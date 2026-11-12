// BB-MULTI: a multi option given more than once keeps every value (it kept
// only the last one: `testkit :mutations --module a --module b` swept b only).
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

const _tool = ToolDefinition(
  name: 'multitool',
  description: 'Multi option test tool',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.projectTool,
  commands: [
    CommandDefinition(
      name: 'sweep',
      description: 'Takes a multi option',
      aliases: ['sw'],
      options: [
        OptionDefinition.multi(name: 'module', description: 'Modules'),
        OptionDefinition.option(name: 'seed', description: 'A single value'),
      ],
    ),
  ],
);

Map<String, dynamic> _opts(List<String> argv) =>
    CliArgParser(toolDefinition: _tool).parse(argv).optionsFor('sweep');

void main() {
  test('BB-MULTI-1: repeated after the command, every value is kept', () {
    expect(_opts([':sweep', '--module', 'a', '--module', 'b'])['module'], [
      'a',
      'b',
    ]);
    expect(
      _opts([':sweep', '--module=a', '--module=b', '--module=c'])['module'],
      ['a', 'b', 'c'],
    );
  });

  test('BB-MULTI-2: repeated before the command, every value is kept', () {
    expect(_opts(['--module', 'a', '--module', 'b', ':sweep'])['module'], [
      'a',
      'b',
    ]);
  });

  test('BB-MULTI-3: given once, the value stays a plain string', () {
    expect(_opts([':sweep', '--module', 'a'])['module'], 'a');
  });

  test('BB-MULTI-5: through an alias as well', () {
    final args = CliArgParser(
      toolDefinition: _tool,
    ).parse([':sw', '--module', 'a', '--module', 'b']);
    expect(args.optionsFor('sweep', aliases: ['sw'])['module'], ['a', 'b']);
  });

  test('BB-MULTI-4: a single-value option still takes the last value', () {
    expect(_opts([':sweep', '--seed', '1', '--seed', '2'])['seed'], '2');
  });
}
