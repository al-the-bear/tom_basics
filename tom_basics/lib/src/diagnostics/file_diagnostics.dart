/// The rolling log file: structured events, one JSON object per line.
///
/// The one `TomDiagnostics` backend that needs a platform, which is why it is
/// its own entry point (`package:tom_basics/diagnostics_io.dart`): a library
/// importing `dart:io` does not link under dart2js at all, and the port must.
///
/// ## Why a file at all
///
/// The in-memory ring is bounded and dies with the process — exactly the wrong
/// lifetime for a record somebody reads after the fact. A user reporting "it
/// did nothing" has closed the app by the time anyone asks. A file is what
/// makes a report reconstructable afterwards.
///
/// ## Structured to the last moment
///
/// One **JSON object per line**, produced from [TomDiagnosticEvent.toMap].
/// The sink never accepts a rendered sentence, which is what keeps the
/// redaction rule structural: while the payload is still data, the sink can
/// refuse a value it cannot encode; once a caller has interpolated something
/// into a string, nothing downstream can tell a locator from a password.
///
/// A value that is not JSON-shaped is therefore written as
/// `"<non-JSON TypeName>"` rather than through `toString()`. That keeps the
/// finding — somebody logged the wrong kind of thing — and leaks nothing, which
/// a `toString()` of a token would not.
library;

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'diagnostics.dart';

/// Appends structured events to a rolling file.
class TomFileDiagnostics implements TomDiagnostics {
  TomFileDiagnostics({
    required String path,
    this.maxBytes = 1 << 20,
    this.generations = 3,
    this.minimumLevel = TomDiagnosticLevel.info,
  })  : _path = path,
        assert(maxBytes > 0, 'a zero-byte file rotates on every line'),
        assert(generations > 0, 'zero generations keeps nothing');

  /// The size at which the current file is rotated. One mebibyte by default:
  /// large enough that an ordinary session never rotates, small enough that a
  /// bug report can carry the whole set.
  @visibleForTesting
  final int maxBytes;

  /// How many files are kept, the live one included. Older ones are deleted,
  /// because "rolling" with no ceiling is unbounded growth wearing a different
  /// name.
  @visibleForTesting
  final int generations;

  /// Events at or above this level are written; the rest are dropped at the
  /// sink rather than at each call site.
  ///
  /// `debug` is excluded by default. A debug line is written to be read while
  /// somebody is looking, and the file exists for the case where nobody was.
  ///
  /// Settable, for the reason [path] is: an application typically keeps it in
  /// settings it reads after start-up, and a support request that needs
  /// verbose output is answered by changing it on a running app.
  TomDiagnosticLevel minimumLevel;

  String _path;
  Object? _failure;

  /// Where the live file is.
  String get path => _path;

  /// Moves the log, carrying nothing with it.
  ///
  /// An application typically keeps the location in settings it reads *after*
  /// start-up — so the sink is built at a default path and repointed once the
  /// settings name another. Prior generations are left where
  /// they are rather than moved: they are a record of what happened at the old
  /// location, and rewriting history to make a directory listing tidier is not
  /// a trade a log should make.
  ///
  /// A sink that had given up is given another chance, because the reason it
  /// gave up may have been the old path.
  set path(String value) {
    if (value == _path) return;
    _path = value;
    _failure = null;
  }

  /// Why this sink stopped writing, or null while it is working.
  ///
  /// It stops on the first failure rather than retrying. The sink cannot tell a
  /// transient fault from a full disk or a read-only directory, and retrying
  /// per line turns the second into a stall on every operation that logs. A
  /// surface that wants to say so reads this; nothing else changes.
  Object? get failure => _failure;

  @override
  void log(TomDiagnosticEvent event) {
    if (_failure != null) return;
    if (event.level.index > minimumLevel.index) return;
    final line = '${jsonEncode(event.toMap(), toEncodable: _encodable)}\n';
    try {
      final file = File(_path);
      // Checked before the append rather than after, so the ceiling is a
      // ceiling: rotating afterwards would let one oversized line live in a
      // file that is already over budget until the *next* line arrives.
      if (file.existsSync() && file.lengthSync() + line.length > maxBytes) {
        _rotate();
      } else {
        file.parent.createSync(recursive: true);
      }
      File(_path).writeAsStringSync(line, mode: FileMode.append, flush: true);
    } on FileSystemException catch (e) {
      _failure = e;
    }
  }

  /// Shifts `<path>.n` → `<path>.n+1`, drops the oldest, and frees `<path>`.
  void _rotate() {
    // The oldest goes first, so that every move below lands on a name that is
    // free. [_moveTo] insists on that on every platform — see there.
    final oldest = File('$_path.${generations - 1}');
    if (oldest.existsSync()) oldest.deleteSync();
    for (var n = generations - 2; n >= 1; n--) {
      final file = File('$_path.$n');
      if (file.existsSync()) _moveTo(file, '$_path.${n + 1}');
    }
    if (generations > 1) {
      _moveTo(File(_path), '$_path.1');
    } else {
      // One generation means the live file and nothing else, so rotation is a
      // truncation. Deleting and re-creating rather than keeping a `.1` nobody
      // asked for.
      File(_path).deleteSync();
    }
  }

  /// Renames [file] to [target], refusing when [target] exists.
  ///
  /// **Windows semantics on every platform.** POSIX `rename` replaces an
  /// existing target and Windows refuses, so a rotation that relied on the
  /// replacement would work on the machines the suite runs on and stop the
  /// sink dead on the third rotation on Windows — silently, since a refused
  /// write only sets [failure]. Refusing here makes the order of [_rotate]
  /// load-bearing wherever it runs, so a rotation that renamed onto an
  /// occupied name fails the generation tests on macOS and Linux as it would
  /// on Windows, instead of there alone.
  static void _moveTo(File file, String target) {
    if (File(target).existsSync()) {
      throw FileSystemException(
        'log rotation would replace an existing generation',
        target,
      );
    }
    file.renameSync(target);
  }

  /// The one escape from JSON, and it carries a type rather than a value.
  static Object? _encodable(Object? value) => '<non-JSON ${value.runtimeType}>';
}
