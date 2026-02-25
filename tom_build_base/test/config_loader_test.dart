// ignore_for_file: avoid_print

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base.dart';

void main() {
  group('ConfigLoader', () {
    late Directory tempDir;
    late String workspaceRoot;
    late String projectPath;

    setUp(() {
      // Create temp directory structure
      tempDir = Directory.systemTemp.createTempSync('config_loader_test_');
      workspaceRoot = tempDir.path;
      projectPath = p.join(workspaceRoot, 'my_project');
      Directory(projectPath).createSync();
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('loads master and project config files', () async {
      // Create master config
      File(p.join(workspaceRoot, 'buildkit_master.yaml')).writeAsStringSync('''
buildkit:
  defines:
    outputDir: /default/output
''');

      // Create project config
      File(p.join(projectPath, 'buildkit.yaml')).writeAsStringSync('''
compiler:
  outputs: [bin/main]
''');

      final loader = ConfigLoader(basename: 'buildkit');
      final config = await loader.load(
        workspaceRoot: workspaceRoot,
        projectPath: projectPath,
        activeModes: [],
      );

      expect(config.masterConfig, isNotEmpty);
      expect(config.projectConfig, isNotEmpty);
      expect(config.appliedModes, isEmpty);
    });

    test('processes mode-prefixed keys', () async {
      File(p.join(workspaceRoot, 'buildkit_master.yaml')).writeAsStringSync('''
compiler:
  target: release
  DEV-target: debug
  CI-threads: 4
''');

      final loader = ConfigLoader(basename: 'buildkit');

      // Test with no modes
      var config = await loader.load(
        workspaceRoot: workspaceRoot,
        projectPath: projectPath,
        activeModes: [],
      );
      expect(config.masterConfig['compiler']['target'], 'release');
      expect(config.masterConfig['compiler'].containsKey('DEV-target'), false);

      // Test with DEV mode
      config = await loader.load(
        workspaceRoot: workspaceRoot,
        projectPath: projectPath,
        activeModes: ['DEV'],
      );
      expect(config.masterConfig['compiler']['target'], 'debug');
      expect(config.appliedModes, ['DEV']);
    });

    test('resolves define placeholders', () async {
      File(p.join(workspaceRoot, 'buildkit_master.yaml')).writeAsStringSync('''
buildkit:
  defines:
    binPath: /opt/bin
    outputDir: "@[binPath]/output"
compiler:
  output: "@[outputDir]/main"
''');

      final loader = ConfigLoader(basename: 'buildkit');
      final config = await loader.load(
        workspaceRoot: workspaceRoot,
        projectPath: projectPath,
        activeModes: [],
      );

      expect(config.masterConfig['compiler']['output'], '/opt/bin/output/main');
    });

    test('resolves tool placeholders', () async {
      File(p.join(workspaceRoot, 'buildkit_master.yaml')).writeAsStringSync('''
compiler:
  projectDir: "@{project-path}"
  wsRoot: "@{workspace-root}"
''');

      final loader = ConfigLoader(basename: 'buildkit');
      final config = await loader.load(
        workspaceRoot: workspaceRoot,
        projectPath: projectPath,
        activeModes: [],
      );

      expect(config.masterConfig['compiler']['projectDir'], projectPath);
      expect(config.masterConfig['compiler']['wsRoot'], workspaceRoot);
    });

    test('shouldSkipDirectory checks tom_skip.yaml', () {
      final skipDir = p.join(workspaceRoot, 'skip_me');
      Directory(skipDir).createSync();

      final loader = ConfigLoader(basename: 'testkit');

      // No skip file
      expect(loader.shouldSkipDirectory(skipDir), false);

      // Add tom_skip.yaml (global)
      File(p.join(skipDir, 'tom_skip.yaml')).writeAsStringSync('');
      expect(loader.shouldSkipDirectory(skipDir), true);
    });

    test('shouldSkipDirectory checks tool-specific skip', () {
      final skipDir = p.join(workspaceRoot, 'skip_me');
      Directory(skipDir).createSync();

      final loader = ConfigLoader(basename: 'testkit');

      // No skip file
      expect(loader.shouldSkipDirectory(skipDir), false);

      // Add testkit_skip.yaml
      File(p.join(skipDir, 'testkit_skip.yaml')).writeAsStringSync('');
      expect(loader.shouldSkipDirectory(skipDir), true);

      // But buildkit shouldn't be skipped
      final buildkitLoader = ConfigLoader(basename: 'buildkit');
      expect(buildkitLoader.shouldSkipDirectory(skipDir), false);
    });
  });

  group('resolvePlaceholders', () {
    test('resolves @[...] placeholders', () {
      final values = {'name': 'world'};
      expect(resolvePlaceholders('Hello @[name]!', values), 'Hello world!');
    });

    test('resolves @{...} placeholders', () {
      final values = {'project-path': '/path/to/project'};
      expect(
        resolvePlaceholders('Path: @{project-path}', values),
        'Path: /path/to/project',
      );
    });

    test('resolves recursively', () {
      final values = {'a': '@[b]', 'b': 'final'};
      expect(resolvePlaceholders('@[a]', values), 'final');
    });

    test('leaves unresolved placeholders', () {
      expect(resolvePlaceholders('Hello @[unknown]!', {}), 'Hello @[unknown]!');
    });

    test('resolves environment variables when enabled', () {
      expect(
        resolvePlaceholders(r'Home: $HOME', {}, resolveEnvVars: true),
        'Home: ${Platform.environment['HOME']}',
      );
    });
  });
}
