/// The version of the Dart SDK on `PATH`, read once per run.
library;

import 'dart:io' show Platform;

import 'package:tom_build_base/tom_build_base.dart'
    show ProcessRunResult, ProcessRunner;

Future<String?>? _dartSdkVersion;

/// The version `dart --version` reports (e.g. `3.13.7`), or null when it
/// cannot be read. The process runs once per buildkit run.
Future<String?> dartSdkVersion() => _dartSdkVersion ??= readDartSdkVersion();

/// Runs [executable] with [args], in a shell when [runInShell].
typedef DartCommandRunner =
    Future<ProcessRunResult> Function(
      String executable,
      List<String> args, {
      required bool runInShell,
    });

/// Reads the version `dart --version` reports, or null when `dart` cannot
/// be started or names no version.
///
/// On Windows ([windows], default: this host) the command runs in a shell:
/// the `dart` Flutter puts on the PATH is `flutter\bin\dart.bat`, and a
/// process started without a shell finds only `.exe` files, so a compiled
/// buildkit could not start it. [run] stands in for the process (tests).
Future<String?> readDartSdkVersion({
  DartCommandRunner? run,
  bool? windows,
}) async {
  final runner = run ?? _runProcess;
  try {
    final result = await runner('dart', const [
      '--version',
    ], runInShell: windows ?? Platform.isWindows);
    final output = result.stdout + result.stderr;
    final match = RegExp(r'Dart SDK version:\s+(\S+)').firstMatch(output);
    if (match != null) return match.group(1);
    return RegExp(r'(\d+\.\d+\.\d+)').firstMatch(output)?.group(1);
  } catch (_) {
    return null;
  }
}

Future<ProcessRunResult> _runProcess(
  String executable,
  List<String> args, {
  required bool runInShell,
}) => ProcessRunner.run(executable, args, runInShell: runInShell);
