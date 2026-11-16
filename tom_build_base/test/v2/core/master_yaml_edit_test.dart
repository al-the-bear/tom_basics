import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:yaml/yaml.dart';

/// `:define`, `:undefine`, `:macro` and `:unmacro` edit `<tool>_master.yaml`
/// in place: only the entry they change is written, so the file's comments,
/// its schema line, its key order and every other section stay as they were.
///
/// Test IDs: BB-MYE-1..3.

const _tool = ToolDefinition(
  name: 'edittool',
  description: 'Tool for the master-file edit tests',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.minimal,
  commands: [
    CommandDefinition(
      name: 'simple',
      description: 'x',
      requiresTraversal: false,
    ),
  ],
);

const _original = '''
# yaml-language-server: \$schema=./schema.json
# The workspace's settings. Keep this comment.

navigation:
  # Excludes for every walk.
  exclude-projects: [zom_*]   # trailing comment

edittool:
  # Workspace defines.
  defines:
    B: two  # B's comment
''';

void main() {
  late Directory workspace;
  late String previousCwd;
  late File master;
  late StringBuffer out;

  setUp(() {
    previousCwd = Directory.current.path;
    workspace = Directory(
      Directory.systemTemp.createTempSync('bb_mye_').resolveSymbolicLinksSync(),
    );
    File(p.join(workspace.path, 'buildkit_master.yaml')).writeAsStringSync('');
    master = File(p.join(workspace.path, 'edittool_master.yaml'))
      ..writeAsStringSync(_original);
    Directory.current = workspace.path;
    out = StringBuffer();
  });
  tearDown(() {
    Directory.current = previousCwd;
    workspace.deleteSync(recursive: true);
  });

  Future<void> run(List<String> args) async {
    final result = await ToolRunner(tool: _tool, output: out).run(args);
    expect(result.success, isTrue, reason: out.toString());
  }

  void expectCommentsKept() {
    final text = master.readAsStringSync();
    for (final line in [
      r'# yaml-language-server: $schema=./schema.json',
      "# The workspace's settings. Keep this comment.",
      '  # Excludes for every walk.',
      '  exclude-projects: [zom_*]   # trailing comment',
      '  # Workspace defines.',
    ]) {
      expect(text, contains(line));
    }
  }

  test(
    'BB-MYE-1: :define and :undefine keep the comments [2026-11-16]',
    () async {
      await run([':define', 'A=one']);
      await run([':define', '-m', 'DEV', 'A=dev']);
      expectCommentsKept();
      expect(master.readAsStringSync(), contains("B: two  # B's comment"));
      final doc = loadYaml(master.readAsStringSync()) as YamlMap;
      expect(doc['edittool']['defines'], {'A': 'one', 'B': 'two'});
      expect(doc['edittool']['DEV-defines'], {'A': 'dev'});

      await run([':undefine', 'A']);
      await run([':undefine', '-m', 'DEV', 'A']);
      expectCommentsKept();
      final after = loadYaml(master.readAsStringSync()) as YamlMap;
      expect(after['edittool']['defines'], {'B': 'two'});
      expect(
        (after['edittool'] as YamlMap).containsKey('DEV-defines'),
        isFalse,
      );
    },
  );

  test(
    'BB-MYE-2: :macro and :unmacro keep the comments [2026-11-16]',
    () async {
      await run([':macro', 'b=:simple -v']);
      expectCommentsKept();
      final doc = loadYaml(master.readAsStringSync()) as YamlMap;
      expect(doc['macros'], {'b': ':simple -v'});
      await run([':unmacro', 'b']);
      expectCommentsKept();
      final after = loadYaml(master.readAsStringSync()) as YamlMap;
      expect(after.containsKey('macros'), isFalse);
    },
  );

  test('BB-MYE-3: adding and removing a define leaves the file as it was '
      '[2026-11-16]', () async {
    await run([':define', 'A=one']);
    await run([':undefine', 'A']);
    expect(master.readAsStringSync(), _original);
  });
}
