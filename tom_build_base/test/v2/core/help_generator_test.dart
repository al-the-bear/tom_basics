import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('HelpGenerator', () {
    group('generateToolHelp', () {
      test('BB-HLP-1: Includes tool name and version [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'mytool',
          description: 'My tool',
          version: '2.0.0',
        );

        final help = HelpGenerator.generateToolHelp(tool);

        expect(help, contains('mytool'));
        expect(help, contains('v2.0.0'));
      });

      test('BB-HLP-2: Includes tool description [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'mytool',
          description: 'My awesome tool',
        );

        final help = HelpGenerator.generateToolHelp(tool);

        expect(help, contains('My awesome tool'));
      });

      test('BB-HLP-3: Includes usage for multi-command tool [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'mytool',
          description: 'My tool',
          mode: ToolMode.multiCommand,
        );

        final help = HelpGenerator.generateToolHelp(tool);

        expect(help, contains('mytool [global-options] :command [command-options]'));
      });

      test('BB-HLP-4: Includes usage for single-command tool [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'mytool',
          description: 'My tool',
          mode: ToolMode.singleCommand,
        );

        final help = HelpGenerator.generateToolHelp(tool);

        expect(help, contains('mytool [options]'));
      });

      test('BB-HLP-5: Lists global options [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'mytool',
          description: 'My tool',
          globalOptions: [
            OptionDefinition.flag(
              name: 'verbose',
              abbr: 'v',
              description: 'Enable verbose output',
            ),
          ],
        );

        final help = HelpGenerator.generateToolHelp(tool);

        expect(help, contains('--verbose'));
        expect(help, contains('-v'));
        expect(help, contains('Enable verbose output'));
      });

      test('BB-HLP-6: Lists commands [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'mytool',
          description: 'My tool',
          mode: ToolMode.multiCommand,
          commands: [
            CommandDefinition(name: 'cleanup', description: 'Clean build'),
            CommandDefinition(name: 'compile', description: 'Compile project'),
          ],
        );

        final help = HelpGenerator.generateToolHelp(tool);

        expect(help, contains(':cleanup'));
        expect(help, contains('Clean build'));
        expect(help, contains(':compile'));
        expect(help, contains('Compile project'));
      });

      test('BB-HLP-7: Shows command aliases [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'mytool',
          description: 'My tool',
          mode: ToolMode.multiCommand,
          commands: [
            CommandDefinition(
              name: 'crossreference',
              description: 'Cross ref',
              aliases: ['crossref', 'xref'],
            ),
          ],
        );

        final help = HelpGenerator.generateToolHelp(tool);

        expect(help, contains(':crossreference'));
        expect(help, contains('crossref'));
        expect(help, contains('xref'));
      });

      test('BB-HLP-8: Excludes hidden commands [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'mytool',
          description: 'My tool',
          mode: ToolMode.multiCommand,
          commands: [
            CommandDefinition(name: 'visible', description: 'Visible'),
            CommandDefinition(name: 'hidden', description: 'Hidden', hidden: true),
          ],
        );

        final help = HelpGenerator.generateToolHelp(tool);

        expect(help, contains(':visible'));
        expect(help, isNot(contains(':hidden')));
      });

      test('BB-HLP-9: Includes help footer [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'mytool',
          description: 'My tool',
          helpFooter: 'This is the footer text.',
        );

        final help = HelpGenerator.generateToolHelp(tool);

        expect(help, contains('This is the footer text.'));
      });

      test('BB-HLP-10: Shows command help hint [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'mytool',
          description: 'My tool',
          mode: ToolMode.multiCommand,
          commands: [
            CommandDefinition(name: 'test', description: 'Test'),
          ],
        );

        final help = HelpGenerator.generateToolHelp(tool);

        expect(help, contains('mytool :command --help'));
      });
    });

    group('generateCommandHelp', () {
      test('BB-HLP-11: Includes command name [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'cleanup',
          description: 'Clean build artifacts',
        );

        final help = HelpGenerator.generateCommandHelp(cmd);

        expect(help, contains(':cleanup'));
      });

      test('BB-HLP-12: Includes command description [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'cleanup',
          description: 'Clean build artifacts',
        );

        final help = HelpGenerator.generateCommandHelp(cmd);

        expect(help, contains('Clean build artifacts'));
      });

      test('BB-HLP-13: Shows aliases [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'crossreference',
          description: 'Cross ref',
          aliases: ['crossref', 'xref'],
        );

        final help = HelpGenerator.generateCommandHelp(cmd);

        expect(help, contains('Aliases'));
        expect(help, contains(':crossref'));
        expect(help, contains(':xref'));
      });

      test('BB-HLP-14: Lists command options [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'test',
          description: 'Run tests',
          options: [
            OptionDefinition.flag(
              name: 'coverage',
              abbr: 'c',
              description: 'Enable coverage',
            ),
            OptionDefinition.option(
              name: 'output',
              abbr: 'o',
              description: 'Output file',
              valueName: 'path',
            ),
          ],
        );

        final help = HelpGenerator.generateCommandHelp(cmd);

        expect(help, contains('--coverage'));
        expect(help, contains('-c'));
        expect(help, contains('Enable coverage'));
        expect(help, contains('--output'));
        expect(help, contains('-o'));
      });

      test('BB-HLP-15: Lists project traversal options when supported [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'compile',
          description: 'Compile',
          supportsProjectTraversal: true,
        );

        final help = HelpGenerator.generateCommandHelp(cmd);

        expect(help, contains('Project Traversal'));
        expect(help, contains('--scan'));
        expect(help, contains('--recursive'));
        expect(help, contains('--project'));
      });

      test('BB-HLP-16: Lists git traversal options when supported [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'gitstatus',
          description: 'Git status',
          supportsGitTraversal: true,
          supportsProjectTraversal: false,
        );

        final help = HelpGenerator.generateCommandHelp(cmd);

        expect(help, contains('Git Traversal'));
        expect(help, contains('--modules'));
        expect(help, contains('--inner-first-git'));
      });

      test('BB-HLP-17: Mentions per-command filter support [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'compile',
          description: 'Compile',
          supportsPerCommandFilter: true,
        );

        final help = HelpGenerator.generateCommandHelp(cmd);

        expect(help, contains('per-command'));
        expect(help, contains('--project'));
        expect(help, contains('--exclude'));
      });

      test('BB-HLP-18: Lists examples [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'test',
          description: 'Run tests',
          examples: [
            'testkit :test',
            'testkit :test --failed',
            'testkit :test -c "bugfix"',
          ],
        );

        final help = HelpGenerator.generateCommandHelp(cmd);

        expect(help, contains('Examples'));
        expect(help, contains('testkit :test'));
        expect(help, contains('testkit :test --failed'));
      });

      test('BB-HLP-19: Uses tool name in usage [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'cleanup',
          description: 'Clean',
        );
        const tool = ToolDefinition(
          name: 'buildkit',
          description: 'Build toolkit',
        );

        final help = HelpGenerator.generateCommandHelp(cmd, tool: tool);

        expect(help, contains('buildkit [global-options] :cleanup [options]'));
      });
    });

    group('generateUsageSummary', () {
      test('BB-HLP-20: Shows basic usage [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'mytool',
          description: 'My tool',
        );

        final summary = HelpGenerator.generateUsageSummary(tool);

        expect(summary, contains('Usage: mytool'));
        expect(summary, contains('--help'));
      });

      test('BB-HLP-21: Shows commands for multi-command tool [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'mytool',
          description: 'My tool',
          mode: ToolMode.multiCommand,
          commands: [
            CommandDefinition(name: 'a', description: 'A'),
            CommandDefinition(name: 'b', description: 'B'),
            CommandDefinition(name: 'c', description: 'C'),
          ],
        );

        final summary = HelpGenerator.generateUsageSummary(tool);

        expect(summary, contains('Commands:'));
        expect(summary, contains(':a'));
        expect(summary, contains(':b'));
        expect(summary, contains(':c'));
      });

      test('BB-HLP-22: Truncates command list [2026-02-12]', () {
        const tool = ToolDefinition(
          name: 'mytool',
          description: 'My tool',
          mode: ToolMode.multiCommand,
          commands: [
            CommandDefinition(name: 'a', description: 'A'),
            CommandDefinition(name: 'b', description: 'B'),
            CommandDefinition(name: 'c', description: 'C'),
            CommandDefinition(name: 'd', description: 'D'),
            CommandDefinition(name: 'e', description: 'E'),
            CommandDefinition(name: 'f', description: 'F'),
            CommandDefinition(name: 'g', description: 'G'),
          ],
        );

        final summary = HelpGenerator.generateUsageSummary(tool);

        expect(summary, contains('...'));
      });
    });

    group('generateOptionHelp', () {
      test('BB-HLP-23: Formats flag option [2026-02-12]', () {
        const opt = OptionDefinition.flag(
          name: 'verbose',
          abbr: 'v',
          description: 'Verbose output',
        );

        final help = HelpGenerator.generateOptionHelp(opt);

        expect(help, contains('-v'));
        expect(help, contains('--verbose'));
        expect(help, contains('Verbose output'));
      });

      test('BB-HLP-24: Formats option with value [2026-02-12]', () {
        const opt = OptionDefinition.option(
          name: 'config',
          abbr: 'c',
          description: 'Config file',
          valueName: 'path',
        );

        final help = HelpGenerator.generateOptionHelp(opt);

        expect(help, contains('-c <path>'));
        expect(help, contains('--config'));
        expect(help, contains('Config file'));
      });

      test('BB-HLP-25: Includes default value [2026-02-12]', () {
        const opt = OptionDefinition.option(
          name: 'format',
          description: 'Output format',
          defaultValue: 'json',
        );

        final help = HelpGenerator.generateOptionHelp(opt);

        expect(help, contains('default: json'));
      });
    });
  });
}
