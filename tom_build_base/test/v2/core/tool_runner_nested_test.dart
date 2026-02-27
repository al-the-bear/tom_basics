import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// Test tool without wiring — used for nested mode and dump-definitions tests.
const _baseTool = ToolDefinition(
  name: 'hosttool',
  description: 'Host tool for nested tests',
  version: '3.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.projectTool,
  globalOptions: [
    OptionDefinition.flag(name: 'verbose', abbr: 'v', description: 'Verbose'),
  ],
  commands: [
    CommandDefinition(
      name: 'native',
      description: 'A native command',
      requiresTraversal: false,
    ),
    CommandDefinition(
      name: 'compile',
      description: 'Compile command',
      requiresTraversal: false,
    ),
  ],
);

/// Test tool with default command.
const _defaultCmdTool = ToolDefinition(
  name: 'hosttool',
  description: 'Host tool with default command',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  defaultCommand: 'compile',
  commands: [
    CommandDefinition(
      name: 'compile',
      description: 'Compile command',
      requiresTraversal: false,
    ),
  ],
);

/// Single-command tool for nested mode tests.
const _singleCommandTool = ToolDefinition(
  name: 'singletool',
  description: 'Single command tool',
  version: '1.0.0',
  mode: ToolMode.singleCommand,
);

/// Executor that tracks calls for verification.
class _TrackingExecutor extends CommandExecutor {
  final List<String> calls = [];
  bool shouldSucceed;

  // ignore: unused_element_parameter
  _TrackingExecutor({this.shouldSucceed = true});

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    calls.add('execute:${context.path}');
    if (shouldSucceed) {
      return ItemResult.success(path: context.path, name: context.name);
    }
    return ItemResult.failure(
      path: context.path,
      name: context.name,
      error: 'Test failure',
    );
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    calls.add('no-traversal');
    if (shouldSucceed) {
      return const ToolResult.success();
    }
    return const ToolResult.failure('Test failure');
  }
}

void main() {
  group('ToolRunner --dump-definitions', () {
    test('BB-RUN-25: --dump-definitions outputs YAML and returns success '
        '[2026-02-22]', () async {
      final output = StringBuffer();
      final runner = ToolRunner(tool: _baseTool, output: output);

      final result = await runner.run(['--dump-definitions']);

      expect(result.success, isTrue);
      final yaml = output.toString();
      expect(yaml, contains('name: hosttool'));
      expect(yaml, contains('version: 3.0.0'));
      expect(yaml, contains('description:'));
    });

    test(
      'BB-RUN-26: --dump-definitions serializes commands [2026-02-22]',
      () async {
        final output = StringBuffer();
        final runner = ToolRunner(tool: _baseTool, output: output);

        final result = await runner.run(['--dump-definitions']);

        expect(result.success, isTrue);
        final yaml = output.toString();
        expect(yaml, contains('native'));
        expect(yaml, contains('compile'));
      },
    );

    test('BB-RUN-27: --dump-definitions takes priority over --help '
        '[2026-02-22]', () async {
      final output = StringBuffer();
      final runner = ToolRunner(tool: _baseTool, output: output);

      final result = await runner.run(['--dump-definitions', '--help']);

      expect(result.success, isTrue);
      final yaml = output.toString();
      // Should be YAML output, not help text
      expect(yaml, contains('name: hosttool'));
    });

    test('BB-RUN-28: --dump-definitions takes priority over commands '
        '[2026-02-22]', () async {
      final output = StringBuffer();
      final runner = ToolRunner(tool: _baseTool, output: output);

      final result = await runner.run(['--dump-definitions', ':native']);

      expect(result.success, isTrue);
      final yaml = output.toString();
      expect(yaml, contains('name: hosttool'));
    });
  });

  group('ToolRunner --nested mode', () {
    test('BB-RUN-29: --nested routes command to executeWithoutTraversal '
        '[2026-02-22]', () async {
      final executor = _TrackingExecutor();
      final runner = ToolRunner(
        tool: _baseTool,
        executors: {'native': executor},
      );

      final result = await runner.run(['--nested', ':native']);

      expect(result.success, isTrue);
      expect(executor.calls, contains('no-traversal'));
    });

    test(
      'BB-RUN-30: --nested shows help when --help also set [2026-02-22]',
      () async {
        final output = StringBuffer();
        final runner = ToolRunner(tool: _baseTool, output: output);

        final result = await runner.run(['--nested', '--help']);

        expect(result.success, isTrue);
        expect(output.toString(), contains('hosttool'));
      },
    );

    test('BB-RUN-31: --nested shows command help for --help with command '
        '[2026-02-22]', () async {
      final output = StringBuffer();
      final runner = ToolRunner(tool: _baseTool, output: output);

      // --help before :native sets global help=true with commands=['native']
      final result = await runner.run(['--nested', '--help', ':native']);

      expect(result.success, isTrue);
      final text = output.toString();
      expect(text, contains(':native'));
      expect(text, contains('A native command'));
    });

    test(
      'BB-RUN-32: --nested shows version for --version [2026-02-22]',
      () async {
        final output = StringBuffer();
        final runner = ToolRunner(tool: _baseTool, output: output);

        final result = await runner.run(['--nested', '--version']);

        expect(result.success, isTrue);
        expect(output.toString(), contains('hosttool v3.0.0'));
      },
    );

    test(
      'BB-RUN-33: --nested fails for unknown command [2026-02-22]',
      () async {
        final runner = ToolRunner(tool: _baseTool, executors: {});

        final result = await runner.run(['--nested', ':nonexistent']);

        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Unknown command'));
      },
    );

    test(
      'BB-RUN-34: --nested fails when no command and no default [2026-02-22]',
      () async {
        final runner = ToolRunner(tool: _baseTool, executors: {});

        final result = await runner.run(['--nested']);

        expect(result.success, isFalse);
        expect(result.errorMessage, contains('No command specified'));
      },
    );

    test('BB-RUN-35: --nested uses default command when available '
        '[2026-02-22]', () async {
      final executor = _TrackingExecutor();
      final runner = ToolRunner(
        tool: _defaultCmdTool,
        executors: {'compile': executor},
      );

      final result = await runner.run(['--nested']);

      expect(result.success, isTrue);
      expect(executor.calls, contains('no-traversal'));
    });

    test('BB-RUN-36: --nested runs only first command in multi-command '
        '[2026-02-22]', () async {
      final nativeExec = _TrackingExecutor();
      final compileExec = _TrackingExecutor();
      final runner = ToolRunner(
        tool: _baseTool,
        executors: {'native': nativeExec, 'compile': compileExec},
      );

      final result = await runner.run(['--nested', ':native', ':compile']);

      expect(result.success, isTrue);
      expect(nativeExec.calls, contains('no-traversal'));
      // Second command should not be executed in nested mode
      expect(compileExec.calls, isEmpty);
    });

    test('BB-RUN-37: --nested single-command tool runs default executor '
        '[2026-02-22]', () async {
      final executor = _TrackingExecutor();
      final runner = ToolRunner(
        tool: _singleCommandTool,
        executors: {'default': executor},
      );

      final result = await runner.run(['--nested']);

      expect(result.success, isTrue);
      expect(executor.calls, contains('no-traversal'));
    });

    test('BB-RUN-38: --nested single-command tool fails without executor '
        '[2026-02-22]', () async {
      final runner = ToolRunner(tool: _singleCommandTool, executors: {});

      final result = await runner.run(['--nested']);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('No default executor'));
    });

    test('BB-RUN-39: --nested takes priority over wiring (no lazy wire) '
        '[2026-02-22]', () async {
      // Tool with hasWiring=true but --nested should skip wiring
      final toolWithWiring = _baseTool.copyWith(
        wiringFile: ToolDefinition.kAutoWiringFile,
      );
      final executor = _TrackingExecutor();
      final runner = ToolRunner(
        tool: toolWithWiring,
        executors: {'native': executor},
      );

      // --nested should run directly without attempting wiring
      final result = await runner.run(['--nested', ':native']);

      expect(result.success, isTrue);
      expect(executor.calls, contains('no-traversal'));
    });
  });

  group('ToolRunner _findExecutor', () {
    test('BB-RUN-40: Finds native executor [2026-02-22]', () async {
      final executor = _TrackingExecutor();
      final runner = ToolRunner(
        tool: _baseTool,
        executors: {'native': executor},
      );

      final result = await runner.run([':native']);

      expect(result.success, isTrue);
      expect(executor.calls, contains('no-traversal'));
    });

    test(
      'BB-RUN-41: Returns error when executor not found [2026-02-22]',
      () async {
        final runner = ToolRunner(tool: _baseTool, executors: {});

        final result = await runner.run([':native']);

        expect(result.success, isFalse);
      },
    );
  });

  group('ToolRunner help routing', () {
    test(
      'BB-RUN-42: --help shows tool help with command list [2026-02-22]',
      () async {
        final output = StringBuffer();
        final runner = ToolRunner(tool: _baseTool, output: output);

        final result = await runner.run(['--help']);

        expect(result.success, isTrue);
        final text = output.toString();
        expect(text, contains('hosttool'));
        expect(text, contains(':native'));
        expect(text, contains(':compile'));
      },
    );

    test(
      'BB-RUN-43: :command --help shows command help [2026-02-22]',
      () async {
        final output = StringBuffer();
        final runner = ToolRunner(tool: _baseTool, output: output);

        final result = await runner.run([':native', '--help']);

        expect(result.success, isTrue);
        final text = output.toString();
        expect(text, contains(':native'));
        expect(text, contains('A native command'));
      },
    );

    test(
      'BB-RUN-44: help for unknown command shows error [2026-02-22]',
      () async {
        final output = StringBuffer();
        final runner = ToolRunner(tool: _baseTool, output: output);

        final result = await runner.run(['--help', ':nonexistent']);

        expect(result.success, isFalse);
        expect(output.toString(), contains('Unknown command'));
      },
    );
  });
}
