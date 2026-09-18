// An option means the same thing wherever it is written relative to its
// command name.
//
// The parser routes by position: an option before the command name lands in
// `extraOptions`, one after it in `commandArgs[<command>].options`. An
// executor reading only one silently ignored the other — and the DOCUMENTED
// form is the trailing one. `CLAUDE.md` shows `testkit :test --test-args="…"`
// and testkit's own help prints `testkit :baseline --test-args="--tags e2e"`,
// so the form everyone is told to use was the broken one:
// `testkit :baseline --test-args="--name nomatch"` ran the whole suite and
// reported on tests the caller never asked about.
//
// buildkit had worked around it privately in eight executors, each with its
// own copy of "per-command options for this command, else global". This is
// that helper, once, where CliArgs can answer it.

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// A tool whose command declares both a long and an abbreviated option, and
/// carries an alias — the parser keys per-command options by the name the
/// caller TYPED, so the alias is part of the contract.
const _tool = ToolDefinition(
  name: 'zomkit',
  description: 'Option-position fixture',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  commands: [
    CommandDefinition(
      name: 'baseline',
      description: 'Create a baseline',
      aliases: ['b'],
      options: [
        OptionDefinition.option(
          name: 'test-args',
          description: 'Arguments passed through',
          valueName: 'args',
        ),
        OptionDefinition.option(
          name: 'comment',
          abbr: 'c',
          description: 'Column label',
          valueName: 'text',
        ),
      ],
    ),
  ],
);

CliArgs _parse(List<String> argv) =>
    CliArgParser(toolDefinition: _tool).parse(argv);

void main() {
  group('BB-OPTPOS: an option is found in either position', () {
    test('BB-OPTPOS-1: an option written BEFORE the command is found '
        '[2026-09-18]', () {
      final args = _parse(['--test-args=--name x', ':baseline']);
      expect(
        args.extraOptions['test-args'],
        '--name x',
        reason: 'the fixture must actually exercise the global position',
      );
      expect(args.optionsFor('baseline')['test-args'], '--name x');
    });

    test('BB-OPTPOS-2: an option written AFTER the command is found — the case '
        'that was dropped [2026-09-18]', () {
      final args = _parse([':baseline', '--test-args=--name x']);
      // Anti-vacuity: prove the parser really put it somewhere else, so this
      // test cannot pass by the option having been global all along.
      expect(
        args.extraOptions,
        isNot(contains('test-args')),
        reason: 'a trailing option is NOT global; that is the whole defect',
      );
      expect(args.optionsFor('baseline')['test-args'], '--name x');
    });

    test('BB-OPTPOS-3: an abbreviated option after the command keeps its value '
        '[2026-09-18]', () {
      final args = _parse([':baseline', '-c', 'label']);
      expect(args.optionsFor('baseline')['comment'], 'label');
    });

    test('BB-OPTPOS-4: with the option in both positions, the per-command one '
        'wins [2026-09-18]', () {
      final args = _parse([
        '--test-args=global',
        ':baseline',
        '--test-args=percommand',
      ]);
      expect(args.optionsFor('baseline')['test-args'], 'percommand');
    });

    test(
      'BB-OPTPOS-5: options land under the name the caller typed, so an alias '
      'must be named [2026-09-18]',
      () {
        final args = _parse([':b', '--test-args=--name x']);
        expect(
          args.commandArgs.keys,
          contains('b'),
          reason: 'the parser keys by the typed name, not the canonical one',
        );
        expect(
          args.optionsFor('baseline')['test-args'],
          isNull,
          reason: 'without its aliases the lookup cannot find them',
        );
        expect(
          args.optionsFor('baseline', aliases: ['b'])['test-args'],
          '--name x',
        );
      },
    );

    test('BB-OPTPOS-6: a command with no options given yields the globals '
        '[2026-09-18]', () {
      final args = _parse(['--test-args=global', ':baseline']);
      expect(args.optionsFor('baseline'), containsPair('test-args', 'global'));
      expect(
        _parse([':baseline']).optionsFor('baseline'),
        isEmpty,
        reason: 'nothing given anywhere means nothing found',
      );
    });
  });
}
