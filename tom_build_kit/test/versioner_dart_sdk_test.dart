/// `:versioner` without a readable Dart SDK version fails the project and
/// writes nothing.
///
/// A host where the versioner ran without `dart` on its PATH (a fleet peer
/// reached over SSH, a LaunchAgent) wrote `dartSdkVersion = ''` and reported
/// "version file generated"; the generated-newer-wins merge driver then
/// carried that file to every machine. A version file that cannot say which
/// SDK built the binary is not stamped: the run for that project fails,
/// naming `dart`, and an existing version file is left as it was.
///
/// Test IDs: VSDK-1 – VSDK-3
@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/src/v2/executors/versioner_executor.dart';

Directory _writeProject() {
  final dir = Directory.systemTemp.createTempSync('vsdk_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
    'name: zom_vsdk\n'
    'version: 1.2.3\n'
    'environment:\n'
    "  sdk: '>=3.0.0 <4.0.0'\n",
  );
  File(
    p.join(dir.path, 'buildkit.yaml'),
  ).writeAsStringSync('versioner:\n  variable-prefix: zomVsdk\n');
  return dir;
}

String _stampPath(Directory project) =>
    p.join(project.path, 'lib', 'src', 'version.versioner.dart');

Future<ItemResult> _run(
  Directory project,
  Future<String?> Function() sdkVersion, {
  bool dryRun = false,
}) => VersionerExecutor(sdkVersion: sdkVersion).execute(
  CommandContext(
    fsFolder: FsFolder(path: project.path),
    natures: const [],
    executionRoot: project.path,
  ),
  CliArgs(dryRun: dryRun),
);

void main() {
  late Directory project;
  setUp(() => project = _writeProject());
  tearDown(() => project.deleteSync(recursive: true));

  test('VSDK-1: no SDK version: the project fails, naming `dart`, and no '
      'version file is written [2026-11-15]', () async {
    for (final dryRun in [false, true]) {
      final result = await _run(project, () async => null, dryRun: dryRun);
      expect(result.success, isFalse, reason: 'dryRun: $dryRun');
      expect(result.error, contains('`dart --version`'));
      expect(result.error, contains('PATH'));
      expect(File(_stampPath(project)).existsSync(), isFalse);
    }
  });

  test(
    'VSDK-2: an existing version file stays as it was [2026-11-15]',
    () async {
      final first = await _run(project, () async => '3.13.7');
      expect(first.success, isTrue, reason: first.error);
      final stamp = File(_stampPath(project));
      final before = stamp.readAsStringSync();
      expect(before, contains("dartSdkVersion = '3.13.7'"));

      final second = await _run(project, () async => null);
      expect(second.success, isFalse);
      expect(stamp.readAsStringSync(), before);
    },
  );

  test('VSDK-3: buildkit run with a PATH that has no `dart` fails the project '
      'and writes nothing [2026-11-15]', () async {
    final kit = Directory.current.path;
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        '--packages=${p.join(kit, '.dart_tool', 'package_config.json')}',
        p.join(kit, 'bin', 'buildkit.dart'),
        ':versioner',
      ],
      workingDirectory: project.path,
      environment: {'PATH': '/usr/bin:/bin'},
      includeParentEnvironment: true,
    );
    final out = '${result.stdout}${result.stderr}';
    expect(result.exitCode, isNot(0), reason: out);
    // Piped output is plain text: the console drops the backticks.
    expect(out, contains('dart --version failed (is dart on PATH?)'));
    expect(out, isNot(contains('version file generated')));
    expect(File(_stampPath(project)).existsSync(), isFalse, reason: out);
  }, skip: Platform.isWindows ? 'PATH layout of a POSIX host' : false);
}
