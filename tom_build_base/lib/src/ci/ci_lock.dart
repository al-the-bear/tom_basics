/// A lock taken the way every session in the workspace takes the flutter lock.
///
/// Two `flutter` invocations at once corrupt each other — the shared build
/// cache, the tester's ports, the tool's own lockfile handling. Sessions in
/// the workspace therefore wrap every flutter command in
///
/// ```bash
/// until mkdir "$C/ztmp/flutter.lock" 2>/dev/null; do sleep 10; done
/// …
/// rmdir "$C/ztmp/flutter.lock"
/// ```
///
/// and this is the same lock, by the same means: `mkdir` is atomic on every
/// platform, so whoever creates the directory holds it. The directory stays
/// **empty** so a session's plain `rmdir` keeps working on it.
///
/// [CiProcessRunner] takes it around each child process, not for a whole run:
/// a person running a full CI and an agent running one `flutter test` then
/// take turns instead of corrupting each other, and neither waits an hour for
/// the other.
library;

import 'dart:async';
import 'dart:io';

/// An advisory, directory-based lock.
class CiLock {
  CiLock(this.path);

  /// The lock directory.
  final String path;

  bool _held = false;

  /// Whether this object currently holds the lock.
  bool get held => _held;

  /// Takes the lock if it is free. Returns whether it was taken.
  ///
  /// By the operating system's `mkdir`, not `Directory.createSync`: Dart's
  /// create succeeds when the directory already exists, so it cannot tell a
  /// lock it took from a lock somebody else holds (measured). `mkdir` fails on
  /// an existing directory, atomically, on macOS, Linux and Windows alike.
  bool _tryAcquire() {
    if (_held) return true;
    Directory(path).parent.createSync(recursive: true);
    final result = Platform.isWindows
        ? Process.runSync('cmd', ['/c', 'mkdir', path])
        : Process.runSync('mkdir', [path]);
    _held = result.exitCode == 0;
    return _held;
  }

  /// Takes the lock, waiting while somebody else holds it.
  ///
  /// [onWait] is called with the time waited so far: once when the wait
  /// begins, then every [reportEvery], so a person watching the console sees
  /// why nothing is happening and whose lock it is.
  Future<void> acquire({
    Duration poll = const Duration(seconds: 5),
    Duration reportEvery = const Duration(minutes: 1),
    void Function(Duration waited)? onWait,
  }) async {
    final watch = Stopwatch()..start();
    var nextReport = Duration.zero;
    while (!_tryAcquire()) {
      if (onWait != null && watch.elapsed >= nextReport) {
        onWait(watch.elapsed);
        nextReport = watch.elapsed + reportEvery;
      }
      await Future<void>.delayed(poll);
    }
  }

  /// Releases the lock if held. Safe to call more than once, and from a
  /// signal handler.
  void release() {
    if (!_held) return;
    _held = false;
    try {
      Directory(path).deleteSync();
    } on FileSystemException {
      // Already gone (removed by hand); nothing left to release.
    }
  }
}
