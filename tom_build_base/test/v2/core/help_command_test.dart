import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// `<tool> help <command>` prints the help of the tool's own command, as
/// `<tool> :<command> --help` does: by name, by alias, with the leading colon,
/// and by an unambiguous prefix. Help topics keep their place (a topic is
/// looked up before a command), and a name that is neither stays an unknown
/// help topic. A nested tool asked `--nested help <command>` (how a host
/// delegates the help of a wired command) answers with that command's help.
///
/// Test IDs: BB-HELPCMD-1..7.

const _tool = ToolDefinition(
  name: 'helptool',
  description: 'Tool for the help-command tests',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.all,
  helpTopics: [
    HelpTopic(
      name: 'layout',
      summary: 'How the folders are laid out',
      content: 'The layout topic text.',
    ),
  ],
  commands: [
    CommandDefinition(
      name: 'compiler',
      description: 'Compiles the projects',
      aliases: ['comp'],
      options: [
        OptionDefinition.option(name: 'target', description: 'The target'),
      ],
    ),
    CommandDefinition(
      name: 'bumpversion',
      description: 'Bumps the version',
      aliases: ['bump'],
    ),
    CommandDefinition(name: 'cleanup', description: 'Removes build output'),
  ],
);

class _Noop extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.success(path: context.path, name: context.name);
}

void main() {
  Future<(ToolResult, String)> run(List<String> args) async {
    final out = StringBuffer();
    final result = await ToolRunner(
      tool: _tool,
      output: out,
      executors: {
        'compiler': _Noop(),
        'bumpversion': _Noop(),
        'cleanup': _Noop(),
      },
    ).run(args);
    return (result, out.toString());
  }

  Future<String> commandHelp(String command) async =>
      (await run([':$command', '--help'])).$2;

  test('BB-HELPCMD-1: `help <command>` prints what `:<command> --help` '
      'prints [2026-11-15]', () async {
    final (result, out) = await run(['help', 'compiler']);
    expect(result.success, isTrue, reason: out);
    expect(out, isNot(contains('Unknown help topic')));
    expect(out, contains('Compiles the projects'));
    expect(out, contains('--target'));
    expect(out, await commandHelp('compiler'));
  });

  test('BB-HELPCMD-2: an alias and an unambiguous prefix name the command '
      '[2026-11-15]', () async {
    final bumpHelp = await commandHelp('bumpversion');
    for (final name in ['bump', 'bumpv']) {
      final (result, out) = await run(['help', name]);
      expect(result.success, isTrue, reason: name);
      expect(out, bumpHelp, reason: name);
    }
  });

  test('BB-HELPCMD-3: `help :<command>` prints the command\'s help, not the '
      'tool overview [2026-11-15]', () async {
    for (final name in [':compiler', ':comp']) {
      final (result, out) = await run(['help', name]);
      expect(result.success, isTrue, reason: name);
      expect(out, await commandHelp('compiler'), reason: name);
      expect(out, isNot(contains('Removes build output')), reason: name);
    }
  });

  test('BB-HELPCMD-4: a help topic and the built-in macro help are found '
      'as before [2026-11-15]', () async {
    final (result, out) = await run(['help', 'layout']);
    expect(result.success, isTrue);
    expect(out, contains('The layout topic text.'));
    for (final name in ['macro', ':macro']) {
      final (macro, macroOut) = await run(['help', name]);
      expect(macro.success, isTrue, reason: name);
      expect(macroOut, contains('Command: :macro'), reason: name);
    }
  });

  test('BB-HELPCMD-5: a name that is no topic and no command stays unknown; '
      'an ambiguous prefix lists its commands [2026-11-15]', () async {
    final (unknown, unknownOut) = await run(['help', 'nosuch']);
    expect(unknown.success, isFalse);
    expect(unknownOut, contains('Unknown help topic: nosuch'));

    final (unknownCmd, unknownCmdOut) = await run(['help', ':nosuch']);
    expect(unknownCmd.success, isFalse);
    expect(unknownCmdOut, contains('Unknown help topic: :nosuch'));

    final (ambiguous, ambiguousOut) = await run(['help', 'c']);
    expect(ambiguous.success, isFalse);
    expect(ambiguousOut, contains('Ambiguous command prefix ":c" matches:'));
    expect(ambiguousOut, contains(':compiler'));
    expect(ambiguousOut, contains(':cleanup'));
  });

  test('BB-HELPCMD-6: `help` alone still prints the tool overview '
      '[2026-11-15]', () async {
    final (result, out) = await run(['help']);
    expect(result.success, isTrue);
    expect(out, contains('Compiles the projects'));
    expect(out, contains('Removes build output'));
  });

  test('BB-HELPCMD-7: `--nested help <command>` answers with the command\'s '
      'help and runs nothing [2026-11-15]', () async {
    for (final name in ['compiler', 'comp', ':compiler']) {
      final (result, out) = await run(['--nested', 'help', name]);
      expect(result.success, isTrue, reason: name);
      expect(out, contains('Compiles the projects'), reason: name);
      expect(out, contains('--target'), reason: name);
    }
    final (unknown, unknownOut) = await run(['--nested', 'help', 'nosuch']);
    expect(unknown.success, isFalse);
    expect(unknownOut, contains('Unknown help topic: nosuch'));
  });
}
