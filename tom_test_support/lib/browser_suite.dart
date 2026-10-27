/// Running a Flutter package's browser-only tests from its ordinary suite.
///
/// A package keeps its `@TestOn('browser')` files in `test/browser/`. An
/// ordinary `flutter test` skips them silently, so a browser half that only
/// those files execute would be compiled and never run. The package's own
/// suite therefore holds one VM test that drives the directory on Chrome and
/// fails when it does not pass:
///
/// ```dart
/// final suite = TomBrowserSuite();
/// test('test/browser passes on Chrome', () async {
///   final failure = TomBrowserSuite.failureOf(await suite.run());
///   expect(failure, isNull, reason: failure);
/// }, skip: suite.skipReason);
/// ```
///
/// Framework-free like the rest of this package: it answers a skip reason and
/// a failure, and the caller's test framework asserts on them.
library;

import 'dart:io';

/// The browser-only tests of the package in [workingDirectory].
final class TomBrowserSuite {
  /// The directory, relative to [workingDirectory], holding the browser tests.
  final String directory;

  /// The package root; the current directory by default, which is where
  /// `flutter test` runs a package's suite.
  final String workingDirectory;

  final Map<String, String> _environment;

  /// The variable that turns the run off, for a machine without Chrome.
  static const skipVariable = 'TOM_SKIP_BROWSER_TESTS';

  TomBrowserSuite({
    this.directory = 'test/browser',
    String? workingDirectory,
    Map<String, String>? environment,
  }) : workingDirectory = workingDirectory ?? Directory.current.absolute.path,
       _environment = environment ?? Platform.environment;

  /// The `flutter` executable of the SDK running this suite, or null.
  ///
  /// `flutter test` sets `FLUTTER_ROOT` for the processes it starts; the
  /// suite uses the SDK it is already running under rather than whichever
  /// `flutter` a `PATH` lookup would find.
  String? get flutterExecutable {
    final root = _environment['FLUTTER_ROOT'];
    if (root == null || root.isEmpty) return null;
    return '$root/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}';
  }

  /// Why the run cannot happen here, naming what would make it run; null when
  /// it can.
  String? get skipReason {
    if (_environment[skipVariable] == '1') {
      return '$skipVariable=1 is set; unset it to run $directory on Chrome';
    }
    final flutter = flutterExecutable;
    if (flutter == null || !File(flutter).existsSync()) {
      return 'FLUTTER_ROOT does not point at a flutter executable '
          '(${_environment['FLUTTER_ROOT'] ?? 'unset'})';
    }
    if (!Directory('$workingDirectory/$directory').existsSync()) {
      return 'no $directory directory in $workingDirectory';
    }
    return null;
  }

  /// Runs `flutter test --platform chrome` over [directory].
  ///
  /// Throws a [StateError] when [skipReason] is not null.
  Future<ProcessResult> run() {
    final reason = skipReason;
    if (reason != null) throw StateError(reason);
    return Process.run(flutterExecutable!, [
      'test',
      '--platform',
      'chrome',
      directory,
    ], workingDirectory: workingDirectory);
  }

  /// Why [result] is not a passing browser suite, with its output; null when
  /// it is one.
  ///
  /// A run that exits 0 must also say `All tests passed`: `flutter test` over
  /// a directory whose every file was skipped exits 0 and asserted nothing.
  static String? failureOf(ProcessResult result) {
    final out = '${result.stdout}';
    if (result.exitCode != 0) {
      return 'the browser suite failed (exit ${result.exitCode}).\n'
          'stdout:\n$out\nstderr:\n${result.stderr}';
    }
    if (!out.contains('All tests passed')) {
      return 'the browser suite exited 0 without reporting a passing run, '
          'which is what a fully-skipped directory looks like.\n'
          'stdout:\n$out';
    }
    return null;
  }
}
