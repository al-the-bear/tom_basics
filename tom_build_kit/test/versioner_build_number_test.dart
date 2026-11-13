/// The build number lives in `version.versioner.dart` (build_tom
/// build_cleanup7): `:versioner` counts on from the file it rewrites and
/// writes no `tom_build_state.json`.
///
/// Drives the executor over a throwaway project, like the SCE48 tests.
///
/// Test IDs: VBN-1 – VBN-5
@TestOn('!browser')
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/src/v2/executors/versioner_executor.dart';

void main() {
  late Directory project;

  String stampPath() =>
      p.join(project.path, 'lib', 'src', 'version.versioner.dart');

  int stampBuildNumber() {
    final match = RegExp(
      r'static const int buildNumber = (\d+);',
    ).firstMatch(File(stampPath()).readAsStringSync());
    return int.parse(match!.group(1)!);
  }

  void writeStamp(String text) => File(stampPath())
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  Future<ItemResult> runVersioner() => VersionerExecutor().execute(
    CommandContext(
      fsFolder: FsFolder(path: project.path),
      natures: const [],
      executionRoot: project.path,
    ),
    CliArgs(),
  );

  setUp(() {
    project = Directory.systemTemp.createTempSync('vbn_');
    File(
      p.join(project.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: zom_vbn\nversion: 1.4.0\n');
    File(
      p.join(project.path, 'buildkit.yaml'),
    ).writeAsStringSync('versioner:\n  variable-prefix: zomVbn\n');
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('VBN-1: a project without a versioner file starts at build 1', () async {
    final result = await runVersioner();
    expect(result.success, isTrue, reason: result.error ?? '');
    expect(stampBuildNumber(), 1);
  });

  test('VBN-2: a run counts on from the existing versioner file', () async {
    writeStamp(
      VersionerExecutor.generateVersionFileContent(
        packageName: 'zom_vbn',
        version: '1.3.9',
        buildTime: '2026-11-01T00:00:00Z',
        buildNumber: 41,
        className: 'ZomVbnVersionInfo',
      ),
    );
    final result = await runVersioner();
    expect(result.success, isTrue, reason: result.error ?? '');
    expect(
      stampBuildNumber(),
      42,
      reason: 'the number grows on across a version change, never resets',
    );
    expect(File(stampPath()).readAsStringSync(), contains("'1.4.0'"));
    await runVersioner();
    expect(stampBuildNumber(), 43);
  });

  test('VBN-3: a versioner file without a build number is a named error, '
      'and is left as it is', () async {
    writeStamp('// a hand-edited file\nclass X {}\n');
    final result = await runVersioner();
    expect(result.success, isFalse);
    expect(
      () => VersionerExecutor.nextBuildNumber(File(stampPath())),
      throwsA(
        isA<VersionerFileException>().having(
          (e) => e.message,
          'message',
          allOf(contains(stampPath()), contains('buildNumber')),
        ),
      ),
    );
    expect(
      File(stampPath()).readAsStringSync(),
      '// a hand-edited file\nclass X {}\n',
    );
  });

  test('VBN-4: no tom_build_state.json is read or written', () async {
    File(
      p.join(project.path, 'tom_build_state.json'),
    ).writeAsStringSync('{"buildNumber": 500}');
    await runVersioner();
    expect(stampBuildNumber(), 1, reason: 'the retired file is not read');
    expect(
      File(p.join(project.path, 'tom_build_state.json')).readAsStringSync(),
      '{"buildNumber": 500}',
      reason: 'and not written',
    );
    File(p.join(project.path, 'tom_build_state.json')).deleteSync();
    await runVersioner();
    expect(
      File(p.join(project.path, 'tom_build_state.json')).existsSync(),
      isFalse,
    );
  });

  test('VBN-5: nextBuildNumber reads the configured output file', () {
    final other = File(p.join(project.path, 'lib', 'v.versioner.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('  static const int buildNumber = 9;\n');
    expect(VersionerExecutor.nextBuildNumber(other), 10);
    expect(
      VersionerExecutor.nextBuildNumber(File(p.join(project.path, 'none'))),
      1,
    );
  });
}
