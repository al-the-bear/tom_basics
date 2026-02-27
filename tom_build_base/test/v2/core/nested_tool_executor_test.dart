import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('NestedToolExecutor', () {
    group('buildNestedArgs', () {
      test('BB-NTE-1: Minimal args for multi-command tool [2026-02-27]', () {
        final args = NestedToolExecutor.buildNestedArgs(
          hostArgs: const CliArgs(),
          hostCommandName: 'buildkittest',
          nestedCommand: 'test',
          isStandalone: false,
        );

        expect(args, equals(['--nested', ':test']));
      });

      test('BB-NTE-2: Minimal args for standalone tool [2026-02-27]', () {
        final args = NestedToolExecutor.buildNestedArgs(
          hostArgs: const CliArgs(),
          hostCommandName: 'astgen',
          nestedCommand: '',
          isStandalone: true,
        );

        expect(args, equals(['--nested']));
      });

      test('BB-NTE-3: Forwards verbose and dry-run [2026-02-27]', () {
        final args = NestedToolExecutor.buildNestedArgs(
          hostArgs: const CliArgs(verbose: true, dryRun: true),
          hostCommandName: 'buildkittest',
          nestedCommand: 'test',
          isStandalone: false,
        );

        expect(args, contains('--nested'));
        expect(args, contains('--verbose'));
        expect(args, contains('--dry-run'));
        expect(args, contains(':test'));
      });

      test('BB-NTE-4: Forwards command-specific flag options [2026-02-27]', () {
        final args = NestedToolExecutor.buildNestedArgs(
          hostArgs: CliArgs(
            commandArgs: {
              'buildkittest': PerCommandArgs(
                commandName: 'buildkittest',
                options: {'fail-fast': true},
              ),
            },
          ),
          hostCommandName: 'buildkittest',
          nestedCommand: 'test',
          isStandalone: false,
        );

        expect(args, contains('--nested'));
        expect(args, contains(':test'));
        expect(args, contains('--fail-fast'));
      });

      test(
        'BB-NTE-5: Forwards command-specific string options [2026-02-27]',
        () {
          final args = NestedToolExecutor.buildNestedArgs(
            hostArgs: CliArgs(
              commandArgs: {
                'buildkittest': PerCommandArgs(
                  commandName: 'buildkittest',
                  options: {'test-args': '--name parser'},
                ),
              },
            ),
            hostCommandName: 'buildkittest',
            nestedCommand: 'test',
            isStandalone: false,
          );

          expect(args, contains('--test-args'));
          expect(args, contains('--name parser'));
        },
      );

      test('BB-NTE-6: Forwards command-specific list options [2026-02-27]', () {
        final args = NestedToolExecutor.buildNestedArgs(
          hostArgs: CliArgs(
            commandArgs: {
              'buildkittest': PerCommandArgs(
                commandName: 'buildkittest',
                options: {
                  'tags': ['unit', 'fast'],
                },
              ),
            },
          ),
          hostCommandName: 'buildkittest',
          nestedCommand: 'test',
          isStandalone: false,
        );

        expect(args, contains('--tags'));
        // Each list item gets its own --tags
        final tagsIndices = <int>[];
        for (var i = 0; i < args.length; i++) {
          if (args[i] == '--tags') tagsIndices.add(i);
        }
        expect(tagsIndices, hasLength(2));
        expect(args[tagsIndices[0] + 1], equals('unit'));
        expect(args[tagsIndices[1] + 1], equals('fast'));
      });

      test('BB-NTE-7: Does not forward traversal options [2026-02-27]', () {
        final args = NestedToolExecutor.buildNestedArgs(
          hostArgs: const CliArgs(
            scan: '.',
            recursive: true,
            root: '/workspace',
            innerFirstGit: true,
          ),
          hostCommandName: 'buildkittest',
          nestedCommand: 'test',
          isStandalone: false,
        );

        // Should only have --nested and :test
        expect(args, equals(['--nested', ':test']));
        expect(args, isNot(contains('-s')));
        expect(args, isNot(contains('--scan')));
        expect(args, isNot(contains('-r')));
        expect(args, isNot(contains('-R')));
        expect(args, isNot(contains('-i')));
      });

      test('BB-NTE-8: Does not forward host-specific options [2026-02-27]', () {
        final args = NestedToolExecutor.buildNestedArgs(
          hostArgs: const CliArgs(listOnly: true, workspaceRecursion: true),
          hostCommandName: 'buildkittest',
          nestedCommand: 'test',
          isStandalone: false,
        );

        expect(args, equals(['--nested', ':test']));
        expect(args, isNot(contains('--list')));
        expect(args, isNot(contains('--workspace-recursion')));
      });

      test('BB-NTE-9: Skips false flag options [2026-02-27]', () {
        final args = NestedToolExecutor.buildNestedArgs(
          hostArgs: CliArgs(
            commandArgs: {
              'cmd': PerCommandArgs(
                commandName: 'cmd',
                options: {'enabled': true, 'disabled': false},
              ),
            },
          ),
          hostCommandName: 'cmd',
          nestedCommand: 'run',
          isStandalone: false,
        );

        expect(args, contains('--enabled'));
        expect(args, isNot(contains('--disabled')));
      });

      test('BB-NTE-10: Full invocation chain example [2026-02-27]', () {
        // Simulates: buildkit -r -v :buildkittest --test-args="--name parser"
        final args = NestedToolExecutor.buildNestedArgs(
          hostArgs: CliArgs(
            verbose: true,
            recursive: true,
            commandArgs: {
              'buildkittest': PerCommandArgs(
                commandName: 'buildkittest',
                options: {'test-args': '--name parser'},
              ),
            },
          ),
          hostCommandName: 'buildkittest',
          nestedCommand: 'test',
          isStandalone: false,
        );

        // Expected: testkit --nested --verbose :test --test-args "--name parser"
        expect(args[0], equals('--nested'));
        expect(args[1], equals('--verbose'));
        expect(args[2], equals(':test'));
        expect(args[3], equals('--test-args'));
        expect(args[4], equals('--name parser'));
      });
    });

    group('constructor and properties', () {
      test('BB-NTE-11: Multi-command executor properties [2026-02-27]', () {
        final executor = NestedToolExecutor(
          binary: 'testkit',
          hostCommandName: 'buildkittest',
          nestedCommand: 'test',
        );

        expect(executor.binary, equals('testkit'));
        expect(executor.hostCommandName, equals('buildkittest'));
        expect(executor.nestedCommand, equals('test'));
        expect(executor.isStandalone, isFalse);
      });

      test('BB-NTE-12: Standalone executor properties [2026-02-27]', () {
        final executor = NestedToolExecutor(
          binary: 'astgen',
          hostCommandName: 'astgen',
          isStandalone: true,
        );

        expect(executor.binary, equals('astgen'));
        expect(executor.isStandalone, isTrue);
        expect(executor.nestedCommand, isNull);
      });

      test('BB-NTE-13: toString for multi-command [2026-02-27]', () {
        final executor = NestedToolExecutor(
          binary: 'testkit',
          hostCommandName: 'buildkittest',
          nestedCommand: 'test',
        );

        final str = executor.toString();
        expect(str, contains('testkit'));
        expect(str, contains(':test'));
        expect(str, contains('buildkittest'));
      });

      test('BB-NTE-14: toString for standalone [2026-02-27]', () {
        final executor = NestedToolExecutor(
          binary: 'astgen',
          hostCommandName: 'astgen',
          isStandalone: true,
        );

        final str = executor.toString();
        expect(str, contains('astgen'));
        expect(str, contains('standalone'));
      });
    });
  });
}
