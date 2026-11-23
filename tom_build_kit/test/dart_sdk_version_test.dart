/// Reading the Dart SDK version (`dart --version`) works where `dart` on the
/// PATH is a batch file.
///
/// On Windows Flutter puts `flutter\bin\dart.bat` on the PATH. A compiled
/// buildkit.exe starts a process without a shell, which finds only `.exe`
/// files, so `dart --version` failed and every `:versioner` stopped with
/// "cannot read the Dart SDK version" (legiondary01, 2026-11-19; reproduced
/// there with a compiled probe on 2026-11-23). On Windows the command runs
/// in a shell, which finds `dart.bat`.
///
/// Test IDs: DSV-1 – DSV-3
library;

import 'dart:io' show ProcessException;

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base.dart' show ProcessRunResult;
import 'package:tom_build_kit/src/v2/dart_sdk_version.dart';

void main() {
  /// A runner that records how it was called and answers [stdout].
  ({List<bool> shells, DartCommandRunner run}) fake(String stdout) {
    final shells = <bool>[];
    Future<ProcessRunResult> run(
      String executable,
      List<String> args, {
      required bool runInShell,
    }) async {
      expect(executable, 'dart');
      expect(args, ['--version']);
      shells.add(runInShell);
      return ProcessRunResult(exitCode: 0, stdout: stdout, stderr: '');
    }

    return (shells: shells, run: run);
  }

  test('DSV-1: on Windows `dart --version` runs in a shell, so a dart.bat on '
      'the PATH is found; elsewhere without one [2026-11-23]', () async {
    for (final windows in [true, false]) {
      final f = fake('Dart SDK version: 3.13.7 (stable) on "windows_x64"\n');
      final version = await readDartSdkVersion(run: f.run, windows: windows);
      expect(version, '3.13.7');
      expect(f.shells, [windows]);
    }
  });

  test('DSV-2: the version is read from stdout or stderr, and from a bare '
      'version number [2026-11-23]', () async {
    expect(
      await readDartSdkVersion(
        run: fake('3.14.0-12.0.dev').run,
        windows: false,
      ),
      '3.14.0',
    );
    Future<ProcessRunResult> onStderr(
      String executable,
      List<String> args, {
      required bool runInShell,
    }) async => const ProcessRunResult(
      exitCode: 0,
      stdout: '',
      stderr: 'Dart SDK version: 2.19.6 (stable)',
    );
    expect(await readDartSdkVersion(run: onStderr, windows: false), '2.19.6');
  });

  test('DSV-3: a `dart` that cannot be started gives no version, not an '
      'error [2026-11-23]', () async {
    Future<ProcessRunResult> missing(
      String executable,
      List<String> args, {
      required bool runInShell,
    }) async => throw const ProcessException('dart', ['--version']);
    expect(await readDartSdkVersion(run: missing, windows: true), isNull);
    expect(
      await readDartSdkVersion(run: fake('no version here').run, windows: true),
      isNull,
    );
  });
}
