import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// An option that takes one value, given twice, is refused: the parser kept
/// the last value without a word, so `-s a -s b` scanned `b` only and the run
/// looked complete. Several scan roots are written once, comma-separated
/// (`--scan a,b`); the traversal visits each, a project once. Options that
/// take several values (`--project`, `--exclude`, a declared multi option)
/// and flags may be repeated as before.
///
/// Test IDs: BB-REP-1..8.

const _tool = ToolDefinition(
  name: 'reptool',
  description: 'Tool for the repeated-option tests',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.all,
  globalOptions: [
    OptionDefinition.option(name: 'level', description: 'One value'),
  ],
  commands: [
    CommandDefinition(
      name: 'write',
      description: 'Visits projects',
      requiresTraversal: true,
      supportsProjectTraversal: true,
      worksWithNatures: {DartProjectFolder},
      options: [
        OptionDefinition.option(name: 'out', description: 'One value'),
        OptionDefinition.multi(name: 'tag', description: 'Several values'),
      ],
    ),
    CommandDefinition(
      name: 'check',
      description: 'Visits projects too',
      requiresTraversal: true,
      supportsProjectTraversal: true,
      worksWithNatures: {DartProjectFolder},
      options: [OptionDefinition.option(name: 'out', description: 'One value')],
    ),
  ],
);

class _Recorder extends CommandExecutor {
  final visited = <String>[];

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    visited.add(context.name);
    return ItemResult.success(path: context.path, name: context.name);
  }
}

void main() {
  CliArgs parse(List<String> args) =>
      CliArgParser(toolDefinition: _tool).parse(args);

  group('a single-value option given twice', () {
    test('BB-REP-1: `-s a -s b` is refused, naming --scan, both values and '
        'the comma form [2026-11-14]', () {
      for (final args in [
        ['-s', 'a', '-s', 'b', ':write'],
        ['--scan', 'a', ':write', '--scan=b'],
        ['-sa', '-sb', ':write'],
      ]) {
        final errors = parse(args).argumentErrors;
        expect(errors, hasLength(1), reason: '$args');
        expect(errors.single, contains('`--scan` given twice'));
        expect(errors.single, contains('`a`'));
        expect(errors.single, contains('`b`'));
        expect(errors.single, contains('--scan a,b'));
      }
    });

    test('BB-REP-2: every other single-value option given twice is refused, '
        'also with the same value [2026-11-14]', () {
      for (final (args, option) in [
        (['-R', 'x', '--root', 'y', ':write'], '--root'),
        (['--config', 'a.yaml', '--config', 'b.yaml', ':write'], '--config'),
        (['--level', '1', '--level', '1', ':write'], '--level'),
        ([':write', '--out', 'a', '--out', 'b'], '--out'),
        (['--jobs', '2', ':write', '--jobs', '3'], '--jobs'),
      ]) {
        final errors = parse(args).argumentErrors;
        expect(errors, [contains('`$option` given twice')], reason: '$args');
        expect(errors.single, contains('give it once'));
      }
    });

    test('BB-REP-3: options that take several values, flags and one value '
        'per command stay as they were [2026-11-14]', () {
      final args = parse([
        '-p', 'a', '-p', 'b', '-x', 'c', '-x', 'd', '-v', '-v', //
        ':write', '--tag', 't1', '--tag', 't2', '--out', 'o1',
        ':check', '--out', 'o2',
      ]);
      expect(args.argumentErrors, isEmpty);
      expect(args.projectPatterns, ['a', 'b']);
      expect(args.excludePatterns, ['c', 'd']);
      expect(args.commandArgs['write']!.options['tag'], ['t1', 't2']);
      expect(args.commandArgs['write']!.options['out'], 'o1');
      expect(args.commandArgs['check']!.options['out'], 'o2');
    });

    test('BB-REP-4: several scan roots written once, comma-separated, are no '
        'repeat [2026-11-14]', () {
      final args = parse(['-s', 'a,b', ':write']);
      expect(args.argumentErrors, isEmpty);
      final info = args.toProjectTraversalInfo(executionRoot: '/ws');
      expect(info.scanRoots, ['a', 'b']);
      expect(
        parse([
          ':write',
        ]).toProjectTraversalInfo(executionRoot: '/ws').scanRoots,
        ['.'],
      );
    });
  });

  group('the run', () {
    late Directory root;
    late StringBuffer out;

    setUp(() {
      root = Directory(
        Directory.systemTemp
            .createTempSync('bb_rep_')
            .resolveSymbolicLinksSync(),
      );
      File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
      for (final rel in ['one/alpha', 'one/beta', 'two/gamma', 'three/delta']) {
        File(p.join(root.path, rel, 'pubspec.yaml'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('name: ${p.basename(rel)}\n');
      }
      out = StringBuffer();
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<(ToolResult, _Recorder)> run(List<String> args) async {
      final recorder = _Recorder();
      final result = await ToolRunner(
        tool: _tool,
        output: out,
        executors: {'write': recorder, 'check': _Recorder()},
      ).run(['-R', root.path, ...args]);
      return (result, recorder);
    }

    test('BB-REP-5: a repeated option stops the run before any project '
        '[2026-11-14]', () async {
      final (result, recorder) = await run([
        '-s', p.join(root.path, 'one'), //
        '-s', p.join(root.path, 'two'), ':write',
      ]);
      expect(result.success, isFalse);
      expect(recorder.visited, isEmpty);
      expect(out.toString(), contains('`--scan` given twice'));
    });

    test('BB-REP-6: `--scan a,b` visits the projects of both roots '
        '[2026-11-14]', () async {
      final (result, recorder) = await run([
        '-r',
        '-s',
        '${p.join(root.path, 'one')},${p.join(root.path, 'two')}',
        ':write',
      ]);
      expect(result.success, isTrue, reason: out.toString());
      expect(recorder.visited.toSet(), {'alpha', 'beta', 'gamma'});
    });

    test(
      'BB-REP-7: overlapping roots visit a project once [2026-11-14]',
      () async {
        final (result, recorder) = await run([
          '-r',
          '-s',
          '${root.path},${p.join(root.path, 'one')}',
          ':write',
        ]);
        expect(result.success, isTrue, reason: out.toString());
        expect(recorder.visited..sort(), ['alpha', 'beta', 'delta', 'gamma']);
      },
    );

    test(
      'BB-REP-8: every root must lie in the workspace [2026-11-14]',
      () async {
        final outside = Directory.systemTemp.createTempSync('bb_rep_out_');
        addTearDown(() => outside.deleteSync(recursive: true));
        final (result, recorder) = await run([
          '-s',
          '${p.join(root.path, 'one')},${outside.path}',
          ':write',
        ]);
        expect(result.success, isFalse);
        expect(recorder.visited, isEmpty);
        expect(out.toString(), contains('outside the workspace'));
      },
    );
  });
}
