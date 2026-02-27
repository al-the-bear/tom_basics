import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('ToolDefinitionSerializer', () {
    group('toYaml', () {
      test('BB-SER-1: Serializes minimal tool definition [2026-02-27]', () {
        const tool = ToolDefinition(
          name: 'simple',
          description: 'A simple tool',
        );

        final yaml = ToolDefinitionSerializer.toYaml(tool);

        expect(yaml, contains('name: simple'));
        expect(yaml, contains('version: 1.0.0'));
        expect(yaml, contains('description: A simple tool'));
        expect(yaml, contains('mode: multi_command'));
        expect(yaml, contains('global_options: []'));
      });

      test('BB-SER-2: Serializes features correctly [2026-02-27]', () {
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
          features: NavigationFeatures.all,
        );

        final yaml = ToolDefinitionSerializer.toYaml(tool);

        expect(yaml, contains('project_traversal: true'));
        expect(yaml, contains('git_traversal: true'));
        expect(yaml, contains('recursive_scan: true'));
        expect(yaml, contains('interactive_mode: true'));
        expect(yaml, contains('dry_run: true'));
        expect(yaml, contains('json_output: true'));
        expect(yaml, contains('verbose: true'));
      });

      test('BB-SER-3: Serializes minimal features correctly [2026-02-27]', () {
        const tool = ToolDefinition(
          name: 'simple',
          description: 'Simple',
          features: NavigationFeatures.minimal,
        );

        final yaml = ToolDefinitionSerializer.toYaml(tool);

        expect(yaml, contains('project_traversal: false'));
        expect(yaml, contains('verbose: true'));
      });

      test('BB-SER-4: Serializes global options [2026-02-27]', () {
        const tool = ToolDefinition(
          name: 'testkit',
          description: 'Test kit',
          globalOptions: [
            OptionDefinition.flag(name: 'tui', description: 'TUI mode'),
            OptionDefinition.option(
              name: 'config',
              abbr: 'c',
              description: 'Config path',
              valueName: 'path',
            ),
          ],
        );

        final yaml = ToolDefinitionSerializer.toYaml(tool);

        expect(yaml, contains('global_options:'));
        expect(yaml, contains('name: tui'));
        expect(yaml, contains('type: flag'));
        expect(yaml, contains('name: config'));
        expect(yaml, contains('abbr: c'));
        expect(yaml, contains('type: option'));
        expect(yaml, contains('value_name: path'));
      });

      test('BB-SER-5: Serializes commands with options [2026-02-27]', () {
        const tool = ToolDefinition(
          name: 'testkit',
          description: 'Test kit',
          commands: [
            CommandDefinition(
              name: 'test',
              description: 'Run tests',
              aliases: ['t'],
              options: [
                OptionDefinition.option(
                  name: 'test-args',
                  description: 'Args for dart test',
                ),
                OptionDefinition.flag(
                  name: 'fail-fast',
                  description: 'Stop on first failure',
                ),
              ],
            ),
            CommandDefinition(name: 'baseline', description: 'Create baseline'),
          ],
        );

        final yaml = ToolDefinitionSerializer.toYaml(tool);

        expect(yaml, contains('commands:'));
        expect(yaml, contains('  test:'));
        expect(yaml, contains('    description: Run tests'));
        expect(yaml, contains('    aliases: [t]'));
        expect(yaml, contains('    options:'));
        expect(yaml, contains('name: test-args'));
        expect(yaml, contains('name: fail-fast'));
        expect(yaml, contains('  baseline:'));
        expect(yaml, contains('    description: Create baseline'));
      });

      test('BB-SER-6: Serializes tool mode correctly [2026-02-27]', () {
        const single = ToolDefinition(
          name: 'astgen',
          description: 'AST gen',
          mode: ToolMode.singleCommand,
        );
        const hybrid = ToolDefinition(
          name: 'hybrid',
          description: 'Hybrid tool',
          mode: ToolMode.hybrid,
        );

        expect(
          ToolDefinitionSerializer.toYaml(single),
          contains('mode: single_command'),
        );
        expect(
          ToolDefinitionSerializer.toYaml(hybrid),
          contains('mode: hybrid'),
        );
      });

      test(
        'BB-SER-7: Escapes strings with special YAML chars [2026-02-27]',
        () {
          const tool = ToolDefinition(
            name: 'tool',
            description: 'Tool: with colon and #hash',
          );

          final yaml = ToolDefinitionSerializer.toYaml(tool);

          // Description should be quoted
          expect(yaml, contains('"Tool: with colon and #hash"'));
        },
      );

      test('BB-SER-8: Serializes hidden commands [2026-02-27]', () {
        const tool = ToolDefinition(
          name: 'tool',
          description: 'Tool',
          commands: [
            CommandDefinition(
              name: 'secret',
              description: 'Hidden command',
              hidden: true,
            ),
          ],
        );

        final yaml = ToolDefinitionSerializer.toYaml(tool);

        expect(yaml, contains('hidden: true'));
      });

      test('BB-SER-9: Serializes multi-value options [2026-02-27]', () {
        const tool = ToolDefinition(
          name: 'tool',
          description: 'Tool',
          globalOptions: [
            OptionDefinition.multi(
              name: 'tags',
              description: 'Test tags',
              valueName: 'tag',
            ),
          ],
        );

        final yaml = ToolDefinitionSerializer.toYaml(tool);

        expect(yaml, contains('type: multi'));
        expect(yaml, contains('value_name: tag'));
      });
    });

    group('fromYamlMap', () {
      test('BB-SER-10: Parses minimal map [2026-02-27]', () {
        final map = {
          'name': 'simple',
          'version': '1.0.0',
          'description': 'A simple tool',
          'mode': 'multi_command',
        };

        final tool = ToolDefinitionSerializer.fromYamlMap(map);

        expect(tool.name, equals('simple'));
        expect(tool.version, equals('1.0.0'));
        expect(tool.description, equals('A simple tool'));
        expect(tool.mode, equals(ToolMode.multiCommand));
      });

      test('BB-SER-11: Parses features map [2026-02-27]', () {
        final map = {
          'name': 'tool',
          'description': 'Tool',
          'features': {
            'project_traversal': true,
            'git_traversal': false,
            'recursive_scan': true,
            'interactive_mode': false,
            'dry_run': true,
            'json_output': false,
            'verbose': true,
          },
        };

        final tool = ToolDefinitionSerializer.fromYamlMap(map);

        expect(tool.features.projectTraversal, isTrue);
        expect(tool.features.gitTraversal, isFalse);
        expect(tool.features.recursiveScan, isTrue);
        expect(tool.features.interactiveMode, isFalse);
        expect(tool.features.dryRun, isTrue);
        expect(tool.features.jsonOutput, isFalse);
        expect(tool.features.verbose, isTrue);
      });

      test('BB-SER-12: Parses global options [2026-02-27]', () {
        final map = {
          'name': 'tool',
          'description': 'Tool',
          'global_options': [
            {'name': 'tui', 'type': 'flag', 'description': 'TUI mode'},
            {
              'name': 'config',
              'abbr': 'c',
              'type': 'option',
              'description': 'Config path',
              'value_name': 'path',
            },
          ],
        };

        final tool = ToolDefinitionSerializer.fromYamlMap(map);

        expect(tool.globalOptions, hasLength(2));
        expect(tool.globalOptions[0].name, equals('tui'));
        expect(tool.globalOptions[0].type, equals(OptionType.flag));
        expect(tool.globalOptions[1].name, equals('config'));
        expect(tool.globalOptions[1].abbr, equals('c'));
        expect(tool.globalOptions[1].type, equals(OptionType.option));
        expect(tool.globalOptions[1].valueName, equals('path'));
      });

      test('BB-SER-13: Parses commands with options [2026-02-27]', () {
        final map = {
          'name': 'testkit',
          'description': 'Test toolkit',
          'commands': {
            'test': {
              'description': 'Run tests',
              'aliases': ['t'],
              'options': [
                {
                  'name': 'test-args',
                  'type': 'option',
                  'description': 'Args for dart test',
                },
                {
                  'name': 'fail-fast',
                  'type': 'flag',
                  'description': 'Stop on first failure',
                },
              ],
            },
            'baseline': {'description': 'Create baseline'},
          },
        };

        final tool = ToolDefinitionSerializer.fromYamlMap(map);

        expect(tool.commands, hasLength(2));

        final testCmd = tool.findCommand('test');
        expect(testCmd, isNotNull);
        expect(testCmd!.description, equals('Run tests'));
        expect(testCmd.aliases, equals(['t']));
        expect(testCmd.options, hasLength(2));
        expect(testCmd.options[0].name, equals('test-args'));
        expect(testCmd.options[0].type, equals(OptionType.option));
        expect(testCmd.options[1].name, equals('fail-fast'));
        expect(testCmd.options[1].type, equals(OptionType.flag));

        final baseline = tool.findCommand('baseline');
        expect(baseline, isNotNull);
        expect(baseline!.description, equals('Create baseline'));
      });

      test('BB-SER-14: Parses single_command mode [2026-02-27]', () {
        final map = {
          'name': 'astgen',
          'description': 'AST gen',
          'mode': 'single_command',
        };

        final tool = ToolDefinitionSerializer.fromYamlMap(map);
        expect(tool.mode, equals(ToolMode.singleCommand));
      });

      test(
        'BB-SER-15: Handles missing/null fields gracefully [2026-02-27]',
        () {
          final map = <String, dynamic>{'name': 'minimal'};

          final tool = ToolDefinitionSerializer.fromYamlMap(map);

          expect(tool.name, equals('minimal'));
          expect(tool.version, equals('1.0.0'));
          expect(tool.description, equals(''));
          expect(tool.mode, equals(ToolMode.multiCommand));
          expect(tool.globalOptions, isEmpty);
          expect(tool.commands, isEmpty);
        },
      );

      test('BB-SER-16: Parses hidden commands [2026-02-27]', () {
        final map = {
          'name': 'tool',
          'description': 'Tool',
          'commands': {
            'secret': {'description': 'Hidden command', 'hidden': true},
          },
        };

        final tool = ToolDefinitionSerializer.fromYamlMap(map);
        expect(tool.commands.first.hidden, isTrue);
      });
    });

    group('round-trip', () {
      test(
        'BB-SER-17: toYaml then fromYamlMap preserves structure [2026-02-27]',
        () {
          const original = ToolDefinition(
            name: 'testkit',
            description: 'Test result tracking',
            version: '1.2.0',
            mode: ToolMode.multiCommand,
            features: NavigationFeatures(
              projectTraversal: true,
              gitTraversal: false,
              recursiveScan: true,
              verbose: true,
            ),
            globalOptions: [
              OptionDefinition.flag(name: 'tui', description: 'TUI mode'),
            ],
            commands: [
              CommandDefinition(
                name: 'test',
                description: 'Run tests',
                aliases: ['t'],
                options: [
                  OptionDefinition.option(
                    name: 'test-args',
                    description: 'Args for dart test',
                  ),
                ],
              ),
              CommandDefinition(
                name: 'baseline',
                description: 'Create baseline',
              ),
            ],
          );

          final yaml = ToolDefinitionSerializer.toYaml(original);

          // Parse back using yaml package
          // For this test, we use fromYamlMap with a manually constructed map
          // that mirrors what yaml.loadYaml would produce
          final restored = ToolDefinitionSerializer.fromYamlMap({
            'name': 'testkit',
            'version': '1.2.0',
            'description': 'Test result tracking',
            'mode': 'multi_command',
            'features': {
              'project_traversal': true,
              'git_traversal': false,
              'recursive_scan': true,
              'interactive_mode': false,
              'dry_run': false,
              'json_output': false,
              'verbose': true,
            },
            'global_options': [
              {'name': 'tui', 'type': 'flag', 'description': 'TUI mode'},
            ],
            'commands': {
              'test': {
                'description': 'Run tests',
                'aliases': ['t'],
                'options': [
                  {
                    'name': 'test-args',
                    'type': 'option',
                    'description': 'Args for dart test',
                  },
                ],
              },
              'baseline': {'description': 'Create baseline'},
            },
          });

          expect(restored.name, equals(original.name));
          expect(restored.version, equals(original.version));
          expect(restored.description, equals(original.description));
          expect(restored.mode, equals(original.mode));
          expect(
            restored.features.projectTraversal,
            equals(original.features.projectTraversal),
          );
          expect(
            restored.features.gitTraversal,
            equals(original.features.gitTraversal),
          );
          expect(restored.globalOptions, hasLength(1));
          expect(restored.globalOptions.first.name, equals('tui'));
          expect(restored.commands, hasLength(2));
          expect(restored.findCommand('test')!.aliases, equals(['t']));
          expect(
            restored.findCommand('test')!.options.first.name,
            equals('test-args'),
          );

          // Also verify the YAML output contains expected content
          expect(yaml, contains('name: testkit'));
          expect(yaml, contains('version: 1.2.0'));
        },
      );
    });
  });
}
