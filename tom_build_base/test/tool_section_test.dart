/// A tool's section in a project's `buildkit.yaml` may hold `defines:` and
/// `<MODE>-defines:` beside the tool's own keys (ToolRunner merges them into
/// the project's defines). The tool never sees them: tom_build_base hands it
/// its section without them, through [TomBuildConfig.readToolSection],
/// [withoutDefines] and [TomBuildConfig.toolOptions]. So a tool that refuses
/// unknown keys, or a section holding only defines, works.
///
/// Test IDs: BB-TSEC-1..4.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base.dart';
import 'package:yaml/yaml.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bb_tsec_'));
  tearDown(() => dir.deleteSync(recursive: true));

  void project(String yaml) =>
      File(p.join(dir.path, 'buildkit.yaml')).writeAsStringSync(yaml);

  test('BB-TSEC-1: isDefinesKey names defines and <MODE>-defines '
      '[2026-11-16]', () {
    expect(isDefinesKey('defines'), isTrue);
    expect(isDefinesKey('DEV-defines'), isTrue);
    expect(isDefinesKey('command'), isFalse);
    expect(isDefinesKey('undefined'), isFalse);
  });

  test('BB-TSEC-2: withoutDefines drops them and keeps the rest, nested maps '
      'as plain maps [2026-11-16]', () {
    final section =
        loadYaml('''
command: dart test
defines: {a: 1}
CI-defines: {a: 2}
nested: {defines: kept}
''')
            as YamlMap;
    expect(withoutDefines(section), {
      'command': 'dart test',
      'nested': {'defines': 'kept'},
    });
  });

  test('BB-TSEC-3: readToolSection hands the section without defines; a '
      'section of only defines is no section [2026-11-16]', () {
    project('''
testkit:
  command: make test
  report: junit
  defines: {x: y}
''');
    expect(TomBuildConfig.readToolSection(dir: dir.path, toolKey: 'testkit'), {
      'command': 'make test',
      'report': 'junit',
    });
    project('''
testkit:
  defines: {x: y}
  DEV-defines: {x: z}
''');
    expect(
      TomBuildConfig.readToolSection(dir: dir.path, toolKey: 'testkit'),
      isNull,
    );
    project('testkit: not-a-map\n');
    expect(
      TomBuildConfig.readToolSection(dir: dir.path, toolKey: 'testkit'),
      'not-a-map',
      reason: 'a malformed section is handed on for the tool to report',
    );
    expect(
      TomBuildConfig.readToolSection(dir: dir.path, toolKey: 'compiler'),
      isNull,
    );
  });

  test('BB-TSEC-4: TomBuildConfig.toolOptions holds no defines '
      '[2026-11-16]', () {
    project('''
versioner:
  variable-prefix: tom
  defines: {x: y}
  DEV-defines: {x: z}
''');
    final config = TomBuildConfig.load(dir: dir.path, toolKey: 'versioner')!;
    expect(config.toolOptions, {'variable-prefix': 'tom'});
  });
}
