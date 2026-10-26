/// Recursive watching built from one non-recursive watch per directory.
///
/// Dart's `Directory.watch(recursive: true)` is recursive on macOS and on
/// Windows, and **not on Linux**: measured in a Linux container (Dart 3.10),
/// it reported a folder created in the root and nothing else — not an edit to
/// an existing file one folder down, and not a file written into a folder
/// created after the watch began. inotify watches one directory at a time, so
/// on Linux the tree is watched the way inotify allows: a watch on every
/// directory the browser walks, a new one for each directory that appears,
/// and the watches of a directory that goes are dropped.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Watches [root] and the directories below it that [descend] admits,
/// reporting the absolute path of every change on [stream].
///
/// [descend] is asked with the directory's path relative to [root] (`/`
/// separators), once when its watch would be added; the browser answers it
/// from its last walk, so a folder the walk does not enter — `.git`, a
/// gitignored build folder — is not watched either. Links are not followed:
/// the tree does not follow a link that leaves its root, and a watch that
/// did would see changes the tree never shows.
///
/// A watch on the root that fails ends the stream with the error, which a
/// tree reads as "this folder cannot be watched". A watch on a
/// directory below it that fails — it went away, or it cannot be read — is
/// dropped and the rest keep running.
class TomDirectoryWatches {
  TomDirectoryWatches(
    this.root, {
    required this.descend,
    Stream<FileSystemEvent> Function(String directory)? watchDirectory,
  }) : _watchDirectory = watchDirectory ?? _platformWatch;

  final String root;
  final bool Function(String relativeDirectory) descend;

  /// One directory's non-recursive watch: the platform's, unless a test
  /// drives the events itself — the platform's delivery is not something a
  /// test of this class's bookkeeping can wait on.
  final Stream<FileSystemEvent> Function(String directory) _watchDirectory;

  static Stream<FileSystemEvent> _platformWatch(String directory) =>
      Directory(directory).watch();

  final Map<String, StreamSubscription<FileSystemEvent>> _watches = {};
  bool _stopped = false;

  // Broadcast: a single-subscription controller does not close on a widget
  // test's clock. The watches
  // start with the first listener and stop for good with the last: one
  // instance serves one watch.
  late final StreamController<String> _out = StreamController<String>.broadcast(
    onListen: () => unawaited(
      _watchTree(root).whenComplete(() {
        if (!_started.isCompleted) _started.complete();
      }),
    ),
    onCancel: _stop,
  );

  final Completer<void> _started = Completer<void>();

  /// Completes once the directories present when the stream was listened to
  /// are all watched — before that, a change in one of them may be missed.
  Future<void> get started => _started.future;

  /// The absolute path of each change, once a listener is attached.
  Stream<String> get stream => _out.stream;

  /// How many directories are watched now.
  int get watchedCount => _watches.length;

  String _relative(String absolute) => absolute == root
      ? ''
      : p.split(p.relative(absolute, from: root)).join('/');

  Future<void> _watchTree(String directory) async {
    if (_stopped || _watches.containsKey(directory)) return;
    if (directory != root && !descend(_relative(directory))) return;
    final StreamSubscription<FileSystemEvent> watch;
    try {
      watch = _watchDirectory(directory).listen(
        (event) => _onEvent(event),
        onError: (Object error, StackTrace stack) =>
            _failed(directory, error, stack),
        onDone: () => _gone(directory),
      );
    } on FileSystemException catch (error, stack) {
      _failed(directory, error, stack);
      return;
    }
    _watches[directory] = watch;
    final List<FileSystemEntity> entries;
    try {
      entries = await Directory(directory).list(followLinks: false).toList();
    } on FileSystemException {
      return;
    }
    for (final entry in entries) {
      if (entry is Directory) await _watchTree(entry.path);
    }
  }

  void _onEvent(FileSystemEvent event) {
    if (_stopped) return;
    _out.add(event.path);
    if (event is FileSystemMoveEvent) {
      _dropUnder(event.path);
      final destination = event.destination;
      if (destination != null) {
        _out.add(destination);
        if (event.isDirectory) unawaited(_watchTree(destination));
      }
    } else if (event is FileSystemDeleteEvent) {
      _dropUnder(event.path);
    } else if (event is FileSystemCreateEvent && event.isDirectory) {
      unawaited(_watchTree(event.path));
    }
  }

  void _failed(String directory, Object error, StackTrace stack) {
    if (_stopped) return;
    if (directory == root) {
      _out.addError(error, stack);
      return;
    }
    _dropUnder(directory);
  }

  void _gone(String directory) {
    if (_stopped) return;
    if (directory == root) {
      unawaited(_out.close());
      return;
    }
    _dropUnder(directory);
  }

  /// Ends the watches of [directory] and everything below it.
  void _dropUnder(String directory) {
    final gone = [
      for (final watched in _watches.keys)
        if (watched == directory || p.isWithin(directory, watched)) watched,
    ];
    for (final watched in gone) {
      // Not awaited: a cancel takes effect when called.
      unawaited(_watches.remove(watched)!.cancel());
    }
  }

  void _stop() {
    _stopped = true;
    for (final watch in _watches.values) {
      unawaited(watch.cancel());
    }
    _watches.clear();
  }
}
