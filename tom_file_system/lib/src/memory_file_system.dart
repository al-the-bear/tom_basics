/// A [TomFileSystem] held in memory — for tests, previews and anything
/// that must not touch a disk.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'file_system.dart';
import 'file_system_base.dart';

class _MemoryFile {
  _MemoryFile(this.bytes, this.modified);

  Uint8List bytes;
  DateTime modified;
}

/// Thrown for a path that is not there, or not the kind of entry asked for.
class TomFileSystemException implements Exception {
  TomFileSystemException(this.message, this.uri);

  final String message;
  final Uri uri;

  @override
  String toString() => 'TomFileSystemException: $message: ${uri.path}';
}

/// Files and folders keyed by their absolute path. Writes are atomic by
/// construction, revisions are checked like on disk, there is no trash, and
/// [watch] reports every change made through it.
class TomMemoryFileSystem extends TomFileSystemBase {
  /// [root] defaults to `/`; [seed] maps absolute paths to text.
  TomMemoryFileSystem({Uri? root, Map<String, String> seed = const {}})
    : super(root ?? Uri.directory('/')) {
    for (final entry in seed.entries) {
      _setFile(
        _key(Uri.file(entry.key)),
        Uint8List.fromList(utf8.encode(entry.value)),
      );
    }
  }

  final Map<String, _MemoryFile> _files = {};

  /// Folders created explicitly; a folder holding a file exists implicitly.
  final Set<String> _directories = {};

  final _watch = StreamController<TomFileChange>.broadcast();

  /// The paths of every file, sorted — for tests.
  List<String> get paths => _files.keys.toList()..sort();

  DateTime _tick = DateTime.utc(2026);

  /// Every write moves the clock, so two writes never share a time.
  DateTime _now() => _tick = _tick.add(const Duration(milliseconds: 1));

  String _key(Uri uri) {
    final path = absolute(uri).path;
    final decoded = Uri.decodeComponent(path);
    return decoded.length > 1 && decoded.endsWith('/')
        ? decoded.substring(0, decoded.length - 1)
        : decoded;
  }

  Uri _uriOfKey(String key) => Uri.file(key);

  void _setFile(String key, Uint8List bytes) {
    final file = _files[key];
    if (file == null) {
      _files[key] = _MemoryFile(bytes, _now());
    } else {
      file
        ..bytes = bytes
        ..modified = _now();
    }
  }

  bool _isDirectory(String key) =>
      key == '/' ||
      _directories.contains(key) ||
      _files.keys.any((f) => f.startsWith('$key/')) ||
      _directories.any((d) => d.startsWith('$key/'));

  void _changed(String key, TomFileChangeType type) {
    final uri = _uriOfKey(key);
    emitChange(uri, type);
    if (!_watch.isClosed) {
      _watch.add(TomFileChange(pathOf(uri) ?? key, uri));
    }
  }

  TomFileEntry _entry(String key, {required bool directory}) {
    final uri = _uriOfKey(key);
    final file = _files[key];
    return TomFileEntry(
      name: key.split('/').last,
      path: pathOf(uri) ?? key,
      uri: uri,
      kind: directory ? TomFileEntryKind.directory : TomFileEntryKind.file,
      size: directory ? 0 : file!.bytes.length,
      modified: file?.modified ?? _tick,
    );
  }

  @override
  Future<List<TomFileEntry>> list(Uri directory) async {
    final key = _key(directory);
    final prefix = key == '/' ? '/' : '$key/';
    final files = <String>{};
    final dirs = <String>{};
    for (final path in [..._files.keys, ..._directories]) {
      if (!path.startsWith(prefix)) continue;
      final rest = path.substring(prefix.length);
      if (rest.isEmpty) continue;
      final slash = rest.indexOf('/');
      if (slash != -1) {
        dirs.add('$prefix${rest.substring(0, slash)}');
      } else if (_files.containsKey(path)) {
        files.add(path);
      } else {
        dirs.add(path);
      }
    }
    return [
      for (final d in dirs) _entry(d, directory: true),
      for (final f in files) _entry(f, directory: false),
    ];
  }

  @override
  Future<TomFileEntry?> stat(Uri uri) async {
    final key = _key(uri);
    if (_files.containsKey(key)) return _entry(key, directory: false);
    if (_isDirectory(key)) return _entry(key, directory: true);
    return null;
  }

  @override
  Future<TomFileContent> read(Uri uri) async {
    final file = _files[_key(uri)];
    if (file == null) throw TomFileSystemException('No such file', uri);
    final bytes = Uint8List.fromList(file.bytes);
    return TomFileContent(bytes, TomFileRevision.of(bytes, file.modified));
  }

  @override
  Future<String?> readSlice(
    Uri uri, {
    required int maxBytes,
    required bool fromEnd,
  }) async {
    final file = _files[_key(uri)];
    if (file == null) return null;
    final bytes = file.bytes;
    final cut = bytes.length > maxBytes;
    final start = fromEnd && cut ? bytes.length - maxBytes : 0;
    final end = cut ? start + maxBytes : bytes.length;
    final text = utf8.decode(bytes.sublist(start, end), allowMalformed: true);
    if (!cut) return text;
    return fromEnd ? tomTrimToLineStart(text) : tomTrimToLineEnd(text);
  }

  @override
  Future<TomFileRevision> write(
    Uri uri,
    Uint8List bytes, {
    TomFileRevision? expected,
  }) async {
    final key = _key(uri);
    if (expected != null) {
      final file = _files[key];
      final current = file == null
          ? null
          : TomFileRevision.of(file.bytes, file.modified);
      if (current != expected) throw TomFileConflict(absolute(uri), current);
    }
    final isNew = !_files.containsKey(key);
    _setFile(key, Uint8List.fromList(bytes));
    _changed(
      key,
      isNew ? TomFileChangeType.created : TomFileChangeType.modified,
    );
    return TomFileRevision.of(bytes, _files[key]!.modified);
  }

  @override
  Future<void> create(Uri uri, {bool directory = false}) async {
    final key = _key(uri);
    if (directory) {
      final segments = key.split('/');
      for (var i = 2; i <= segments.length; i++) {
        _directories.add(segments.sublist(0, i).join('/'));
      }
      _changed(key, TomFileChangeType.created);
      return;
    }
    if (_files.containsKey(key) || _isDirectory(key)) {
      throw TomFileSystemException('Already exists', uri);
    }
    _setFile(key, Uint8List(0));
    _changed(key, TomFileChangeType.created);
  }

  @override
  Future<void> rename(Uri from, Uri to) async {
    final source = _key(from);
    final target = _key(to);
    if (_files.containsKey(target) || _isDirectory(target)) {
      throw TomFileSystemException('Already exists', to);
    }
    if (_files.containsKey(source)) {
      _files[target] = _files.remove(source)!;
    } else if (_isDirectory(source)) {
      String moved(String path) => '$target${path.substring(source.length)}';
      for (final path in _files.keys.toList()) {
        if (path.startsWith('$source/')) {
          _files[moved(path)] = _files.remove(path)!;
        }
      }
      for (final path in _directories.toList()) {
        if (path == source || path.startsWith('$source/')) {
          _directories
            ..remove(path)
            ..add(moved(path));
        }
      }
    } else {
      throw TomFileSystemException('No such entry', from);
    }
    _changed(source, TomFileChangeType.deleted);
    _changed(target, TomFileChangeType.created);
  }

  /// There is no trash in memory: the caller asks before [delete].
  @override
  Future<bool> trash(Uri uri) async => false;

  @override
  Future<void> delete(Uri uri) async {
    final key = _key(uri);
    final existed = _files.remove(key) != null || _isDirectory(key);
    _files.removeWhere((path, _) => path.startsWith('$key/'));
    _directories.removeWhere((d) => d == key || d.startsWith('$key/'));
    if (existed) _changed(key, TomFileChangeType.deleted);
  }

  @override
  Future<bool> exists(Uri uri) async {
    final key = _key(uri);
    return _files.containsKey(key) || _isDirectory(key);
  }

  @override
  Stream<TomFileChange>? watch({bool Function(String path)? descend}) =>
      _watch.stream;

  @override
  Future<void> dispose() async {
    await _watch.close();
    await super.dispose();
  }
}
