/// The [TomFileSystem] over a local folder.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../file_system.dart';
import '../file_system_base.dart';
import 'directory_watches.dart';
import 'windows_recycle_bin.dart';
import 'xdg_trash.dart';

/// A local folder as a [TomFileSystem].
///
/// Writes go to a sibling temporary file, flushed and renamed over the
/// target. A link is listed with where it leads and is not expanded when it
/// leaves the root or loops back into its own ancestors. A delete goes to
/// Finder's Trash, the freedesktop.org trash (through `gio` or `trash-put`,
/// else written directly), or the Windows Recycle Bin.
class TomLocalFileSystem extends TomFileSystemBase {
  /// [watchEachDirectory] chooses how [watch] is recursive: one watch per
  /// directory ([TomDirectoryWatches]) or the platform's own recursive
  /// watch. It is true on Linux, where `Directory.watch` is not recursive,
  /// and false elsewhere; a test sets it to run the Linux way on any host.
  TomLocalFileSystem(String root, {bool? watchEachDirectory})
    : rootPath = p.normalize(p.absolute(root)),
      _watchEachDirectory = watchEachDirectory ?? Platform.isLinux,
      super(Uri.directory(p.normalize(p.absolute(root))));

  /// The root as a local path.
  final String rootPath;

  final bool _watchEachDirectory;

  /// The root's real path, links resolved — what a link target is compared
  /// with.
  late final String _realRoot = () {
    try {
      return Directory(rootPath).resolveSymbolicLinksSync();
    } on FileSystemException {
      return rootPath;
    }
  }();

  /// [uri] as a local path.
  String localPathOf(Uri uri) => p.normalize(absolute(uri).toFilePath());

  String _relative(String local) => p.equals(local, rootPath)
      ? ''
      : p.split(p.relative(local, from: rootPath)).join('/');

  TomFileEntry _entryOf(
    String local, {
    required TomFileEntryKind kind,
    required FileStat stat,
    bool linksToDirectory = false,
    bool linkLeavesRoot = false,
    bool? readable,
  }) => TomFileEntry(
    name: p.basename(local),
    path: _relative(local),
    uri: kind == TomFileEntryKind.directory
        ? Uri.directory(local)
        : Uri.file(local),
    kind: kind,
    size: kind == TomFileEntryKind.file ? stat.size : 0,
    modified: stat.modified,
    linksToDirectory: linksToDirectory,
    linkLeavesRoot: linkLeavesRoot,
    readable: readable ?? _readable(stat),
  );

  @override
  Future<List<TomFileEntry>> list(Uri directory) async {
    final local = localPathOf(directory);
    final relative = _relative(local);
    final realHere = relative.isEmpty
        ? _realRoot
        : p.join(_realRoot, p.joinAll(relative.split('/')));
    final entries = <TomFileEntry>[];
    await for (final entity in Directory(local).list(followLinks: false)) {
      final stat = await entity.stat();
      if (entity is Link) {
        String? target;
        try {
          target = await entity.resolveSymbolicLinks();
        } on FileSystemException {
          target = null;
        }
        final targetType = target == null
            ? null
            : FileSystemEntity.typeSync(target);
        // Compared as real paths: the root itself may sit behind a link
        // (macOS's /var is /private/var), and a resolved target never names
        // the unresolved form.
        final here = p.join(realHere, p.basename(entity.path));
        final inside =
            target != null &&
            (p.isWithin(_realRoot, target) || p.equals(_realRoot, target));
        final ancestor =
            target != null &&
            (p.isWithin(target, here) || p.equals(target, _realRoot));
        entries.add(
          _entryOf(
            entity.path,
            kind: TomFileEntryKind.link,
            stat: stat,
            linksToDirectory: targetType == FileSystemEntityType.directory,
            linkLeavesRoot: !inside || ancestor,
            readable: target != null,
          ),
        );
        continue;
      }
      entries.add(
        _entryOf(
          entity.path,
          kind: entity is Directory
              ? TomFileEntryKind.directory
              : TomFileEntryKind.file,
          stat: stat,
        ),
      );
    }
    return entries;
  }

  /// Whether the owner may read — the case that matters for a single-user
  /// folder; a stat that does not say is taken as readable and the read
  /// itself reports the truth.
  static bool _readable(FileStat stat) =>
      stat.mode == 0 || (stat.mode & 0x100) != 0;

  @override
  Future<TomFileEntry?> stat(Uri uri) async {
    final local = localPathOf(uri);
    final type = FileSystemEntity.typeSync(local, followLinks: true);
    if (type == FileSystemEntityType.notFound) return null;
    return _entryOf(
      local,
      kind: type == FileSystemEntityType.directory
          ? TomFileEntryKind.directory
          : TomFileEntryKind.file,
      stat: await FileStat.stat(local),
    );
  }

  @override
  Future<TomFileContent> read(Uri uri) async {
    final file = File(localPathOf(uri));
    final bytes = await file.readAsBytes();
    return TomFileContent(
      bytes,
      TomFileRevision.of(bytes, await file.lastModified()),
    );
  }

  @override
  Future<String?> readSlice(
    Uri uri, {
    required int maxBytes,
    required bool fromEnd,
  }) async {
    final file = File(localPathOf(uri));
    if (!file.existsSync()) return null;
    final handle = await file.open();
    try {
      final size = await handle.length();
      final cut = size > maxBytes;
      final start = fromEnd && cut ? size - maxBytes : 0;
      await handle.setPosition(start);
      final bytes = await handle.read(cut ? maxBytes : size);
      final text = utf8.decode(bytes, allowMalformed: true);
      if (!cut) return text;
      return fromEnd ? tomTrimToLineStart(text) : tomTrimToLineEnd(text);
    } finally {
      await handle.close();
    }
  }

  @override
  Future<TomFileRevision> write(
    Uri uri,
    Uint8List bytes, {
    TomFileRevision? expected,
  }) async {
    final target = File(localPathOf(uri));
    final existed = target.existsSync();
    if (expected != null) {
      final current = existed
          ? TomFileRevision.of(
              await target.readAsBytes(),
              await target.lastModified(),
            )
          : null;
      if (current != expected) throw TomFileConflict(absolute(uri), current);
    }
    // Atomic: a sibling temporary file, flushed, renamed over the target. A
    // crash leaves either the old file or the new one, never half of one.
    final temp = File(
      p.join(
        target.parent.path,
        '.${p.basename(target.path)}.tom-'
        '${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    final handle = await temp.open(mode: FileMode.writeOnly);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
    await temp.rename(target.path);
    emitChange(
      uri,
      existed ? TomFileChangeType.modified : TomFileChangeType.created,
    );
    return TomFileRevision.of(bytes, await target.lastModified());
  }

  @override
  Future<void> create(Uri uri, {bool directory = false}) async {
    final local = localPathOf(uri);
    if (directory) {
      await Directory(local).create(recursive: true);
    } else {
      await File(local).create(recursive: true, exclusive: true);
    }
    emitChange(uri, TomFileChangeType.created);
  }

  @override
  Future<void> rename(Uri from, Uri to) async {
    final source = localPathOf(from);
    final destination = localPathOf(to);
    if (FileSystemEntity.typeSync(destination) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('already exists', destination);
    }
    await (FileSystemEntity.isDirectorySync(source)
            ? Directory(source)
            : File(source))
        .rename(destination);
    emitChange(from, TomFileChangeType.deleted);
    emitChange(to, TomFileChangeType.created);
  }

  @override
  Future<bool> trash(Uri uri) async {
    final local = localPathOf(uri);
    final moved = await _trash(local);
    if (moved) emitChange(uri, TomFileChangeType.deleted);
    return moved;
  }

  static Future<bool> _trash(String local) async {
    if (Platform.isMacOS) {
      // Finder's own delete, so the item can be put back from the Trash.
      final result = await Process.run('osascript', [
        '-e',
        'tell application "Finder" to delete '
            '(POSIX file ${jsonEncode(local)} as alias)',
      ]);
      return result.exitCode == 0;
    }
    if (Platform.isLinux) {
      // The desktop's own tools first: they know each mount's trash.
      for (final command in const [
        ['gio', 'trash'],
        ['trash-put'],
      ]) {
        try {
          final result = await Process.run(command.first, [
            ...command.skip(1),
            local,
          ]);
          if (result.exitCode == 0) return true;
        } on ProcessException {
          continue;
        }
      }
      // Neither installed: the home trash, as the specification writes it.
      return tomXdgTrash(local);
    }
    if (Platform.isWindows) return tomWindowsRecycle(local);
    return false;
  }

  @override
  Future<void> delete(Uri uri) async {
    final local = localPathOf(uri);
    if (FileSystemEntity.isDirectorySync(local)) {
      await Directory(local).delete(recursive: true);
    } else {
      await File(local).delete();
    }
    emitChange(uri, TomFileChangeType.deleted);
  }

  @override
  Future<bool> exists(Uri uri) async =>
      FileSystemEntity.typeSync(localPathOf(uri)) !=
      FileSystemEntityType.notFound;

  @override
  Stream<TomFileChange>? watch({bool Function(String path)? descend}) {
    if (!FileSystemEntity.isWatchSupported) return null;
    TomFileChange change(String local) =>
        TomFileChange(_relative(local), Uri.file(local));
    if (_watchEachDirectory) {
      return TomDirectoryWatches(
        rootPath,
        descend: descend ?? (_) => true,
      ).stream.map(change);
    }
    try {
      return Directory(
        rootPath,
      ).watch(recursive: true).map((event) => change(event.path));
    } on FileSystemException {
      return null;
    }
  }
}
