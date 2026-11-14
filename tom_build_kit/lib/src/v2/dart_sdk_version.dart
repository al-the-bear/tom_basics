/// The version of the Dart SDK on `PATH`, read once per run.
library;

import 'package:tom_build_base/tom_build_base.dart' show ProcessRunner;

Future<String?>? _dartSdkVersion;

/// The version `dart --version` reports (e.g. `3.13.7`), or null when it
/// cannot be read. The process runs once per buildkit run.
Future<String?> dartSdkVersion() => _dartSdkVersion ??= _read();

Future<String?> _read() async {
  try {
    final result = await ProcessRunner.run('dart', ['--version']);
    final output = result.stdout + result.stderr;
    final match = RegExp(r'Dart SDK version:\s+(\S+)').firstMatch(output);
    if (match != null) return match.group(1);
    return RegExp(r'(\d+\.\d+\.\d+)').firstMatch(output)?.group(1);
  } catch (_) {
    return null;
  }
}
