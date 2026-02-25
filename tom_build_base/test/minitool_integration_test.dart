// ignore_for_file: avoid_print

/// Integration test for modes and placeholders using a simulated "mini-tool".
///
/// This test simulates a complete tool ("minitool") with multiple commands
/// to verify the full mode processing, placeholder resolution, and skip file
/// behavior as specified in modes_and_placeholders.md.
///
/// The mini-tool has:
/// - :build command - primary command
/// - :test command - secondary command
/// - :deploy command - also available as standalone "deployer" executable

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base.dart';

/// Simulates a tool with multiple commands.
class MiniTool {
  final String basename;
  final String workspaceRoot;
  final List<String> activeModes;
  final bool verbose;

  late final ConfigLoader _loader;

  MiniTool({
    required this.basename,
    required this.workspaceRoot,
    this.activeModes = const [],
    this.verbose = false,
  }) {
    _loader = ConfigLoader(
      basename: basename,
      verbose: verbose,
      toolPlaceholders: {
        'tool-version': PlaceholderDefinition(
          name: 'tool-version',
          description: 'Version of the tool',
          resolver: (_) => '1.0.0',
        ),
      },
    );
  }

  /// Load and process configuration for a project.
  Future<MiniToolConfig> loadConfig(String projectPath) async {
    final loaded = await _loader.load(
      workspaceRoot: workspaceRoot,
      projectPath: projectPath,
      activeModes: activeModes,
    );

    return MiniToolConfig(
      masterConfig: loaded.masterConfig,
      projectConfig: loaded.projectConfig,
      appliedModes: loaded.appliedModes,
      resolvedDefines: loaded.resolvedDefines,
    );
  }

  /// Check if a directory should be skipped.
  bool shouldSkip(String dirPath) => _loader.shouldSkipDirectory(dirPath);

  /// Get skip reason for a directory.
  String? getSkipReason(String dirPath) => _loader.getSkipReason(dirPath);
}

/// Configuration result for mini-tool.
class MiniToolConfig {
  final Map<String, dynamic> masterConfig;
  final Map<String, dynamic> projectConfig;
  final List<String> appliedModes;
  final Map<String, String> resolvedDefines;

  MiniToolConfig({
    required this.masterConfig,
    required this.projectConfig,
    required this.appliedModes,
    required this.resolvedDefines,
  });

  /// Get command-specific config from master.
  Map<String, dynamic>? getCommandConfig(String commandName) {
    return masterConfig[commandName] as Map<String, dynamic>?;
  }

  /// Get command-specific config from project.
  Map<String, dynamic>? getProjectCommandConfig(String commandName) {
    return projectConfig[commandName] as Map<String, dynamic>?;
  }
}

/// Simulates a standalone tool that is also available as a command.
/// This demonstrates that standalone tools inherit configuration from
/// the parent tool's config file.
class DeployerStandalone {
  final String basename;
  final String commandName;
  final String workspaceRoot;
  final List<String> activeModes;

  DeployerStandalone({
    required this.basename,
    required this.commandName,
    required this.workspaceRoot,
    this.activeModes = const [],
  });

  /// Load configuration - standalone tool still uses the parent tool's config.
  Future<Map<String, dynamic>?> loadConfig(String projectPath) async {
    final loader = ConfigLoader(basename: basename);
    final loaded = await loader.load(
      workspaceRoot: workspaceRoot,
      projectPath: projectPath,
      activeModes: activeModes,
    );

    // Extract command-specific config
    return loaded.masterConfig[commandName] as Map<String, dynamic>? ??
        loaded.projectConfig[commandName] as Map<String, dynamic>?;
  }
}

void main() {
  group('Mini-Tool Integration Tests', () {
    late Directory tempDir;
    late String workspaceRoot;
    late String projectPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('minitool_test_');
      workspaceRoot = tempDir.path;
      projectPath = p.join(workspaceRoot, 'my_project');
      Directory(projectPath).createSync();
      // Create pubspec.yaml to make it a valid project
      File(
        p.join(projectPath, 'pubspec.yaml'),
      ).writeAsStringSync('name: my_project');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    group('Mode Processing', () {
      test('spec: base config used when no modes active', () async {
        File(p.join(workspaceRoot, 'minitool_master.yaml')).writeAsStringSync(
          '''
build:
  target: release
  optimize: true
  DEV-target: debug
  DEV-optimize: false
''',
        );

        final tool = MiniTool(
          basename: 'minitool',
          workspaceRoot: workspaceRoot,
          activeModes: [],
        );
        final config = await tool.loadConfig(projectPath);

        expect(config.getCommandConfig('build')?['target'], 'release');
        expect(config.getCommandConfig('build')?['optimize'], true);
        // Mode-prefixed keys should be removed
        expect(
          config.getCommandConfig('build')?.containsKey('DEV-target'),
          false,
        );
      });

      test('spec: DEV mode overrides base config', () async {
        File(p.join(workspaceRoot, 'minitool_master.yaml')).writeAsStringSync(
          '''
build:
  target: release
  optimize: true
  DEV-target: debug
  DEV-optimize: false
''',
        );

        final tool = MiniTool(
          basename: 'minitool',
          workspaceRoot: workspaceRoot,
          activeModes: ['DEV'],
        );
        final config = await tool.loadConfig(projectPath);

        expect(config.getCommandConfig('build')?['target'], 'debug');
        expect(config.getCommandConfig('build')?['optimize'], false);
        expect(config.appliedModes, ['DEV']);
      });

      test('spec: multiple modes merge in order', () async {
        File(p.join(workspaceRoot, 'minitool_master.yaml')).writeAsStringSync(
          '''
minitool:
  defines:
    outputPath: /prod/output
    cloudProvider: AWS
  DEV-defines:
    outputPath: /dev/output
  CLOUD-defines:
    cloudProvider: GCP
''',
        );

        final tool = MiniTool(
          basename: 'minitool',
          workspaceRoot: workspaceRoot,
          activeModes: ['DEV', 'CLOUD'],
        );
        final config = await tool.loadConfig(projectPath);

        // DEV overrides outputPath, CLOUD overrides cloudProvider
        expect(config.resolvedDefines['outputPath'], '/dev/output');
        expect(config.resolvedDefines['cloudProvider'], 'GCP');
      });

      test('spec: CI mode as feature flag', () async {
        File(p.join(workspaceRoot, 'minitool_master.yaml')).writeAsStringSync(
          '''
test:
  verbose: true
  CI-verbose: false
  CI-parallel: true
''',
        );

        // Without CI mode
        var tool = MiniTool(
          basename: 'minitool',
          workspaceRoot: workspaceRoot,
          activeModes: [],
        );
        var config = await tool.loadConfig(projectPath);
        expect(config.getCommandConfig('test')?['verbose'], true);
        expect(config.getCommandConfig('test')?['parallel'], null);

        // With CI mode
        tool = MiniTool(
          basename: 'minitool',
          workspaceRoot: workspaceRoot,
          activeModes: ['CI'],
        );
        config = await tool.loadConfig(projectPath);
        expect(config.getCommandConfig('test')?['verbose'], false);
        expect(config.getCommandConfig('test')?['parallel'], true);
      });
    });

    group('Placeholder Resolution', () {
      test('spec: @[...] define placeholders resolved at load time', () async {
        File(p.join(workspaceRoot, 'minitool_master.yaml')).writeAsStringSync(
          '''
minitool:
  defines:
    binPath: /opt/minitool/bin
    outputDir: "@[binPath]/output"
build:
  output: "@[outputDir]/main"
  script: "mkdir -p @[binPath]"
''',
        );

        final tool = MiniTool(
          basename: 'minitool',
          workspaceRoot: workspaceRoot,
          activeModes: [],
        );
        final config = await tool.loadConfig(projectPath);

        expect(
          config.getCommandConfig('build')?['output'],
          '/opt/minitool/bin/output/main',
        );
        expect(
          config.getCommandConfig('build')?['script'],
          'mkdir -p /opt/minitool/bin',
        );
      });

      test(
        'spec: @{...} tool placeholders resolved after mode processing',
        () async {
          File(p.join(workspaceRoot, 'minitool_master.yaml')).writeAsStringSync(
            '''
build:
  workDir: "@{project-path}/build"
  rootDir: "@{workspace-root}"
  projectName: "@{project-name}"
  version: "@{tool-version}"
''',
          );

          final tool = MiniTool(
            basename: 'minitool',
            workspaceRoot: workspaceRoot,
            activeModes: [],
          );
          final config = await tool.loadConfig(projectPath);

          expect(
            config.getCommandConfig('build')?['workDir'],
            '$projectPath/build',
          );
          expect(config.getCommandConfig('build')?['rootDir'], workspaceRoot);
          expect(
            config.getCommandConfig('build')?['projectName'],
            'my_project',
          );
          expect(config.getCommandConfig('build')?['version'], '1.0.0');
        },
      );

      test('spec: recursive placeholder resolution (max depth 10)', () async {
        File(p.join(workspaceRoot, 'minitool_master.yaml')).writeAsStringSync(
          '''
minitool:
  defines:
    level1: "L1"
    level2: "@[level1]/L2"
    level3: "@[level2]/L3"
    level4: "@[level3]/L4"
build:
  deepPath: "@[level4]/final"
''',
        );

        final tool = MiniTool(
          basename: 'minitool',
          workspaceRoot: workspaceRoot,
          activeModes: [],
        );
        final config = await tool.loadConfig(projectPath);

        expect(
          config.getCommandConfig('build')?['deepPath'],
          'L1/L2/L3/L4/final',
        );
      });

      test('spec: unresolved placeholders remain unchanged', () async {
        File(p.join(workspaceRoot, 'minitool_master.yaml')).writeAsStringSync(
          r'''
build:
  # ${file} is a command placeholder - not resolved at load time
  cmd: "compile ${file} to @{project-path}/out"
''',
        );

        final tool = MiniTool(
          basename: 'minitool',
          workspaceRoot: workspaceRoot,
          activeModes: [],
        );
        final config = await tool.loadConfig(projectPath);

        // @{project-path} resolved, ${file} left for command execution
        expect(
          config.getCommandConfig('build')?['cmd'],
          'compile \${file} to $projectPath/out',
        );
      });

      test(r'spec: env vars $VAR resolved when enabled', () {
        final result = resolvePlaceholders(
          r'Home: $HOME, User: $USER',
          {},
          resolveEnvVars: true,
        );

        expect(result, contains(Platform.environment['HOME'] ?? ''));
        expect(result, contains(Platform.environment['USER'] ?? ''));
      });

      test(r'spec: env vars $[VAR] syntax for adjacent text', () {
        final result = resolvePlaceholders(
          r'$[HOME]backup',
          {},
          resolveEnvVars: true,
        );

        final home = Platform.environment['HOME'] ?? '';
        expect(result, '${home}backup');
      });
    });

    group('Skip Files', () {
      test('spec: tom_skip.yaml skips directory for ALL tools', () {
        final skipDir = p.join(workspaceRoot, 'legacy_project');
        Directory(skipDir).createSync();
        File(
          p.join(skipDir, 'tom_skip.yaml'),
        ).writeAsStringSync('reason: Legacy project');

        // All tools should skip this directory
        final minitool = MiniTool(
          basename: 'minitool',
          workspaceRoot: workspaceRoot,
        );
        final buildkit = MiniTool(
          basename: 'buildkit',
          workspaceRoot: workspaceRoot,
        );
        final testkit = MiniTool(
          basename: 'testkit',
          workspaceRoot: workspaceRoot,
        );

        expect(minitool.shouldSkip(skipDir), true);
        expect(buildkit.shouldSkip(skipDir), true);
        expect(testkit.shouldSkip(skipDir), true);
      });

      test('spec: {basename}_skip.yaml skips for specific tool only', () {
        final skipDir = p.join(workspaceRoot, 'needs_special_handling');
        Directory(skipDir).createSync();
        File(p.join(skipDir, 'minitool_skip.yaml')).writeAsStringSync('');

        final minitool = MiniTool(
          basename: 'minitool',
          workspaceRoot: workspaceRoot,
        );
        final testkit = MiniTool(
          basename: 'testkit',
          workspaceRoot: workspaceRoot,
        );

        expect(minitool.shouldSkip(skipDir), true);
        expect(testkit.shouldSkip(skipDir), false);
      });

      test('spec: skip reason can be read from YAML', () {
        final skipDir = p.join(workspaceRoot, 'skip_with_reason');
        Directory(skipDir).createSync();
        File(p.join(skipDir, 'tom_skip.yaml')).writeAsStringSync('''
reason: "Not actively maintained"
''');

        final tool = MiniTool(
          basename: 'minitool',
          workspaceRoot: workspaceRoot,
        );
        final reason = tool.getSkipReason(skipDir);

        expect(reason, 'Not actively maintained');
      });

      test('spec: empty skip file is sufficient', () {
        final skipDir = p.join(workspaceRoot, 'empty_skip');
        Directory(skipDir).createSync();
        File(p.join(skipDir, 'tom_skip.yaml')).writeAsStringSync('');

        final tool = MiniTool(
          basename: 'minitool',
          workspaceRoot: workspaceRoot,
        );
        expect(tool.shouldSkip(skipDir), true);
      });
    });

    group('Standalone Tool Configuration Inheritance', () {
      test('spec: standalone tool inherits from parent tool config', () async {
        // The "deployer" standalone executable reads from minitool config
        File(p.join(workspaceRoot, 'minitool_master.yaml')).writeAsStringSync(
          '''
deploy:
  target: production
  region: us-east-1
  DEV-target: staging
  DEV-region: us-west-2
''',
        );

        // Standalone tool knows it's part of minitool
        final deployer = DeployerStandalone(
          basename: 'minitool',
          commandName: 'deploy',
          workspaceRoot: workspaceRoot,
          activeModes: [],
        );
        var deployConfig = await deployer.loadConfig(projectPath);

        expect(deployConfig?['target'], 'production');
        expect(deployConfig?['region'], 'us-east-1');

        // With DEV mode
        final devDeployer = DeployerStandalone(
          basename: 'minitool',
          commandName: 'deploy',
          workspaceRoot: workspaceRoot,
          activeModes: ['DEV'],
        );
        deployConfig = await devDeployer.loadConfig(projectPath);

        expect(deployConfig?['target'], 'staging');
        expect(deployConfig?['region'], 'us-west-2');
      });
    });

    group('Resolution Order (from spec)', () {
      test('spec: resolution follows 6-step flow', () async {
        // This test verifies the complete resolution flow:
        // 1. Determine active modes (CLI or tom_workspace.yaml)
        // 2. Load master YAML
        // 3. Load project YAML
        // 4. Apply mode processing
        // 5. Resolve @[...] defines
        // 6. Resolve @{...} tool placeholders

        File(p.join(workspaceRoot, 'minitool_master.yaml')).writeAsStringSync(
          '''
minitool:
  defines:
    env: prod
  DEV-defines:
    env: dev

build:
  envLabel: "@[env]"
  fullPath: "@{project-path}/@[env]/build"
  DEV-envLabel: "development"
''',
        );

        // Step 1: modes = ['DEV']
        final tool = MiniTool(
          basename: 'minitool',
          workspaceRoot: workspaceRoot,
          activeModes: ['DEV'],
        );

        // Steps 2-6 happen in loadConfig
        final config = await tool.loadConfig(projectPath);

        // Verify mode processing happened (step 4)
        expect(config.appliedModes, ['DEV']);

        // Verify defines resolved with mode override (steps 4+5)
        expect(config.resolvedDefines['env'], 'dev');

        // Verify all placeholders resolved (step 6)
        expect(config.getCommandConfig('build')?['envLabel'], 'development');
        expect(
          config.getCommandConfig('build')?['fullPath'],
          '$projectPath/dev/build',
        );
      });
    });
  });
}
