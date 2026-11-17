/// A tool of stand-alone commands ([ToolDefinition.strictCommandOptions]):
/// each command holds to the options it declares, gets its declared defaults
/// and checks, has positionals of its own, keeps a flag that shares a name
/// with a global one, and a usage error ends the run with the tool's
/// [ToolDefinition.usageErrorExitCode] on [ToolRunner.errorOutput].
library;

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

const _options = [
  OptionDefinition.option(name: 'package', abbr: 'p', description: 'pkg'),
  OptionDefinition.option(
    name: 'out',
    abbr: 'o',
    description: 'out',
    defaultValue: 'out-default',
  ),
  OptionDefinition.option(
    name: 'standard',
    description: 'std',
    allowedValues: ['openapi', 'markdown'],
  ),
  OptionDefinition.multi(name: 'extra', description: 'repeated'),
  OptionDefinition.multi(
    name: 'split',
    description: 'comma separated',
    splitCommas: true,
  ),
  OptionDefinition.flag(name: 'json', description: 'json'),
  OptionDefinition.flag(
    name: 'record',
    description: 'record',
    negatable: true,
    defaultValue: 'true',
  ),
  OptionDefinition.flag(name: 'verbose', abbr: 'v', description: 'own'),
  OptionDefinition.flag(name: 'dry-run', description: 'own dry run'),
  OptionDefinition.option(name: 'root', description: 'own root'),
];

ToolDefinition _tool({bool strict = true}) => ToolDefinition(
  name: 'specs',
  description: 'stand-alone commands',
  version: '1.2.3',
  versionString: 'specs 1.2.3+4.abcdef0',
  features: const NavigationFeatures(
    projectTraversal: false,
    recursiveScan: false,
    verbose: false,
  ),
  strictCommandOptions: strict,
  usageErrorExitCode: 2,
  builtInHelpTopics: false,
  commands: [
    for (final name in ['one', 'two', 'three'])
      CommandDefinition(
        name: name,
        description: 'command $name',
        options: name == 'three'
            ? const [
                OptionDefinition.option(
                  name: 'json',
                  description: 'a value option here',
                ),
                OptionDefinition.option(
                  name: 'needed',
                  description: 'mandatory',
                  mandatory: true,
                ),
              ]
            : _options,
        supportsProjectTraversal: false,
        requiresTraversal: false,
        needsEnvironment: false,
      ),
  ],
);

CliArgs _parse(List<String> args, {bool strict = true}) =>
    CliArgParser(toolDefinition: _tool(strict: strict)).parse(args);

class _Exec extends CommandExecutor {
  final String name;
  final int code;
  final List<String> log;
  _Exec(this.name, this.code, this.log);

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      throw StateError('no traversal expected');

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    log.add(name);
    if (code == 0) return const ToolResult.success();
    return ToolResult.fromItems([
      ItemResult.failure(path: '.', name: name, error: 'x', exitCode: code),
    ]);
  }
}

void main() {
  group('SCO1: positionals per command', () {
    test('BB-SCO-1: each command gets the positionals written after it', () {
      final args = _parse([':one', 'a', 'b', ':two', 'c']);
      expect(args.commandArgs['one']!.positionalArgs, ['a', 'b']);
      expect(args.commandArgs['two']!.positionalArgs, ['c']);
      expect(args.positionalArgs, ['a', 'b', 'c']);
    });
    test('BB-SCO-2: also without strict options', () {
      final args = _parse([':one', 'a', ':two', 'c'], strict: false);
      expect(args.commandArgs['one']!.positionalArgs, ['a']);
      expect(args.commandArgs['two']!.positionalArgs, ['c']);
    });
  });

  group('SCO2: a command negatable flag', () {
    test('BB-SCO-3: --no-x sets x false, strict or not', () {
      for (final strict in [true, false]) {
        final args = _parse([':one', '--no-record'], strict: strict);
        expect(args.commandArgs['one']!.options['record'], isFalse);
        expect(
          args.commandArgs['one']!.options.containsKey('no-record'),
          isFalse,
        );
      }
    });
  });

  group('SCO3: strict options', () {
    test('BB-SCO-4: values, abbreviations, repeated and split values', () {
      final args = _parse([
        ':one',
        '-p',
        'pkg',
        '--standard',
        'markdown',
        '--extra',
        'a,b',
        '--extra',
        'c',
        '--split',
        'x,y',
        '--json',
        'doc.yaml',
      ]);
      expect(args.argumentErrors, isEmpty);
      final o = args.commandArgs['one']!.options;
      expect(o['package'], 'pkg');
      expect(o['standard'], 'markdown');
      expect(o['extra'], ['a,b', 'c']);
      expect(o['split'], ['x', 'y']);
      expect(o['json'], isTrue);
      expect(args.commandArgs['one']!.positionalArgs, ['doc.yaml']);
    });

    test('BB-SCO-5: declared defaults fill what was not given', () {
      final o = _parse([':one']).commandArgs['one']!.options;
      expect(o['out'], 'out-default');
      expect(o['record'], isTrue);
      expect(o.containsKey('json'), isFalse);
    });

    test(
      'BB-SCO-6: an undeclared option is an argument error; --help and -v are not',
      () {
        expect(
          _parse([':one', '--bogus']).argumentErrors.single,
          allOf(
            contains('`:one` has no option `--bogus`'),
            contains('`specs :one --help`'),
          ),
        );
        expect(_parse([':one', '--scan', '.']).argumentErrors, isNotEmpty);
        expect(
          _parse([':three', '--needed', 'x', '-v']).argumentErrors,
          isEmpty,
        );
        expect(_parse([':one', '--help']).help, isTrue);
      },
    );

    test(
      'BB-SCO-7: a flag the command declares is its own, also under a global name',
      () {
        final args = _parse([':one', '-v', '--dry-run', '--root', 'r']);
        expect(args.argumentErrors, isEmpty);
        final o = args.commandArgs['one']!.options;
        expect(o['verbose'], isTrue);
        expect(o['dry-run'], isTrue);
        expect(o['root'], 'r');
        expect(args.verbose, isFalse);
        expect(args.dryRun, isFalse);
      },
    );

    test(
      'BB-SCO-8: a value outside allowedValues, a missing mandatory option, a value '
      'option without a value and a flag with one are errors',
      () {
        expect(
          _parse([':one', '--standard', 'icu']).argumentErrors.single,
          contains('takes one of openapi, markdown'),
        );
        expect(
          _parse([':three']).argumentErrors.single,
          contains('`:three` needs `--needed`'),
        );
        expect(
          _parse([':one', '--package']).argumentErrors.single,
          contains('needs a value'),
        );
        expect(
          _parse([':one', '--json=yes']).argumentErrors.single,
          contains('takes no value'),
        );
      },
    );

    test(
      'BB-SCO-9: a name is a flag or a value option by the command it is written '
      'after',
      () {
        final args = _parse([
          ':one',
          '--json',
          'a.yaml',
          ':three',
          '--json',
          'v',
          '--needed',
          'n',
        ]);
        expect(args.argumentErrors, isEmpty);
        expect(args.commandArgs['one']!.options['json'], isTrue);
        expect(args.commandArgs['one']!.positionalArgs, ['a.yaml']);
        expect(args.commandArgs['three']!.options['json'], 'v');
      },
    );

    test(
      'BB-SCO-10: without strict options nothing is checked or defaulted',
      () {
        final args = _parse([
          ':one',
          '--bogus',
          '--standard',
          'icu',
        ], strict: false);
        expect(args.argumentErrors, isEmpty);
        expect(args.commandArgs['one']!.options.containsKey('out'), isFalse);
      },
    );
  });

  group('SCO4: running stand-alone commands', () {
    Future<(ToolResult, String, String, List<String>)> run(
      List<String> args, {
      Map<String, int> codes = const {},
    }) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final log = <String>[];
      final runner = ToolRunner(
        tool: _tool(),
        executors: {
          for (final n in ['one', 'two', 'three'])
            n: _Exec(n, codes[n] ?? 0, log),
        },
        output: out,
        errorOutput: err,
      );
      final result = await runner.run(args);
      return (result, '$out', '$err', log);
    }

    test(
      'BB-SCO-11: commands run in order and the runner writes nothing on success',
      () async {
        final (r, out, err, log) = await run([':one', ':two']);
        expect(r.exitCode, 0);
        expect(log, ['one', 'two']);
        expect(out, isEmpty);
        expect(err, isEmpty);
      },
    );

    for (final code in [1, 2, 3]) {
      test(
        'BB-SCO-12: a failing command stops the run with its own exit code $code',
        () async {
          final (r, _, _, log) = await run(
            [':one', ':two', ':three', '--needed', 'n'],
            codes: {'two': code},
          );
          expect(log, ['one', 'two']);
          expect(r.exitCode, code);
        },
      );
    }

    test(
      'BB-SCO-13: a usage error exits with usageErrorExitCode on errorOutput, and '
      'runs nothing',
      () async {
        final (r, out, err, log) = await run([':one', ':two', '--bogus']);
        expect(r.exitCode, 2);
        expect(log, isEmpty);
        expect(out, isEmpty);
        expect(err, contains('has no option `--bogus`'));
        final (u, _, uerr, ulog) = await run([':one', ':nosuch']);
        expect(u.exitCode, 2);
        expect(ulog, isEmpty);
        expect(uerr, contains('Unknown command: :nosuch'));
      },
    );

    test(
      'BB-SCO-14: --version prints the versionString; the help lists the commands '
      'and no master-YAML topics, a command help its allowed values',
      () async {
        final (_, version, _, _) = await run(['--version']);
        expect(version, startsWith('specs 1.2.3+4.abcdef0'));
        final (_, help, _, _) = await run(['--help']);
        expect(help, contains(':one'));
        expect(help, contains(':three'));
        expect(help, isNot(contains('pipelines')));
        final (_, cmdHelp, _, _) = await run([':one', '--help']);
        expect(cmdHelp, contains('One of: openapi, markdown'));
        expect(cmdHelp, contains('--no-record'));
      },
    );
  });
}
