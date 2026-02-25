import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('ToolMode', () {
    test('BB-TDF-1: Has three values [2026-02-12]', () {
      expect(ToolMode.values, hasLength(3));
      expect(ToolMode.values, contains(ToolMode.multiCommand));
      expect(ToolMode.values, contains(ToolMode.singleCommand));
      expect(ToolMode.values, contains(ToolMode.hybrid));
    });
  });

  group('NavigationFeatures', () {
    group('constructor', () {
      test('BB-TDF-2: Creates features with defaults [2026-02-12]', () {
        const features = NavigationFeatures();

        expect(features.projectTraversal, isTrue);
        expect(features.gitTraversal, isFalse);
        expect(features.recursiveScan, isTrue);
        expect(features.interactiveMode, isFalse);
        expect(features.dryRun, isFalse);
        expect(features.jsonOutput, isFalse);
        expect(features.verbose, isTrue);
      });

      test('BB-TDF-3: Creates features with all fields [2026-02-12]', () {
        const features = NavigationFeatures(
          projectTraversal: false,
          gitTraversal: true,
          recursiveScan: false,
          interactiveMode: true,
          dryRun: true,
          jsonOutput: true,
          verbose: false,
        );

        expect(features.projectTraversal, isFalse);
        expect(features.gitTraversal, isTrue);
        expect(features.recursiveScan, isFalse);
        expect(features.interactiveMode, isTrue);
        expect(features.dryRun, isTrue);
        expect(features.jsonOutput, isTrue);
        expect(features.verbose, isFalse);
      });
    });

    group('predefined constants', () {
      test('BB-TDF-4: All has all features enabled [2026-02-12]', () {
        const features = NavigationFeatures.all;

        expect(features.projectTraversal, isTrue);
        expect(features.gitTraversal, isTrue);
        expect(features.recursiveScan, isTrue);
        expect(features.interactiveMode, isTrue);
        expect(features.dryRun, isTrue);
        expect(features.jsonOutput, isTrue);
        expect(features.verbose, isTrue);
      });

      test('BB-TDF-5: Minimal has only verbose enabled [2026-02-12]', () {
        const features = NavigationFeatures.minimal;

        expect(features.projectTraversal, isFalse);
        expect(features.gitTraversal, isFalse);
        expect(features.recursiveScan, isFalse);
        expect(features.interactiveMode, isFalse);
        expect(features.dryRun, isFalse);
        expect(features.jsonOutput, isFalse);
        expect(features.verbose, isTrue);
      });

      test('BB-TDF-6: ProjectTool has project traversal enabled [2026-02-12]', () {
        const features = NavigationFeatures.projectTool;

        expect(features.projectTraversal, isTrue);
        expect(features.gitTraversal, isFalse);
        expect(features.recursiveScan, isTrue);
        expect(features.verbose, isTrue);
      });

      test('BB-TDF-7: GitTool has git traversal enabled [2026-02-12]', () {
        const features = NavigationFeatures.gitTool;

        expect(features.projectTraversal, isFalse);
        expect(features.gitTraversal, isTrue);
        expect(features.recursiveScan, isTrue);
        expect(features.verbose, isTrue);
      });
    });

    group('toString', () {
      test('BB-TDF-8: Lists enabled features [2026-02-12]', () {
        const features = NavigationFeatures(
          projectTraversal: true,
          gitTraversal: false,
          verbose: true,
        );

        final str = features.toString();
        expect(str, contains('projectTraversal'));
        expect(str, contains('verbose'));
        expect(str, isNot(contains('gitTraversal,')));
      });

      test('BB-TDF-9: Handles no features enabled [2026-02-12]', () {
        const features = NavigationFeatures(
          projectTraversal: false,
          gitTraversal: false,
          recursiveScan: false,
          interactiveMode: false,
          dryRun: false,
          jsonOutput: false,
          verbose: false,
        );

        expect(features.toString(), equals('NavigationFeatures()'));
      });
    });
  });

  group('ToolDefinition', () {
    group('constructor', () {
      test('BB-TDF-10: Creates tool with required fields [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'mytool',
          description: 'My tool description',
        );

        expect(tool.name, equals('mytool'));
        expect(tool.description, equals('My tool description'));
        expect(tool.version, equals('1.0.0'));
        expect(tool.mode, equals(ToolMode.multiCommand));
        expect(tool.features, isA<NavigationFeatures>());
        expect(tool.globalOptions, isEmpty);
        expect(tool.commands, isEmpty);
        expect(tool.defaultCommand, isNull);
        expect(tool.helpFooter, isNull);
      });

      test('BB-TDF-11: Creates tool with all fields [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
          version: '2.0.0',
          mode: ToolMode.multiCommand,
          features: NavigationFeatures.all,
          globalOptions: [
            OptionDefinition.flag(name: 'tui', description: 'TUI mode'),
          ],
          commands: [
            CommandDefinition(name: 'cleanup', description: 'Clean'),
          ],
          defaultCommand: 'status',
          helpFooter: 'Footer text',
        );

        expect(tool.name, equals('buildkit'));
        expect(tool.version, equals('2.0.0'));
        expect(tool.mode, equals(ToolMode.multiCommand));
        expect(tool.features, equals(NavigationFeatures.all));
        expect(tool.globalOptions, hasLength(1));
        expect(tool.commands, hasLength(1));
        expect(tool.defaultCommand, equals('status'));
        expect(tool.helpFooter, equals('Footer text'));
      });
    });

    group('findCommand', () {
      test('BB-TDF-12: Finds command by name [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
          commands: [
            CommandDefinition(name: 'cleanup', description: 'Clean'),
            CommandDefinition(name: 'compile', description: 'Compile'),
          ],
        );

        final cmd = tool.findCommand('cleanup');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('cleanup'));
      });

      test('BB-TDF-13: Finds command by alias [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
          commands: [
            CommandDefinition(
              name: 'crossreference',
              description: 'Cross ref',
              aliases: ['crossref', 'xref'],
            ),
          ],
        );

        expect(tool.findCommand('crossreference')?.name, equals('crossreference'));
        expect(tool.findCommand('crossref')?.name, equals('crossreference'));
        expect(tool.findCommand('xref')?.name, equals('crossreference'));
      });

      test('BB-TDF-14: Returns null for unknown command [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
          commands: [
            CommandDefinition(name: 'cleanup', description: 'Clean'),
          ],
        );

        expect(tool.findCommand('unknown'), isNull);
      });
    });

    group('visibleCommands', () {
      test('BB-TDF-15: Returns non-hidden commands [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
          commands: [
            CommandDefinition(name: 'cleanup', description: 'Clean'),
            CommandDefinition(name: 'debug', description: 'Debug', hidden: true),
            CommandDefinition(name: 'compile', description: 'Compile'),
          ],
        );

        final visible = tool.visibleCommands;
        expect(visible, hasLength(2));
        expect(visible.map((c) => c.name), containsAll(['cleanup', 'compile']));
        expect(visible.map((c) => c.name), isNot(contains('debug')));
      });

      test('BB-TDF-16: Returns empty list when all hidden [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
          commands: [
            CommandDefinition(name: 'debug', description: 'Debug', hidden: true),
          ],
        );

        expect(tool.visibleCommands, isEmpty);
      });
    });

    group('allGlobalOptions', () {
      test('BB-TDF-17: Includes custom global options [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
          globalOptions: [
            OptionDefinition.flag(name: 'tui', description: 'TUI mode'),
          ],
        );

        final allOptions = tool.allGlobalOptions;
        expect(allOptions.any((o) => o.name == 'tui'), isTrue);
      });

      test('BB-TDF-18: Includes common options [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
        );

        final allOptions = tool.allGlobalOptions;
        // Common options should include exclude, test, etc.
        expect(allOptions.any((o) => o.name == 'exclude'), isTrue);
      });

      test('BB-TDF-19: Includes dry-run when feature enabled [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
          features: NavigationFeatures(dryRun: true),
        );

        final allOptions = tool.allGlobalOptions;
        expect(allOptions.any((o) => o.name == 'dry-run'), isTrue);
      });

      test('BB-TDF-20: Dry-run is always present via commonOptions [2026-02-12]', () {
        // Note: dry-run is part of commonOptions, so it's always included.
        // The NavigationFeatures.dryRun flag controls whether an additional
        // feature-specific dry-run is added (which would be redundant).
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
          features: NavigationFeatures(dryRun: false),
        );

        final allOptions = tool.allGlobalOptions;
        // dry-run comes from commonOptions regardless of dryRun feature flag
        expect(allOptions.any((o) => o.name == 'dry-run'), isTrue);
      });

      test('BB-TDF-21: Includes json when feature enabled [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
          features: NavigationFeatures(jsonOutput: true),
        );

        final allOptions = tool.allGlobalOptions;
        expect(allOptions.any((o) => o.name == 'json'), isTrue);
      });

      test('BB-TDF-22: Includes interactive when feature enabled [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
          features: NavigationFeatures(interactiveMode: true),
        );

        final allOptions = tool.allGlobalOptions;
        expect(allOptions.any((o) => o.name == 'interactive'), isTrue);
      });
    });

    group('toString', () {
      test('BB-TDF-23: Returns descriptive string [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
          version: '2.0.0',
        );

        expect(tool.toString(), equals('ToolDefinition(buildkit v2.0.0)'));
      });
    });
  });

  group('Complete tool definition', () {
    test('BB-TDF-24: Creates realistic tool definition [2026-02-12]', () {
      const tool = ToolDefinition(
        name: 'testkit',
        description: 'Test result tracking tool',
        version: '0.1.0',
        mode: ToolMode.multiCommand,
        features: NavigationFeatures.projectTool,
        globalOptions: [
          OptionDefinition.flag(name: 'tui', description: 'TUI mode'),
        ],
        commands: [
          CommandDefinition(
            name: 'baseline',
            description: 'Create baseline',
            options: [
              OptionDefinition.option(
                name: 'file',
                description: 'Output file',
              ),
            ],
          ),
          CommandDefinition(
            name: 'test',
            description: 'Run tests',
            options: [
              OptionDefinition.flag(
                name: 'failed',
                description: 'Only failed',
              ),
            ],
          ),
          CommandDefinition(
            name: 'status',
            description: 'Show status',
          ),
        ],
        helpFooter: 'See documentation for more info.',
      );

      expect(tool.name, equals('testkit'));
      expect(tool.commands, hasLength(3));
      expect(tool.findCommand('baseline'), isNotNull);
      expect(tool.findCommand('test'), isNotNull);
      expect(tool.findCommand('status'), isNotNull);

      // Check command options are properly inherited
      final testCmd = tool.findCommand('test')!;
      expect(testCmd.allOptions.any((o) => o.name == 'failed'), isTrue);
      expect(testCmd.allOptions.any((o) => o.name == 'scan'), isTrue);
    });
  });
}
