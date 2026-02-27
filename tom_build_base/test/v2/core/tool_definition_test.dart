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

      test(
        'BB-TDF-6: ProjectTool has project traversal enabled [2026-02-12]',
        () {
          const features = NavigationFeatures.projectTool;

          expect(features.projectTraversal, isTrue);
          expect(features.gitTraversal, isFalse);
          expect(features.recursiveScan, isTrue);
          expect(features.verbose, isTrue);
        },
      );

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
          commands: [CommandDefinition(name: 'cleanup', description: 'Clean')],
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

        expect(
          tool.findCommand('crossreference')?.name,
          equals('crossreference'),
        );
        expect(tool.findCommand('crossref')?.name, equals('crossreference'));
        expect(tool.findCommand('xref')?.name, equals('crossreference'));
      });

      test('BB-TDF-14: Returns null for unknown command [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
          commands: [CommandDefinition(name: 'cleanup', description: 'Clean')],
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
            CommandDefinition(
              name: 'debug',
              description: 'Debug',
              hidden: true,
            ),
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
            CommandDefinition(
              name: 'debug',
              description: 'Debug',
              hidden: true,
            ),
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

      test(
        'BB-TDF-20: Dry-run is always present via commonOptions [2026-02-12]',
        () {
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
        },
      );

      test('BB-TDF-21: Includes json when feature enabled [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
          features: NavigationFeatures(jsonOutput: true),
        );

        final allOptions = tool.allGlobalOptions;
        expect(allOptions.any((o) => o.name == 'json'), isTrue);
      });

      test(
        'BB-TDF-22: Includes interactive when feature enabled [2026-02-12]',
        () {
          const tool = ToolDefinition(
            name: 'buildkit',
            description: 'Build toolkit',
            features: NavigationFeatures(interactiveMode: true),
          );

          final allOptions = tool.allGlobalOptions;
          expect(allOptions.any((o) => o.name == 'interactive'), isTrue);
        },
      );
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
              OptionDefinition.option(name: 'file', description: 'Output file'),
            ],
          ),
          CommandDefinition(
            name: 'test',
            description: 'Run tests',
            options: [
              OptionDefinition.flag(name: 'failed', description: 'Only failed'),
            ],
          ),
          CommandDefinition(name: 'status', description: 'Show status'),
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

  group('ToolDefinition.copyWith', () {
    const baseTool = ToolDefinition(
      name: 'buildkit',
      description: 'Build toolkit',
      version: '2.0.0',
      mode: ToolMode.multiCommand,
      features: NavigationFeatures.all,
      globalOptions: [
        OptionDefinition.flag(name: 'list', description: 'List things'),
      ],
      commands: [
        CommandDefinition(name: 'cleanup', description: 'Clean'),
        CommandDefinition(name: 'compile', description: 'Compile'),
        CommandDefinition(name: 'runner', description: 'Run'),
      ],
      defaultCommand: 'cleanup',
      helpFooter: 'Original footer',
      worksWithNatures: {},
    );

    test('BB-TDF-25: Returns identical tool when no args [2026-02-27]', () {
      final copy = baseTool.copyWith();

      expect(copy.name, equals(baseTool.name));
      expect(copy.description, equals(baseTool.description));
      expect(copy.version, equals(baseTool.version));
      expect(copy.mode, equals(baseTool.mode));
      expect(copy.features, equals(baseTool.features));
      expect(copy.globalOptions, equals(baseTool.globalOptions));
      expect(copy.commands, equals(baseTool.commands));
      expect(copy.defaultCommand, equals(baseTool.defaultCommand));
      expect(copy.helpFooter, equals(baseTool.helpFooter));
      expect(copy.helpTopics, equals(baseTool.helpTopics));
      expect(copy.requiredNatures, equals(baseTool.requiredNatures));
      expect(copy.worksWithNatures, equals(baseTool.worksWithNatures));
    });

    test('BB-TDF-26: Overrides name and version [2026-02-27]', () {
      final derived = baseTool.copyWith(name: 'supertool', version: '1.0.0');

      expect(derived.name, equals('supertool'));
      expect(derived.version, equals('1.0.0'));
      // Other fields unchanged
      expect(derived.description, equals(baseTool.description));
      expect(derived.mode, equals(baseTool.mode));
      expect(derived.commands, equals(baseTool.commands));
    });

    test('BB-TDF-27: Overrides commands list [2026-02-27]', () {
      final newCommands = [
        const CommandDefinition(name: 'deploy', description: 'Deploy'),
      ];
      final derived = baseTool.copyWith(commands: newCommands);

      expect(derived.commands, hasLength(1));
      expect(derived.commands.first.name, equals('deploy'));
      // Original unchanged
      expect(baseTool.commands, hasLength(3));
    });

    test('BB-TDF-28: Overrides mode and features [2026-02-27]', () {
      final derived = baseTool.copyWith(
        mode: ToolMode.singleCommand,
        features: NavigationFeatures.minimal,
      );

      expect(derived.mode, equals(ToolMode.singleCommand));
      expect(derived.features.projectTraversal, isFalse);
      expect(derived.features.verbose, isTrue);
    });

    test('BB-TDF-29: Overrides natures [2026-02-27]', () {
      final derived = baseTool.copyWith(
        requiredNatures: {String},
        worksWithNatures: {int, double},
      );

      expect(derived.requiredNatures, equals({String}));
      expect(derived.worksWithNatures, equals({int, double}));
    });

    test('BB-TDF-30: Does not mutate the original [2026-02-27]', () {
      final derived = baseTool.copyWith(
        name: 'other',
        commands: const [CommandDefinition(name: 'x', description: 'X')],
      );

      expect(baseTool.name, equals('buildkit'));
      expect(baseTool.commands, hasLength(3));
      expect(derived.name, equals('other'));
      expect(derived.commands, hasLength(1));
    });
  });

  group('CommandListOps', () {
    const commands = [
      CommandDefinition(name: 'cleanup', description: 'Clean'),
      CommandDefinition(name: 'compile', description: 'Compile'),
      CommandDefinition(name: 'runner', description: 'Run'),
      CommandDefinition(name: 'versioner', description: 'Version'),
    ];

    group('without', () {
      test('BB-TDF-31: Removes named commands [2026-02-27]', () {
        final result = commands.without({'cleanup', 'runner'});

        expect(result, hasLength(2));
        expect(result.map((c) => c.name), equals(['compile', 'versioner']));
      });

      test('BB-TDF-32: Returns all when no names match [2026-02-27]', () {
        final result = commands.without({'nonexistent'});

        expect(result, hasLength(4));
      });

      test('BB-TDF-33: Returns empty when all removed [2026-02-27]', () {
        final result = commands.without({
          'cleanup',
          'compile',
          'runner',
          'versioner',
        });

        expect(result, isEmpty);
      });

      test('BB-TDF-34: Does not modify original list [2026-02-27]', () {
        commands.without({'cleanup'});

        expect(commands, hasLength(4));
      });
    });

    group('replacing', () {
      test('BB-TDF-35: Replaces command by name [2026-02-27]', () {
        const replacement = CommandDefinition(
          name: 'runner',
          description: 'Custom runner',
        );
        final result = commands.replacing('runner', replacement);

        expect(result, hasLength(4));
        expect(result[2].name, equals('runner'));
        expect(result[2].description, equals('Custom runner'));
      });

      test('BB-TDF-36: Keeps position of replaced command [2026-02-27]', () {
        const replacement = CommandDefinition(
          name: 'compile',
          description: 'New compile',
        );
        final result = commands.replacing('compile', replacement);

        expect(result[0].name, equals('cleanup'));
        expect(result[1].name, equals('compile'));
        expect(result[1].description, equals('New compile'));
        expect(result[2].name, equals('runner'));
      });

      test('BB-TDF-37: Returns unchanged when name not found [2026-02-27]', () {
        const replacement = CommandDefinition(
          name: 'deploy',
          description: 'Deploy',
        );
        final result = commands.replacing('nonexistent', replacement);

        expect(result, hasLength(4));
        expect(
          result.map((c) => c.name),
          equals(['cleanup', 'compile', 'runner', 'versioner']),
        );
      });
    });

    group('plus', () {
      test('BB-TDF-38: Appends new commands [2026-02-27]', () {
        final result = commands.plus(const [
          CommandDefinition(name: 'deploy', description: 'Deploy'),
          CommandDefinition(name: 'lint', description: 'Lint'),
        ]);

        expect(result, hasLength(6));
        expect(result.last.name, equals('lint'));
      });

      test('BB-TDF-39: Appends empty list unchanged [2026-02-27]', () {
        final result = commands.plus(const []);

        expect(result, hasLength(4));
      });
    });

    group('chained operations', () {
      test('BB-TDF-40: Chained without+replacing+plus [2026-02-27]', () {
        const customRunner = CommandDefinition(
          name: 'runner',
          description: 'Custom',
        );
        const extra = CommandDefinition(name: 'deploy', description: 'Deploy');

        final result = commands
            .without({'cleanup'})
            .replacing('runner', customRunner)
            .plus([extra]);

        expect(result, hasLength(4));
        expect(
          result.map((c) => c.name),
          equals(['compile', 'runner', 'versioner', 'deploy']),
        );
        expect(result[1].description, equals('Custom'));
      });

      test(
        'BB-TDF-41: Used with copyWith for tool derivation [2026-02-27]',
        () {
          const baseTool = ToolDefinition(
            name: 'buildkit',
            description: 'Build toolkit',
            version: '2.0.0',
            commands: commands,
          );

          final derived = baseTool.copyWith(
            name: 'supertool',
            version: '1.0.0',
            commands: baseTool.commands.without({'cleanup'}).plus(const [
              CommandDefinition(name: 'deploy', description: 'Deploy'),
            ]),
          );

          expect(derived.name, equals('supertool'));
          expect(derived.commands, hasLength(4));
          expect(derived.findCommand('cleanup'), isNull);
          expect(derived.findCommand('deploy'), isNotNull);
          expect(derived.findCommand('compile'), isNotNull);
        },
      );
    });
  });

  group('ToolWiringEntry', () {
    test(
      'BB-TDF-42: Standalone entry has binary as host command [2026-02-27]',
      () {
        const entry = ToolWiringEntry(
          binary: 'astgen',
          mode: WiringMode.standalone,
        );

        expect(entry.binary, equals('astgen'));
        expect(entry.mode, equals(WiringMode.standalone));
        expect(entry.hasCommands, isFalse);
        expect(entry.hostCommandNames, equals({'astgen'}));
      },
    );

    test(
      'BB-TDF-43: Multi-command entry with command mapping [2026-02-27]',
      () {
        const entry = ToolWiringEntry(
          binary: 'testkit',
          mode: WiringMode.multiCommand,
          commands: {'buildkittest': 'test', 'buildkitbaseline': 'baseline'},
        );

        expect(entry.binary, equals('testkit'));
        expect(entry.mode, equals(WiringMode.multiCommand));
        expect(entry.hasCommands, isTrue);
        expect(
          entry.hostCommandNames,
          equals({'buildkittest', 'buildkitbaseline'}),
        );
      },
    );

    test('BB-TDF-44: Multi-command entry with null commands [2026-02-27]', () {
      const entry = ToolWiringEntry(
        binary: 'testkit',
        mode: WiringMode.multiCommand,
      );

      expect(entry.hasCommands, isFalse);
      expect(entry.hostCommandNames, isEmpty);
    });

    test('BB-TDF-45: toString includes binary and mode [2026-02-27]', () {
      const entry = ToolWiringEntry(
        binary: 'astgen',
        mode: WiringMode.standalone,
      );

      final str = entry.toString();
      expect(str, contains('astgen'));
      expect(str, contains('standalone'));
    });

    test('BB-TDF-46: toString includes commands when present [2026-02-27]', () {
      const entry = ToolWiringEntry(
        binary: 'testkit',
        mode: WiringMode.multiCommand,
        commands: {'bt': 'test'},
      );

      final str = entry.toString();
      expect(str, contains('commands:'));
      expect(str, contains('bt'));
    });
  });

  group('ToolDefinition wiring fields', () {
    test('BB-TDF-47: Defaults to no wiring [2026-02-27]', () {
      const tool = ToolDefinition(name: 'simple', description: 'Simple tool');

      expect(tool.wiringFile, isNull);
      expect(tool.defaultIncludes, isNull);
      expect(tool.hasWiring, isFalse);
    });

    test('BB-TDF-48: kAutoWiringFile enables hasWiring [2026-02-27]', () {
      const tool = ToolDefinition(
        name: 'buildkit',
        description: 'Build toolkit',
        wiringFile: ToolDefinition.kAutoWiringFile,
      );

      expect(tool.wiringFile, equals(''));
      expect(tool.hasWiring, isTrue);
    });

    test('BB-TDF-49: Explicit wiringFile enables hasWiring [2026-02-27]', () {
      const tool = ToolDefinition(
        name: 'testkit',
        description: 'Test toolkit',
        wiringFile: 'testkit_master.yaml',
      );

      expect(tool.wiringFile, equals('testkit_master.yaml'));
      expect(tool.hasWiring, isTrue);
    });

    test('BB-TDF-50: defaultIncludes enables hasWiring [2026-02-27]', () {
      const tool = ToolDefinition(
        name: 'buildkit',
        description: 'Build toolkit',
        defaultIncludes: [
          ToolWiringEntry(binary: 'astgen', mode: WiringMode.standalone),
        ],
      );

      expect(tool.wiringFile, isNull);
      expect(tool.defaultIncludes, hasLength(1));
      expect(tool.hasWiring, isTrue);
    });

    test('BB-TDF-51: Both wiringFile and defaultIncludes [2026-02-27]', () {
      const tool = ToolDefinition(
        name: 'buildkit',
        description: 'Build toolkit',
        wiringFile: ToolDefinition.kAutoWiringFile,
        defaultIncludes: [
          ToolWiringEntry(
            binary: 'testkit',
            mode: WiringMode.multiCommand,
            commands: {'bt': 'test'},
          ),
          ToolWiringEntry(binary: 'astgen', mode: WiringMode.standalone),
          ToolWiringEntry(binary: 'd4rtgen', mode: WiringMode.standalone),
        ],
      );

      expect(tool.hasWiring, isTrue);
      expect(tool.defaultIncludes, hasLength(3));
      expect(tool.defaultIncludes![0].hostCommandNames, equals({'bt'}));
      expect(tool.defaultIncludes![1].hostCommandNames, equals({'astgen'}));
    });

    test('BB-TDF-52: copyWith preserves wiring fields [2026-02-27]', () {
      const tool = ToolDefinition(
        name: 'buildkit',
        description: 'Build toolkit',
        wiringFile: ToolDefinition.kAutoWiringFile,
        defaultIncludes: [
          ToolWiringEntry(binary: 'astgen', mode: WiringMode.standalone),
        ],
      );

      final derived = tool.copyWith(name: 'supertool');

      expect(derived.name, equals('supertool'));
      expect(derived.wiringFile, equals(ToolDefinition.kAutoWiringFile));
      expect(derived.defaultIncludes, hasLength(1));
      expect(derived.hasWiring, isTrue);
    });

    test('BB-TDF-53: copyWith overrides wiring fields [2026-02-27]', () {
      const tool = ToolDefinition(
        name: 'buildkit',
        description: 'Build toolkit',
        wiringFile: ToolDefinition.kAutoWiringFile,
        defaultIncludes: [
          ToolWiringEntry(binary: 'astgen', mode: WiringMode.standalone),
        ],
      );

      final derived = tool.copyWith(
        wiringFile: 'custom_master.yaml',
        defaultIncludes: [
          const ToolWiringEntry(
            binary: 'testkit',
            mode: WiringMode.multiCommand,
            commands: {'bt': 'test'},
          ),
        ],
      );

      expect(derived.wiringFile, equals('custom_master.yaml'));
      expect(derived.defaultIncludes, hasLength(1));
      expect(derived.defaultIncludes!.first.binary, equals('testkit'));
    });

    test('BB-TDF-54: Full buildkit-like wiring definition [2026-02-27]', () {
      const tool = ToolDefinition(
        name: 'buildkit',
        description: 'Pipeline-based build orchestration',
        version: '3.1.0',
        mode: ToolMode.multiCommand,
        features: NavigationFeatures.all,
        wiringFile: ToolDefinition.kAutoWiringFile,
        defaultIncludes: [
          ToolWiringEntry(
            binary: 'testkit',
            mode: WiringMode.multiCommand,
            commands: {'buildkittest': 'test', 'buildkitbaseline': 'baseline'},
          ),
          ToolWiringEntry(binary: 'astgen', mode: WiringMode.standalone),
          ToolWiringEntry(binary: 'd4rtgen', mode: WiringMode.standalone),
        ],
        commands: [
          CommandDefinition(name: 'cleanup', description: 'Clean artifacts'),
          CommandDefinition(name: 'versioner', description: 'Manage versions'),
          CommandDefinition(name: 'compiler', description: 'Compile project'),
        ],
      );

      expect(tool.hasWiring, isTrue);
      expect(tool.defaultIncludes, hasLength(3));
      expect(tool.commands, hasLength(3));

      // testkit wiring gives 2 host commands
      expect(
        tool.defaultIncludes![0].hostCommandNames,
        equals({'buildkittest', 'buildkitbaseline'}),
      );
      // standalone tools give one host command each (binary name)
      expect(tool.defaultIncludes![1].hostCommandNames, equals({'astgen'}));
      expect(tool.defaultIncludes![2].hostCommandNames, equals({'d4rtgen'}));
    });
  });
}
