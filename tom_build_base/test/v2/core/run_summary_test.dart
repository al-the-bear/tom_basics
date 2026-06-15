/// Unit tests for the shared end-of-run summary block.
///
/// [ToolResult.renderRunSummary] gives every `tom_build_base`-based tool a
/// single, consistent errors/skips summary so outcomes are easy to read after
/// a long run (cli_tools todo #16, tool_run_analysis §b.5/§b.7/§d). The tests
/// drive the pure renderer directly, so they run on any host without a
/// provisioned workspace.
///
/// Test IDs: SUMM01–SUMM13
@TestOn('!browser')
@Timeout(Duration(seconds: 30))
library;

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

ItemResult _ok(String name, {String? cmd, String? message}) => ItemResult(
  path: name,
  name: name,
  commandName: cmd,
  message: message,
);

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
      final summary = ToolResult.fromItems([_ok('a'), _ok('b')])
          .renderRunSummary();
      expect(summary, 'Done. No errors.');
    });

    test('SUMM07: a failure renders an Errors section, not the clean footer',
        () {
      final summary = ToolResult.fromItems([
        _ok('a'),
        _fail('b', cmd: 'compiler', error: 'Compilation failed'),
      ]).renderRunSummary();
      expect(summary, contains('=== Errors ==='));
      expect(summary, contains('b :compiler — Compilation failed'));
      expect(summary, contains('1 error(s) in 1 project(s).'));
      expect(summary, isNot(contains('Done. No errors.')));
    });

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
      expect(
        summary,
        contains('b :compiler — compile skipped as configured'),
      );
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
      final summary = ToolResult.fromItems([_skip('b', cmd: 'compiler')])
          .renderRunSummary();
      expect(summary, contains('b :compiler — skipped'));
    });

    test('SUMM12: an item without a command name omits the colon segment', () {
      final summary =
          ToolResult.fromItems([_fail('b', error: 'boom')]).renderRunSummary();
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
}
