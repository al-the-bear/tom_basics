/// A bare repository on disk, in git's own layout, so git can read it and it
/// can read what git wrote.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../object_id.dart';
import '../object_store.dart';
import '../objects.dart';
import '../pack.dart';
import '../ref_store.dart';
import '../repository.dart';
import '../zlib.dart';

/// Opens the bare repository at [path], creating it (with [defaultBranch] as
/// `HEAD`) when [create] is set and nothing is there.
GitRepository gitOpenDirectory(
  String path, {
  bool create = false,
  String defaultBranch = 'main',
}) {
  final dir = Directory(path);
  final head = File(p.join(path, 'HEAD'));
  if (!head.existsSync()) {
    if (!create) {
      throw FileSystemException('Not a git repository', path);
    }
    for (final sub in [
      'objects/pack',
      'objects/info',
      'refs/heads',
      'refs/tags',
    ]) {
      Directory(p.join(path, sub)).createSync(recursive: true);
    }
    File(p.join(path, 'config')).writeAsStringSync(
      '[core]\n\trepositoryformatversion = 0\n\tfilemode = true\n'
      '\tbare = true\n',
    );
    head.writeAsStringSync('ref: refs/heads/$defaultBranch\n');
  }
  return GitRepository(
    objects: GitDirectoryObjectStore(dir.path),
    refs: GitDirectoryRefStore(dir.path),
  );
}

/// Objects in a git directory: loose objects and packs with their indexes.
class GitDirectoryObjectStore extends GitObjectStore {
  GitDirectoryObjectStore(this.gitDir);

  final String gitDir;

  String get _objects => p.join(gitDir, 'objects');
  String get _packDir => p.join(_objects, 'pack');

  List<_Pack>? _packs;

  List<_Pack> get _loadedPacks {
    final known = _packs;
    if (known != null) return known;
    final dir = Directory(_packDir);
    final packs = <_Pack>[];
    if (dir.existsSync()) {
      for (final idx in dir.listSync().whereType<File>()) {
        if (!idx.path.endsWith('.idx')) continue;
        final pack = File('${idx.path.substring(0, idx.path.length - 4)}.pack');
        if (!pack.existsSync()) continue;
        packs.add(_Pack(GitPackIndex.parse(idx.readAsBytesSync()), pack));
      }
    }
    return _packs = packs;
  }

  String _loosePath(GitObjectId id) {
    final hex = id.hex;
    return p.join(_objects, hex.substring(0, 2), hex.substring(2));
  }

  @override
  Future<GitObject?> read(GitObjectId id) async {
    final loose = File(_loosePath(id));
    if (loose.existsSync()) {
      return GitObject.unframe(gitInflate(loose.readAsBytesSync()));
    }
    for (final pack in _loadedPacks) {
      final offset = pack.index.offsetOf(id);
      if (offset != null) return pack.read(offset, read);
    }
    return null;
  }

  @override
  Future<bool> contains(GitObjectId id) async {
    if (File(_loosePath(id)).existsSync()) return true;
    for (final pack in _loadedPacks) {
      if (pack.index.offsetOf(id) != null) return true;
    }
    return false;
  }

  @override
  Future<GitObjectId> write(GitObject object) async {
    final id = object.id;
    if (await contains(id)) return id;
    final path = _loosePath(id);
    _atomicWrite(path, gitDeflate(object.framed));
    return id;
  }

  /// Keeps the pack as it arrived, with the index this library builds beside
  /// it — the layout `git index-pack` produces.
  @override
  Future<void> writePack(Uint8List pack) async {
    final parsed = await gitReadPack(pack, external: read);
    final missing = <GitObject>[];
    for (final o in parsed.objects) {
      if (!await contains(o.object.id)) missing.add(o.object);
    }
    if (missing.isEmpty) return;
    final name = 'pack-${GitObjectId.fromBytes(parsed.checksum).hex}';
    _atomicWrite(p.join(_packDir, '$name.pack'), pack);
    // The index last: a pack without its index is invisible, an index
    // without its pack would be read.
    _atomicWrite(p.join(_packDir, '$name.idx'), parsed.buildIndex());
    _packs = null;
  }
}

class _Pack {
  _Pack(this.index, this.file);

  final GitPackIndex index;
  final File file;
  Uint8List? _bytes;
  final Map<int, GitObject> _byOffset = {};

  Uint8List get bytes => _bytes ??= file.readAsBytesSync();

  Future<GitObject> read(
    int offset,
    Future<GitObject?> Function(GitObjectId id) resolveId,
  ) async {
    final cached = _byOffset[offset];
    if (cached != null) return cached;
    final object = await gitReadPackEntry(
      bytes,
      offset,
      resolveOffset: (o) => read(o, resolveId),
      resolveId: resolveId,
    );
    // Delta bases are read again and again while a chain resolves; the cache
    // is per pack and lives as long as the store.
    if (_byOffset.length > 4096) _byOffset.clear();
    _byOffset[offset] = object;
    return object;
  }
}

/// Refs in a git directory: loose ref files over `packed-refs`.
///
/// An update takes git's own lock — `<ref>.lock`, created exclusively — so a
/// second writer, this library or git, is refused rather than interleaved.
class GitDirectoryRefStore extends GitRefStore {
  GitDirectoryRefStore(this.gitDir);

  final String gitDir;

  File _loose(String name) => File(p.join(gitDir, name));

  Map<String, GitObjectId> _packed() {
    final file = File(p.join(gitDir, 'packed-refs'));
    if (!file.existsSync()) return {};
    final out = <String, GitObjectId>{};
    for (final line in file.readAsLinesSync()) {
      if (line.isEmpty || line.startsWith('#') || line.startsWith('^')) {
        continue;
      }
      final space = line.indexOf(' ');
      if (space == 40) {
        out[line.substring(41)] = GitObjectId.fromHex(line.substring(0, 40));
      }
    }
    return out;
  }

  @override
  Future<GitObjectId?> read(String name) async {
    final loose = _loose(name);
    if (loose.existsSync()) {
      final text = loose.readAsStringSync().trim();
      if (text.startsWith('ref: ')) return read(text.substring(5));
      return GitObjectId.fromHex(text);
    }
    return _packed()[name];
  }

  @override
  Future<void> write(
    String name,
    GitObjectId id, {
    GitObjectId? expected,
  }) async {
    final target = _loose(name);
    target.parent.createSync(recursive: true);
    final lock = File('${target.path}.lock');
    try {
      lock.createSync(exclusive: true);
    } on FileSystemException {
      throw GitRefConflict(name, expected: expected, actual: await read(name));
    }
    try {
      if (expected != null) {
        final actual = await read(name);
        final matches = expected.isZero ? actual == null : actual == expected;
        if (!matches) {
          throw GitRefConflict(name, expected: expected, actual: actual);
        }
      }
      lock.writeAsStringSync('${id.hex}\n', flush: true);
      lock.renameSync(target.path);
    } finally {
      if (lock.existsSync()) lock.deleteSync();
    }
  }

  @override
  Future<void> delete(String name) async {
    final loose = _loose(name);
    if (loose.existsSync()) loose.deleteSync();
    final packed = _packed();
    if (packed.remove(name) != null) {
      final b = StringBuffer('# pack-refs with: peeled fully-peeled sorted \n');
      for (final e
          in (packed.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)))) {
        b.write('${e.value.hex} ${e.key}\n');
      }
      _atomicWrite(p.join(gitDir, 'packed-refs'), utf8.encode(b.toString()));
    }
  }

  @override
  Future<Map<String, GitObjectId>> list([String prefix = 'refs/']) async {
    final out = <String, GitObjectId>{
      for (final e in _packed().entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
    final refsDir = Directory(p.join(gitDir, 'refs'));
    if (refsDir.existsSync()) {
      for (final f in refsDir.listSync(recursive: true).whereType<File>()) {
        if (f.path.endsWith('.lock')) continue;
        final name = p.posix.joinAll(p.split(p.relative(f.path, from: gitDir)));
        if (!name.startsWith(prefix)) continue;
        final id = await read(name);
        if (id != null) out[name] = id;
      }
    }
    return out;
  }
}

/// Writes [bytes] to a sibling temporary file and renames it over [path], so
/// a reader sees the old file or the new one and never part of either.
void _atomicWrite(String path, List<int> bytes) {
  final target = File(path);
  target.parent.createSync(recursive: true);
  final temp = File('$path.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}');
  temp.writeAsBytesSync(bytes, flush: true);
  temp.renameSync(path);
}
