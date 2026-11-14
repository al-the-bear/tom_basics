/// Unit tests for the shared end-of-run summary block.
///
/// [ToolResult.renderRunSummary] gives every `tom_build_base`-based tool a
/// single, consistent errors/skips summary so outcomes are easy to read after
/// a long run (cli_tools todo #16, tool_run_analysis §b.5/§b.7/§d). The tests
/// drive the pure renderer directly, so they run on any host without a
/// provisioned workspace.
///
/// Test IDs: SUMM01–SUMM20
@TestOn('!browser')
@Timeout(Duration(seconds: 30))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

ItemResult _ok(String name, {String? cmd, String? message}) =>
    ItemResult(path: name, name: name, commandName: cmd, message: message);

ItemResult _skip(String name, {String? cmd, String? message}) =>
    ItemResult.skipped(
      path: name,
      name: name,
      commandName: cmd,
      message: message,
    );

ItemResult _fail(String name, {String? cmd, required String error}) =>
    ItemResult.failure(path: name, name: name, commandName: cmd, error: error);

void main() {
  group('ItemResult.skipped', () {
    test('SUMM01: a skipped item is a non-failing success', () {
      final item = _skip('proj', message: 'skipped as configured');
      expect(item.success, isTrue);
      expect(item.skipped, isTrue);
      expect(item.error, isNull);
    });

    test('SUMM02: a plain success is not marked skipped', () {
      expect(_ok('proj').skipped, isFalse);
    });

    test('SUMM03: a failure is not marked skipped', () {
      expect(_fail('proj', error: 'boom').skipped, isFalse);
    });

    test('SUMM04: skipped items do not count as failures in fromItems', () {
      final result = ToolResult.fromItems([
        _ok('a'),
        _skip('b', message: 'skipped'),
      ]);
      expect(result.success, isTrue);
      expect(result.failedCount, 0);
      expect(result.processedCount, 2);
    });
  });

  group('ToolResult.renderRunSummary', () {
    test('SUMM05: empty item list renders nothing', () {
      expect(ToolResult.fromItems(const []).renderRunSummary(), isEmpty);
    });

    test('SUMM06: all-success renders the clean footer', () {
      final summary = ToolResult.fromItems([
        _ok('a'),
        _ok('b'),
      ]).renderRunSummary();
      expect(summary, 'Done. No errors.');
    });

    test(
      'SUMM07: a failure renders an Errors section, not the clean footer',
      () {
        final summary = ToolResult.fromItems([
          _ok('a'),
          _fail('b', cmd: 'compiler', error: 'Compilation failed'),
        ]).renderRunSummary();
        expect(summary, contains('=== Errors ==='));
        expect(summary, contains('b :compiler — Compilation failed'));
        expect(summary, contains('1 error(s) in 1 project(s).'));
        expect(summary, isNot(contains('Done. No errors.')));
      },
    );

    test('SUMM08: the error tally counts distinct projects', () {
      final summary = ToolResult.fromItems([
        _fail('b', cmd: 'compiler', error: 'e1'),
        _fail('b', cmd: 'reflect', error: 'e2'),
        _fail('c', cmd: 'compiler', error: 'e3'),
      ]).renderRunSummary();
      // 3 failures across 2 distinct projects (b, c).
      expect(summary, contains('3 error(s) in 2 project(s).'));
    });

    test('SUMM09: a skip renders a Skipped section above the footer', () {
      final summary = ToolResult.fromItems([
        _ok('a'),
        _skip('b', cmd: 'compiler', message: 'compile skipped as configured'),
      ]).renderRunSummary();
      expect(summary, contains('=== Skipped ==='));
      expect(summary, contains('b :compiler — compile skipped as configured'));
      expect(summary, contains('1 project(s) skipped.'));
      // No failures -> clean footer still present.
      expect(summary, contains('Done. No errors.'));
      // Skipped section comes before the footer.
      expect(
        summary.indexOf('=== Skipped ==='),
        lessThan(summary.indexOf('Done. No errors.')),
      );
    });

    test('SUMM10: skips and errors render both sections, skips first', () {
      final summary = ToolResult.fromItems([
        _skip('a', cmd: 'compiler', message: 'skipped'),
        _fail('b', cmd: 'compiler', error: 'boom'),
      ]).renderRunSummary();
      expect(summary, contains('=== Skipped ==='));
      expect(summary, contains('=== Errors ==='));
      expect(
        summary.indexOf('=== Skipped ==='),
        lessThan(summary.indexOf('=== Errors ===')),
      );
      // Errors present -> no clean footer.
      expect(summary, isNot(contains('Done. No errors.')));
    });

    test('SUMM11: a skip with no message falls back to a default label', () {
      final summary = ToolResult.fromItems([
        _skip('b', cmd: 'compiler'),
      ]).renderRunSummary();
      expect(summary, contains('b :compiler — skipped'));
    });

    test('SUMM12: an item without a command name omits the colon segment', () {
      final summary = ToolResult.fromItems([
        _fail('b', error: 'boom'),
      ]).renderRunSummary();
      expect(summary, contains('  b — boom'));
      expect(summary, isNot(contains('b :')));
    });

    test('SUMM13: the rendered block has no leading or trailing newline', () {
      final summary = ToolResult.fromItems([
        _skip('a', message: 'skipped'),
        _fail('b', error: 'boom'),
      ]).renderRunSummary();
      expect(summary, isNotEmpty);
      expect(summary.startsWith('\n'), isFalse);
      expect(summary.endsWith('\n'), isFalse);
    });
  });

  group('timing', () {
    ItemResult timed(String name, String cmd, int ms) => ItemResult(
      path: name,
      name: name,
      commandName: cmd,
      duration: Duration(milliseconds: ms),
    );

    test('SUMM14: the time per step, its projects and its slowest '
        'projects, then the total with startup and traversal [2026-11-14]', () {
      final text = ToolResult.fromItems([
        timed('a', 'pubget', 1200),
        timed('b', 'pubget', 3400),
        timed('c', 'pubget', 500),
        timed('d', 'pubget', 2100),
        timed('a', 'versioner', 300),
      ]).renderRunSummary(elapsed: const Duration(milliseconds: 9000));
      final lines = text.split('\n');
      expect(lines, contains('=== Timing ==='));
      expect(
        lines,
        contains(
          '  :pubget  4 project(s)  7.2s  (slowest: b 3.4s, d 2.1s, a 1.2s)',
        ),
      );
      expect(lines, contains('  :versioner  1 project(s)  0.3s'));
      expect(
        lines,
        contains('  Total 9.0s, of which startup and traversal 1.5s'),
      );
      expect(lines.last, 'Done. No errors.');
      expect(
        text.indexOf('=== Timing ==='),
        lessThan(text.indexOf('Done. No errors.')),
      );
    });

    test('SUMM15: items without a duration and no elapsed time render no '
        'timing; minutes are written as minutes [2026-11-14]', () {
      expect(
        ToolResult.fromItems([_ok('a', cmd: 'x')]).renderRunSummary(),
        isNot(contains('Timing')),
      );
      final text = ToolResult.fromItems([
        timed('a', 'compiler', 125400),
      ]).renderRunSummary(elapsed: const Duration(milliseconds: 126000));
      expect(text, contains('  :compiler  1 project(s)  2m 05.4s'));
      expect(
        text,
        contains('  Total 2m 06.0s, of which startup and traversal 0.6s'),
      );
    });

    test('SUMM20: a pipeline names a multi-line command by its first line, '
        'and a dry run prints no timing [2026-11-14]', () async {
      final root = Directory.systemTemp.createTempSync('summ_pipeline_ml_');
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync(
        'buildkit:\n'
        '  pipelines:\n'
        '    piped:\n'
        '      executable: true\n'
        '      core:\n'
        '        - commands:\n'
        '            - |\n'
        '              stdin cat\n'
        '              Hello piped world\n',
      );
      final previous = Directory.current;
      Directory.current = root;
      addTearDown(() => Directory.current = previous);
      Future<String> run(List<String> args) async {
        final out = StringBuffer();
        await ToolRunner(
          tool: const ToolDefinition(
            name: 'buildkit',
            description: 'Pipelines',
            version: '1.0.0',
            mode: ToolMode.multiCommand,
            features: NavigationFeatures.all,
          ),
          output: out,
          executors: const {},
        ).run(['-R', root.path, ...args]);
        return out.toString();
      }

      final text = await run(['piped']);
      final timing = text.substring(text.indexOf('=== Pipeline piped: timing'));
      expect(timing, contains(RegExp(r'  stdin cat …  \d+\.\ds')));
      expect(timing, isNot(contains('Hello piped world')));

      final dry = await run(['--dry-run', 'piped']);
      expect(dry, isNot(contains('timing ===')));
    });

    test('SUMM18: projects that ran at once (more project time than the '
        'run took) are named as such, not as negative startup '
        '[2026-11-14]', () {
      final text = ToolResult.fromItems([
        timed('a', 'pubget', 6000),
        timed('b', 'pubget', 6000),
        timed('c', 'pubget', 6000),
      ]).renderRunSummary(elapsed: const Duration(milliseconds: 7000));
      expect(
        text,
        contains(
          '  Total 7.0s; the projects ran at once (18.0s of project time)',
        ),
      );
      expect(text, isNot(contains('startup and traversal')));
    });

    test('SUMM19: no slowest list when every project took next to no time '
        '[2026-11-14]', () {
      final text = ToolResult.fromItems([
        timed('a', 'pubget', 0),
        timed('b', 'pubget', 10),
      ]).renderRunSummary(elapsed: const Duration(milliseconds: 900));
      expect(text, contains('  :pubget  2 project(s)  0.0s\n'));
      expect(text, isNot(contains('slowest')));
    });

    test('SUMM16: ToolRunner times each project and the run, and its summary '
        'shows them [2026-11-14]', () async {
      final root = Directory.systemTemp.createTempSync('summ_timing_');
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
      for (final name in ['alpha', 'beta']) {
        File(p.join(root.path, name, 'pubspec.yaml'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('name: $name\n');
      }
      final out = StringBuffer();
      final result = await ToolRunner(
        tool: const ToolDefinition(
          name: 'timer',
          description: 'Times its projects',
          version: '1.0.0',
          mode: ToolMode.multiCommand,
          features: NavigationFeatures.all,
          commands: [
            CommandDefinition(
              name: 'nap',
              description: 'Sleeps per project',
              requiresTraversal: true,
              supportsProjectTraversal: true,
              worksWithNatures: {DartProjectFolder},
            ),
          ],
        ),
        output: out,
        executors: {'nap': _Napper()},
      ).runToCompletion(['-R', root.path, '-s', root.path, '-r', ':nap']);
      expect(result.itemResults, hasLength(2));
      for (final item in result.itemResults) {
        expect(
          item.duration,
          greaterThanOrEqualTo(const Duration(milliseconds: 50)),
        );
        expect(item.commandName, 'nap');
      }
      expect(out.toString(), contains('=== Timing ==='));
      expect(out.toString(), contains('  :nap  2 project(s)  '));
      expect(out.toString(), contains('  Total '));
    });

    test('SUMM17: a pipeline prints the time of each of its steps and its '
        'total [2026-11-14]', () async {
      final root = Directory.systemTemp.createTempSync('summ_pipeline_');
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync(
        'buildkit:\n'
        '  pipelines:\n'
        '    twice:\n'
        '      executable: true\n'
        '      core:\n'
        '        - commands:\n'
        '            - shell echo one\n'
        '            - print two\n',
      );
      // Pipelines are loaded from the working directory's master file.
      final previous = Directory.current;
      Directory.current = root;
      addTearDown(() => Directory.current = previous);
      final out = StringBuffer();
      final result = await ToolRunner(
        tool: const ToolDefinition(
          name: 'buildkit',
          description: 'Pipelines',
          version: '1.0.0',
          mode: ToolMode.multiCommand,
          features: NavigationFeatures.all,
        ),
        output: out,
        executors: const {},
      ).run(['-R', root.path, 'twice']);
      expect(result.success, isTrue, reason: out.toString());
      final text = out.toString();
      expect(text, contains('=== Pipeline twice: timing ==='));
      expect(text, contains(RegExp(r'  shell echo one  \d+\.\ds')));
      expect(text, contains(RegExp(r'  print two  \d+\.\ds')));
      expect(text, contains(RegExp(r'  Total \d+\.\ds')));
    });
  });
}

class _Napper extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return ItemResult.success(path: context.path, name: context.name);
  }
}
