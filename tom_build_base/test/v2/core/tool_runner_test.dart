import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// Test tool definition for use in tests.
const testTool = ToolDefinition(
  name: 'testtool',
  description: 'Test tool for testing',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.projectTool,
  globalOptions: [
    OptionDefinition.flag(name: 'verbose', abbr: 'v', description: 'Verbose'),
    OptionDefinition.flag(name: 'dry-run', description: 'Dry run'),
  ],
  commands: [
    CommandDefinition(
      name: 'simple',
      description: 'Simple command',
      requiresTraversal: false,
    ),
    CommandDefinition(
      name: 'traverse',
      description: 'Traverse command',
      requiresTraversal: true,
      supportsProjectTraversal: true,
    ),
    CommandDefinition(
      name: 'hidden',
      description: 'Hidden command',
      hidden: true,
    ),
    CommandDefinition(
      name: 'alias',
      description: 'Command with aliases',
      aliases: ['a', 'al'],
    ),
  ],
  helpFooter: 'Test footer',
);

/// Test executor that tracks calls.
class TrackingExecutor extends CommandExecutor {
  final List<String> calls = [];
  bool shouldSucceed;

  TrackingExecutor({this.shouldSucceed = true});

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    calls.add(context.path);
    if (shouldSucceed) {
      return ItemResult.success(path: context.path, name: context.name);
    } else {
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error: 'Test failure',
      );
    }
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    calls.add('no-traversal');
    return const ToolResult.success();
  }
}

void main() {
  group('ItemResult', () {
    group('constructor', () {
      test('BB-RUN-1: Creates result with required fields [2026-02-12]', () {
        const result = ItemResult(path: '/test', name: 'test');

        expect(result.path, equals('/test'));
        expect(result.name, equals('test'));
        expect(result.success, isTrue);
        expect(result.message, isNull);
        expect(result.error, isNull);
      });

      test('BB-RUN-2: Creates result with all fields [2026-02-12]', () {
        const result = ItemResult(
          path: '/test',
          name: 'test',
          success: false,
          message: 'info',
          error: 'failed',
        );

        expect(result.success, isFalse);
        expect(result.message, equals('info'));
        expect(result.error, equals('failed'));
      });
    });

    group('success factory', () {
      test('BB-RUN-3: Creates success result [2026-02-12]', () {
        const result = ItemResult.success(
          path: '/test',
          name: 'test',
          message: 'OK',
        );

        expect(result.success, isTrue);
        expect(result.error, isNull);
        expect(result.message, equals('OK'));
      });
    });

    group('failure factory', () {
      test('BB-RUN-4: Creates failure result [2026-02-12]', () {
        const result = ItemResult.failure(
          path: '/test',
          name: 'test',
          error: 'Something went wrong',
        );

        expect(result.success, isFalse);
        expect(result.error, equals('Something went wrong'));
        expect(result.message, isNull);
      });
    });
  });

  group('ToolResult', () {
    group('constructor', () {
      test('BB-RUN-5: Creates result with defaults [2026-02-12]', () {
        const result = ToolResult();

        expect(result.success, isTrue);
        expect(result.processedCount, equals(0));
        expect(result.failedCount, equals(0));
        expect(result.errorMessage, isNull);
        expect(result.itemResults, isEmpty);
      });

      test('BB-RUN-6: Creates result with all fields [2026-02-12]', () {
        const result = ToolResult(
          success: false,
          processedCount: 5,
          failedCount: 2,
          errorMessage: 'Some failed',
          itemResults: [],
        );

        expect(result.success, isFalse);
        expect(result.processedCount, equals(5));
        expect(result.failedCount, equals(2));
        expect(result.errorMessage, equals('Some failed'));
      });
    });

    group('success factory', () {
      test('BB-RUN-7: Creates success result [2026-02-12]', () {
        const result = ToolResult.success(processedCount: 3);

        expect(result.success, isTrue);
        expect(result.processedCount, equals(3));
        expect(result.failedCount, equals(0));
        expect(result.errorMessage, isNull);
      });

      test('BB-RUN-8: Creates success with item results [2026-02-12]', () {
        const items = [
          ItemResult.success(path: '/a', name: 'a'),
          ItemResult.success(path: '/b', name: 'b'),
        ];
        const result = ToolResult.success(itemResults: items);

        expect(result.itemResults, hasLength(2));
      });
    });

    group('failure factory', () {
      test('BB-RUN-9: Creates failure result [2026-02-12]', () {
        const result = ToolResult.failure('Something went wrong');

        expect(result.success, isFalse);
        expect(result.errorMessage, equals('Something went wrong'));
        expect(result.processedCount, equals(0));
        expect(result.failedCount, equals(0));
      });
    });

    group('fromItems factory', () {
      test('BB-RUN-10: Creates result from all successful items [2026-02-12]', () {
        final result = ToolResult.fromItems([
          const ItemResult.success(path: '/a', name: 'a'),
          const ItemResult.success(path: '/b', name: 'b'),
          const ItemResult.success(path: '/c', name: 'c'),
        ]);

        expect(result.success, isTrue);
        expect(result.processedCount, equals(3));
        expect(result.failedCount, equals(0));
      });

      test('BB-RUN-11: Creates result from mixed items [2026-02-12]', () {
        final result = ToolResult.fromItems([
          const ItemResult.success(path: '/a', name: 'a'),
          const ItemResult.failure(path: '/b', name: 'b', error: 'err'),
          const ItemResult.success(path: '/c', name: 'c'),
        ]);

        expect(result.success, isFalse);
        expect(result.processedCount, equals(3));
        expect(result.failedCount, equals(1));
      });

      test('BB-RUN-12: Creates result from all failed items [2026-02-12]', () {
        final result = ToolResult.fromItems([
          const ItemResult.failure(path: '/a', name: 'a', error: 'err'),
          const ItemResult.failure(path: '/b', name: 'b', error: 'err'),
        ]);

        expect(result.success, isFalse);
        expect(result.processedCount, equals(2));
        expect(result.failedCount, equals(2));
      });

      test('BB-RUN-13: Creates result from empty items [2026-02-12]', () {
        final result = ToolResult.fromItems([]);

        expect(result.success, isTrue);
        expect(result.processedCount, equals(0));
        expect(result.failedCount, equals(0));
      });
    });
  });

  group('ToolRunner', () {
    group('constructor', () {
      test('BB-RUN-14: Creates runner with required fields [2026-02-12]', () {
        final runner = ToolRunner(tool: testTool);

        expect(runner.tool, equals(testTool));
        expect(runner.executors, isEmpty);
        expect(runner.verbose, isTrue);
      });

      test('BB-RUN-15: Creates runner with executors [2026-02-12]', () {
        final executor = TrackingExecutor();
        final runner = ToolRunner(
          tool: testTool,
          executors: {'simple': executor},
        );

        expect(runner.executors['simple'], equals(executor));
      });
    });

    group('run', () {
      test('BB-RUN-16: Shows tool help for --help [2026-02-12]', () async {
        final output = StringBuffer();
        final runner = ToolRunner(
          tool: testTool,
          output: output,
        );

        final result = await runner.run(['--help']);

        expect(result.success, isTrue);
        expect(output.toString(), contains('testtool'));
        expect(output.toString(), contains('Test tool for testing'));
      });

      test('BB-RUN-17: Shows version for --version [2026-02-12]', () async {
        final output = StringBuffer();
        final runner = ToolRunner(
          tool: testTool,
          output: output,
        );

        final result = await runner.run(['--version']);

        expect(result.success, isTrue);
        expect(output.toString(), contains('1.0.0'));
      });

      test('BB-RUN-18: Shows command help for :command --help [2026-02-12]', () async {
        final output = StringBuffer();
        final runner = ToolRunner(
          tool: testTool,
          output: output,
        );

        final result = await runner.run([':simple', '--help']);

        expect(result.success, isTrue);
        expect(output.toString(), contains(':simple'));
        expect(output.toString(), contains('Simple command'));
      });

      test('BB-RUN-19: Finds command by alias [2026-02-12]', () async {
        final output = StringBuffer();
        final executor = TrackingExecutor();
        final runner = ToolRunner(
          tool: testTool,
          executors: {'alias': executor},
          output: output,
        );

        // Using alias 'a' should find command 'alias'
        final result = await runner.run([':a', '--help']);

        expect(result.success, isTrue);
        expect(output.toString(), contains(':alias'));
      });

      test('BB-RUN-20: Returns error for unknown command [2026-02-12]', () async {
        final output = StringBuffer();
        final runner = ToolRunner(
          tool: testTool,
          output: output,
        );

        final result = await runner.run([':unknown']);

        expect(result.success, isFalse);
        expect(output.toString(), contains('Unknown command'));
      });

      test('BB-RUN-21: Shows usage when no command specified [2026-02-12]', () async {
        final output = StringBuffer();
        final runner = ToolRunner(
          tool: testTool,
          output: output,
        );

        final result = await runner.run([]);

        expect(result.success, isFalse);
        expect(output.toString(), contains('No command specified'));
      });

      test('BB-RUN-22: Executes command without traversal [2026-02-12]', () async {
        final executor = TrackingExecutor();
        final runner = ToolRunner(
          tool: testTool,
          executors: {'simple': executor},
        );

        final result = await runner.run([':simple']);

        expect(result.success, isTrue);
        expect(executor.calls, contains('no-traversal'));
      });

      test('BB-RUN-23: Returns error when no executor for command [2026-02-12]', () async {
        final runner = ToolRunner(
          tool: testTool,
          executors: {},
        );

        final result = await runner.run([':traverse']);

        expect(result.success, isFalse);
      });
    });
  });

  group('CommandExecutor', () {
    test('BB-RUN-24: Base class has default executeWithoutTraversal [2026-02-12]', () async {
      final executor = _MinimalExecutor();

      final result = await executor.executeWithoutTraversal(const CliArgs());
      expect(result.success, isTrue);
    });
  });
}

/// Minimal executor for testing base class defaults.
class _MinimalExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    return ItemResult.success(path: context.path, name: context.name);
  }
}
