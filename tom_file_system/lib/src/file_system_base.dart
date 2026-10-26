/// What every [TomFileSystem] does the same way, written once: resolving
/// URIs against the root, text over bytes and the save announcements.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'file_system.dart';

/// A [TomFileSystem] whose implementation supplies the primitives — list,
/// stat, read, write, create, rename, trash, delete, watch — and announces
/// its own changes with [emitChange].
abstract class TomFileSystemBase implements TomFileSystem {
  /// [root] must be an absolute directory URI.
  TomFileSystemBase(Uri root)
    : root = root.path.endsWith('/')
          ? root
          : root.replace(path: '${root.path}/');

  @override
  final Uri root;

  final _changes = StreamController<TomFileChangeEvent>.broadcast();
  final _saves = StreamController<Uri>.broadcast();
  final _willSaves = StreamController<TomWillSaveEvent>.broadcast();

  /// [uri] made absolute against [root].
  Uri absolute(Uri uri) => uri.hasScheme ? uri : root.resolveUri(uri);

  @override
  Uri uriOf(String path) =>
      path.isEmpty ? root : root.resolveUri(Uri(path: path));

  @override
  String? pathOf(Uri uri) {
    final target = absolute(uri);
    if (target.scheme != root.scheme || target.authority != root.authority) {
      return null;
    }
    final base = [
      for (final s in root.pathSegments)
        if (s.isNotEmpty) s,
    ];
    final segments = [
      for (final s in target.pathSegments)
        if (s.isNotEmpty) s,
    ];
    if (segments.length < base.length) return null;
    for (var i = 0; i < base.length; i++) {
      if (segments[i] != base[i]) return null;
    }
    return segments.skip(base.length).join('/');
  }

  /// The last segment of [uri]'s path — a file's or folder's own name.
  String nameOf(Uri uri) {
    final segments = absolute(uri).pathSegments.where((s) => s.isNotEmpty);
    return segments.isEmpty ? '' : segments.last;
  }

  /// Announces a change made through this file system.
  void emitChange(Uri uri, TomFileChangeType type) {
    if (!_changes.isClosed) {
      _changes.add(TomFileChangeEvent(uri: absolute(uri), type: type));
    }
  }

  @override
  Future<String> readText(Uri uri) async =>
      utf8.decode((await read(uri)).bytes, allowMalformed: true);

  @override
  Future<TomFileRevision> writeText(
    Uri uri,
    String text, {
    TomFileRevision? expected,
  }) => write(uri, Uint8List.fromList(utf8.encode(text)), expected: expected);

  @override
  Future<void> save(Uri uri) async {
    final content = await readText(uri);
    final event = TomWillSaveEvent(
      uri: absolute(uri),
      content: content,
      reason: TomSaveReason.manual,
    );
    _willSaves.add(event);
    // A listener may change what is saved.
    if (event.content != content) await writeText(uri, event.content);
    _saves.add(absolute(uri));
  }

  @override
  Stream<TomFileChangeEvent> get onDidChange => _changes.stream;

  @override
  Stream<Uri> get onDidSave => _saves.stream;

  @override
  Stream<TomWillSaveEvent> get onWillSave => _willSaves.stream;

  @override
  Future<void> dispose() async {
    await _changes.close();
    await _saves.close();
    await _willSaves.close();
  }
}
