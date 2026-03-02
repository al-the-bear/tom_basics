/// Comprehensive tests for modes, defines, macros, placeholders, and pipelines.
///
/// These tests exercise the core build_base functionality using the existing
/// patterns from tool_runner_test.dart. Each test manages its own temp directory
/// and cwd changes using try-finally blocks.
///
/// Test IDs:
/// - BB-MOD-01 through BB-MOD-10: modes functionality
/// - BB-DEF-01 through BB-DEF-10: define/undefine commands
/// - BB-MCR-01 through BB-MCR-10: macro/unmacro commands
/// - BB-PLH-01 through BB-PLH-10: placeholder resolution
/// - BB-PIP-01 through BB-PIP-10: pipeline execution
@TestOn('!browser')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// Simple multi-command tool for testing.
const _multiTool = ToolDefinition(
  name: 'testtool',
  description: 'Test tool',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.projectTool,
  commands: [
    CommandDefinition(
      name: 'execute',
      description: 'Execute shell command',
      requiresTraversal: true,
      supportsProjectTraversal: true,
      worksWithNatures: {DartProjectFolder},
    ),
    CommandDefinition(
      name: 'build',
      description: 'Build command',
      requiresTraversal: true,
      supportsProjectTraversal: true,
      worksWithNatures: {DartProjectFolder},
    ),
  ],
);

/// Helper to create a minimal workspace with one Dart project.
Future<({Directory tempRoot, Directory workspace, Directory project})>
createMinimalWorkspace() async {
  final tempRoot = await Directory.systemTemp.createTemp('bb_feature_');
  final workspace = Directory(p.join(tempRoot.path, 'ws'))..createSync();
  final project = Directory(p.join(workspace.path, 'my_project'))..createSync();
  Directory(p.join(project.path, 'lib')).createSync();
  File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: my_project
version: 1.0.0
environment:
  sdk: ^3.0.0
''');
  // Create master yaml
  File(p.join(workspace.path, 'testtool_master.yaml')).writeAsStringSync('''
testtool:
  defines:
    mode: PROD
''');
  // Create .git to mark workspace root
  Directory(p.join(workspace.path, '.git')).createSync();
  return (tempRoot: tempRoot, workspace: workspace, project: project);
}

void main() {
  // ============ Modes Tests ============
  group('Modes CLI Parsing', () {
    test('BB-MOD-01: --modes flag parses single value [2026-06-15]', () {
      final parser = CliArgParser(toolDefinition: _multiTool);
      final result = parser.parse(['--modes', 'DEV', ':execute']);
      expect(result.modes, equals(['DEV']));
    });

    test(
      'BB-MOD-02: --modes flag parses comma-separated values [2026-06-15]',
      () {
        final parser = CliArgParser(toolDefinition: _multiTool);
        final result = parser.parse(['--modes', 'DEV,CI,PROD', ':execute']);
        expect(result.modes, equals(['DEV', 'CI', 'PROD']));
      },
    );

    test('BB-MOD-03: --modes defaults to empty [2026-06-15]', () {
      final parser = CliArgParser(toolDefinition: _multiTool);
      final result = parser.parse([':execute']);
      expect(result.modes, isEmpty);
    });

    test('BB-MOD-04: multiple --modes flags concatenate [2026-06-15]', () {
      final parser = CliArgParser(toolDefinition: _multiTool);
      final result = parser.parse([
        '--modes',
        'DEV',
        '--modes',
        'CI',
        ':execute',
      ]);
      expect(result.modes, equals(['DEV', 'CI']));
    });
  });

  // ============ Define Commands Tests ============
  group(':define command', () {
    test('BB-DEF-01: :define adds new define [2026-06-15]', () async {
      final ws = await createMinimalWorkspace();
      final previousCwd = Directory.current.path;
      try {
        Directory.current = ws.workspace.path;

        final output = StringBuffer();
        final runner = ToolRunner(tool: _multiTool, output: output);
        final result = await runner.run([':define', 'newKey=newValue']);

        expect(result.success, isTrue);
        expect(output.toString(), contains('Added define'));

        final content = File(
          p.join(ws.workspace.path, 'testtool_master.yaml'),
        ).readAsStringSync();
        expect(content, contains('newKey: newValue'));
      } finally {
        Directory.current = previousCwd;
        if (ws.tempRoot.existsSync()) {
          await ws.tempRoot.delete(recursive: true);
        }
      }
    });

    test(
      'BB-DEF-02: :define with -m adds mode-specific define [2026-06-15]',
      () async {
        final ws = await createMinimalWorkspace();
        final previousCwd = Directory.current.path;
        try {
          Directory.current = ws.workspace.path;

          final output = StringBuffer();
          final runner = ToolRunner(tool: _multiTool, output: output);
          final result = await runner.run([
            ':define',
            '-m',
            'DEV',
            'debug=enabled',
          ]);

          expect(result.success, isTrue);
          expect(output.toString(), contains('DEV mode'));

          final content = File(
            p.join(ws.workspace.path, 'testtool_master.yaml'),
          ).readAsStringSync();
          expect(content, contains('DEV-defines:'));
        } finally {
          Directory.current = previousCwd;
          if (ws.tempRoot.existsSync()) {
            await ws.tempRoot.delete(recursive: true);
          }
        }
      },
    );

    test('BB-DEF-03: :defines lists all defines [2026-06-15]', () async {
      final ws = await createMinimalWorkspace();
      final previousCwd = Directory.current.path;
      try {
        Directory.current = ws.workspace.path;

        // Add some defines
        File(
          p.join(ws.workspace.path, 'testtool_master.yaml'),
        ).writeAsStringSync('''
testtool:
  defines:
    alpha: valueA
    beta: valueB
  DEV-defines:
    gamma: valueC
''');

        final output = StringBuffer();
        final runner = ToolRunner(tool: _multiTool, output: output);
        final result = await runner.run([':defines']);

        expect(result.success, isTrue);
        final out = output.toString();
        expect(out, contains('alpha'));
        expect(out, contains('beta'));
        expect(out, contains('DEV'));
      } finally {
        Directory.current = previousCwd;
        if (ws.tempRoot.existsSync()) {
          await ws.tempRoot.delete(recursive: true);
        }
      }
    });

    test('BB-DEF-04: :undefine removes define [2026-06-15]', () async {
      final ws = await createMinimalWorkspace();
      final previousCwd = Directory.current.path;
      try {
        Directory.current = ws.workspace.path;

        // Set up initial defines
        File(
          p.join(ws.workspace.path, 'testtool_master.yaml'),
        ).writeAsStringSync('''
testtool:
  defines:
    toRemove: value
    toKeep: value
''');

        final output = StringBuffer();
        final runner = ToolRunner(tool: _multiTool, output: output);
        final result = await runner.run([':undefine', 'toRemove']);

        expect(result.success, isTrue);

        final content = File(
          p.join(ws.workspace.path, 'testtool_master.yaml'),
        ).readAsStringSync();
        expect(content, isNot(contains('toRemove')));
        expect(content, contains('toKeep'));
      } finally {
        Directory.current = previousCwd;
        if (ws.tempRoot.existsSync()) {
          await ws.tempRoot.delete(recursive: true);
        }
      }
    });
  });

  // ============ Macro Commands Tests ============
  group(':macro command', () {
    test('BB-MCR-01: :macro adds new macro [2026-06-15]', () async {
      final ws = await createMinimalWorkspace();
      final previousCwd = Directory.current.path;
      try {
        Directory.current = ws.workspace.path;

        final output = StringBuffer();
        final runner = ToolRunner(tool: _multiTool, output: output);
        final result = await runner.run([
          ':macro',
          'build=:execute echo build',
        ]);

        expect(result.success, isTrue);
        expect(output.toString(), contains('Added macro'));

        final content = File(
          p.join(ws.workspace.path, 'testtool_master.yaml'),
        ).readAsStringSync();
        expect(content, contains('macros:'));
        expect(content, contains('build:'));
      } finally {
        Directory.current = previousCwd;
        if (ws.tempRoot.existsSync()) {
          await ws.tempRoot.delete(recursive: true);
        }
      }
    });

    test('BB-MCR-02: :macros lists all macros [2026-06-15]', () async {
      final ws = await createMinimalWorkspace();
      final previousCwd = Directory.current.path;
      try {
        Directory.current = ws.workspace.path;

        // Set up macros
        File(
          p.join(ws.workspace.path, 'testtool_master.yaml'),
        ).writeAsStringSync('''
testtool:
  defines:
    mode: PROD
macros:
  build: ":compile --release"
  test: ":test-runner"
''');

        final output = StringBuffer();
        final runner = ToolRunner(tool: _multiTool, output: output);
        final result = await runner.run([':macros']);

        expect(result.success, isTrue);
        final out = output.toString();
        expect(out, contains('build'));
        expect(out, contains('test'));
      } finally {
        Directory.current = previousCwd;
        if (ws.tempRoot.existsSync()) {
          await ws.tempRoot.delete(recursive: true);
        }
      }
    });

    test('BB-MCR-03: :unmacro removes macro [2026-06-15]', () async {
      final ws = await createMinimalWorkspace();
      final previousCwd = Directory.current.path;
      try {
        Directory.current = ws.workspace.path;

        // Set up macros
        File(
          p.join(ws.workspace.path, 'testtool_master.yaml'),
        ).writeAsStringSync('''
testtool:
  defines:
    mode: PROD
macros:
  toRemove: ":cmd1"
  toKeep: ":cmd2"
''');

        final output = StringBuffer();
        final runner = ToolRunner(tool: _multiTool, output: output);
        final result = await runner.run([':unmacro', 'toRemove']);

        expect(result.success, isTrue);

        final content = File(
          p.join(ws.workspace.path, 'testtool_master.yaml'),
        ).readAsStringSync();
        expect(content, isNot(contains('toRemove')));
        expect(content, contains('toKeep'));
      } finally {
        Directory.current = previousCwd;
        if (ws.tempRoot.existsSync()) {
          await ws.tempRoot.delete(recursive: true);
        }
      }
    });

    test('BB-MCR-04: macro expansion with placeholders [2026-06-15]', () {
      // Test macro expansion at argument parsing level
      final macros = {r'bp': r':build --project $1'};
      final args = ['@bp', 'tom_core'];
      final result = expandMacros(args, macros);
      expect(result, equals([':build', '--project', 'tom_core']));
    });

    test(r'BB-MCR-05: macro expansion with $$ rest args [2026-06-15]', () {
      final macros = {r'all': r':run $$'};
      final args = ['@all', '--verbose', '--dry-run', ':test'];
      final result = expandMacros(args, macros);
      expect(result, equals([':run', '--verbose', '--dry-run', ':test']));
    });
  });

  // ============ Placeholder Resolution Tests ============
  group('Execute Placeholders', () {
    test(
      'BB-PLH-01: folder placeholder resolves to absolute path [2026-06-15]',
      () {
        final folder = FsFolder(path: '/workspace/my-project');
        final ctx = ExecutePlaceholderContext(
          rootPath: '/workspace',
          folder: folder,
        );

        final result = ExecutePlaceholderResolver.resolveCommand(
          r'echo %{folder}',
          ctx,
        );
        expect(result, equals('echo /workspace/my-project'));
      },
    );

    test('BB-PLH-02: folder.name resolves to folder basename [2026-06-15]', () {
      final folder = FsFolder(path: '/workspace/my-project');
      final ctx = ExecutePlaceholderContext(
        rootPath: '/workspace',
        folder: folder,
      );

      final result = ExecutePlaceholderResolver.resolveCommand(
        r'echo %{folder.name}',
        ctx,
      );
      expect(result, equals('echo my-project'));
    });

    test(
      'BB-PLH-03: folder.relative resolves relative to root [2026-06-15]',
      () {
        final folder = FsFolder(path: '/workspace/packages/my-project');
        final ctx = ExecutePlaceholderContext(
          rootPath: '/workspace',
          folder: folder,
        );

        final result = ExecutePlaceholderResolver.resolveCommand(
          r'echo %{folder.relative}',
          ctx,
        );
        expect(result, equals('echo packages/my-project'));
      },
    );

    test(
      'BB-PLH-04: current-platform placeholder resolves to OS info [2026-06-15]',
      () {
        final folder = FsFolder(path: '/workspace');
        final ctx = ExecutePlaceholderContext(
          rootPath: '/workspace',
          folder: folder,
          currentOs: 'linux',
          currentArch: 'x64',
        );

        final result = ExecutePlaceholderResolver.resolveCommand(
          r'echo %{current-platform}',
          ctx,
        );
        expect(result, equals('echo linux-x64'));
      },
    );

    test(
      'BB-PLH-05: root placeholder resolves to workspace root [2026-06-15]',
      () {
        final folder = FsFolder(path: '/workspace/sub/project');
        final ctx = ExecutePlaceholderContext(
          rootPath: '/workspace',
          folder: folder,
        );

        final result = ExecutePlaceholderResolver.resolveCommand(
          r'cd %{root}',
          ctx,
        );
        expect(result, equals('cd /workspace'));
      },
    );

    test('BB-PLH-06: multiple placeholders in single command [2026-06-15]', () {
      final folder = FsFolder(path: '/workspace/my-project');
      final ctx = ExecutePlaceholderContext(
        rootPath: '/workspace',
        folder: folder,
        currentOs: 'linux',
        currentArch: 'x64',
      );

      final result = ExecutePlaceholderResolver.resolveCommand(
        r'cp %{folder.name}.tar.gz %{root}/dist/%{current-platform}/',
        ctx,
      );
      expect(result, equals('cp my-project.tar.gz /workspace/dist/linux-x64/'));
    });

    test('BB-PLH-07: ternary expression with true condition [2026-06-15]', () {
      // Create FsFolder with natures - needs dart.exists to be true
      // The FsFolder uses a mutable natures list
      final folderWithNatures = FsFolder(path: '/workspace/my-project');
      // Create a DartProjectFolder and add to natures
      final dartFolder = DartProjectFolder(
        folderWithNatures,
        projectName: 'my_project',
        version: '1.0.0',
      );
      folderWithNatures.natures.add(dartFolder);

      final ctx = ExecutePlaceholderContext(
        rootPath: '/workspace',
        folder: folderWithNatures,
      );

      final result = ExecutePlaceholderResolver.resolveCommand(
        r'echo %{dart.exists?(is-dart):(not-dart)}',
        ctx,
      );
      expect(result, equals('echo is-dart'));
    });

    test('BB-PLH-08: ternary expression with false condition [2026-06-15]', () {
      final folder = FsFolder(path: '/workspace/my-project');
      final ctx = ExecutePlaceholderContext(
        rootPath: '/workspace',
        folder: folder,
      );

      final result = ExecutePlaceholderResolver.resolveCommand(
        r'echo %{dart.exists?(is-dart):(not-dart)}',
        ctx,
      );
      expect(result, equals('echo not-dart'));
    });
  });

  // ============ Pipeline Tests ============
  group('Pipeline Configuration', () {
    test('BB-PIP-01: loads pipeline from master yaml [2026-06-15]', () async {
      final ws = await createMinimalWorkspace();
      final previousCwd = Directory.current.path;
      try {
        Directory.current = ws.workspace.path;

        File(
          p.join(ws.workspace.path, 'testtool_master.yaml'),
        ).writeAsStringSync('''
testtool:
  defines:
    mode: PROD
  pipelines:
    test:
      executable: true
      core:
        - commands:
            - "shell echo hello"
''');

        final config = ToolPipelineConfigLoader.load(
          tool: _multiTool,
          fromDirectory: ws.workspace.path,
        );

        expect(config, isNotNull);
        expect(config!.pipelines, contains('test'));
        expect(config.pipelines['test']!.executable, isTrue);
      } finally {
        Directory.current = previousCwd;
        if (ws.tempRoot.existsSync()) {
          await ws.tempRoot.delete(recursive: true);
        }
      }
    });

    test(
      'BB-PIP-02: pipeline definition has correct stages [2026-06-15]',
      () async {
        final ws = await createMinimalWorkspace();
        final previousCwd = Directory.current.path;
        try {
          Directory.current = ws.workspace.path;

          File(
            p.join(ws.workspace.path, 'testtool_master.yaml'),
          ).writeAsStringSync('''
testtool:
  defines:
    mode: PROD
  pipelines:
    build:
      executable: true
      precore:
        - commands:
            - "shell echo precore"
      core:
        - commands:
            - "shell echo core"
      postcore:
        - commands:
            - "shell echo postcore"
''');

          final config = ToolPipelineConfigLoader.load(
            tool: _multiTool,
            fromDirectory: ws.workspace.path,
          );

          expect(config, isNotNull);
          final pipeline = config!.pipelines['build']!;
          expect(pipeline.precore, hasLength(1));
          expect(pipeline.core, hasLength(1));
          expect(pipeline.postcore, hasLength(1));
        } finally {
          Directory.current = previousCwd;
          if (ws.tempRoot.existsSync()) {
            await ws.tempRoot.delete(recursive: true);
          }
        }
      },
    );

    test(
      'BB-PIP-03: PipelineCommandPrefixParser parses shell prefix [2026-06-15]',
      () {
        final result = PipelineCommandPrefixParser.parse(
          'shell echo hello',
          toolPrefix: 'testtool',
        );

        expect(result, isNotNull);
        expect(result!.prefix, equals(PipelineCommandPrefix.shell));
        expect(result.body, equals('echo hello'));
      },
    );

    test(
      'BB-PIP-04: PipelineCommandPrefixParser parses shell-scan prefix [2026-06-15]',
      () {
        final result = PipelineCommandPrefixParser.parse(
          'shell-scan echo project',
          toolPrefix: 'testtool',
        );

        expect(result, isNotNull);
        expect(result!.prefix, equals(PipelineCommandPrefix.shellScan));
        expect(result.body, equals('echo project'));
      },
    );

    test(
      'BB-PIP-05: PipelineCommandPrefixParser parses tool prefix [2026-06-15]',
      () {
        final result = PipelineCommandPrefixParser.parse(
          'testtool :build --release',
          toolPrefix: 'testtool',
        );

        expect(result, isNotNull);
        expect(result!.prefix, equals(PipelineCommandPrefix.tool));
        expect(result.body, equals(':build --release'));
      },
    );

    test(
      'BB-PIP-06: PipelineCommandPrefixParser parses stdin prefix [2026-06-15]',
      () {
        final result = PipelineCommandPrefixParser.parse(
          'stdin cat > output.txt',
          toolPrefix: 'testtool',
        );

        expect(result, isNotNull);
        expect(result!.prefix, equals(PipelineCommandPrefix.stdin));
        expect(result.body, equals('cat > output.txt'));
      },
    );

    test('BB-PIP-07: pipeline option resolver merges options [2026-06-15]', () {
      final pipelineOpts = {'verbose': 'true'};
      final invocationOpts = {'project': 'my_*'};
      final commandOpts = {'dry-run': 'true'};

      final merged = PipelineOptionResolver.resolveEffectiveOptions(
        pipelineOptions: pipelineOpts,
        invocationOptions: invocationOpts,
        commandOptions: commandOpts,
      );

      expect(merged, containsPair('verbose', 'true'));
      expect(merged, containsPair('project', 'my_*'));
      expect(merged, containsPair('dry-run', 'true'));
    });

    test(
      'BB-PIP-08: pipeline option resolver - command overrides invocation [2026-06-15]',
      () {
        final invocationOpts = {'project': 'old_*'};
        final commandOpts = {'project': 'new_*'};

        final merged = PipelineOptionResolver.resolveEffectiveOptions(
          pipelineOptions: {},
          invocationOptions: invocationOpts,
          commandOptions: commandOpts,
        );

        // Command options should override invocation options (later in spread)
        expect(merged['project'], equals('new_*'));
      },
    );

    test(
      'BB-PIP-09: hasDisqualifyingTraversalOptions detects root [2026-06-15]',
      () {
        const cliArgs = CliArgs(root: '/some/path');
        expect(
          PipelineOptionResolver.hasDisqualifyingTraversalOptions(cliArgs),
          isTrue,
        );
      },
    );

    test(
      'BB-PIP-10: hasDisqualifyingTraversalOptions detects project patterns [2026-06-15]',
      () {
        const cliArgs = CliArgs(projectPatterns: ['my_*']);
        expect(
          PipelineOptionResolver.hasDisqualifyingTraversalOptions(cliArgs),
          isTrue,
        );
      },
    );

    test(
      'BB-PIP-11: hasDisqualifyingTraversalOptions - empty args ok [2026-06-15]',
      () {
        const cliArgs = CliArgs();
        expect(
          PipelineOptionResolver.hasDisqualifyingTraversalOptions(cliArgs),
          isFalse,
        );
      },
    );
  });
}
