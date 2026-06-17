/// Unit tests for the per-failure compiler output cap.
///
/// These tests do NOT use TestWorkspace — they exercise the pure static
/// [CompilerExecutor.capOutput] helper directly, so they run on every host
/// regardless of OS or workspace cleanliness.
///
/// A failing AOT compile (e.g. the umbrella `tom` binary, ≈ 1250 error lines)
/// must not drown the log: each per-failure dump is capped to the first
/// [CompilerExecutor.maxFailureOutputLines] lines plus a truncation marker.
/// See tool_run_analysis §b.5 ("`tom` failure is enormous and unactionable").
///
/// Test IDs: CMP_CAP01–CMP_CAP08
@TestOn('!browser')
@Timeout(Duration(seconds: 30))
library;

import 'package:test/test.dart';
import 'package:tom_build_kit/src/v2/executors/compiler_executor.dart';

/// Build a string of [n] numbered lines: "line 1\nline 2\n...\nline n".
String _lines(int n) =>
    List.generate(n, (i) => 'line ${i + 1}').join('\n');

void main() {
  group('CompilerExecutor.capOutput', () {
    test('CMP_CAP01: returns short output unchanged', () {
      const text = 'line 1\nline 2\nline 3';
      expect(CompilerExecutor.capOutput(text), equals(text));
    });

    test('CMP_CAP02: returns empty output unchanged', () {
      expect(CompilerExecutor.capOutput(''), equals(''));
    });

    test('CMP_CAP03: returns output of exactly the cap unchanged', () {
      final text = _lines(CompilerExecutor.maxFailureOutputLines);
      expect(CompilerExecutor.capOutput(text), equals(text));
    });

    test('CMP_CAP04: caps output one line over the limit', () {
      final cap = CompilerExecutor.maxFailureOutputLines;
      final text = _lines(cap + 1);
      final result = CompilerExecutor.capOutput(text);

      // First `cap` content lines are preserved...
      expect(result, contains('line 1'));
      expect(result, contains('line $cap'));
      // ...the (cap + 1)-th content line is elided.
      expect(result, isNot(contains('line ${cap + 1}')));
      // ...and a truncation marker names how many lines were elided.
      expect(result, contains('truncated'));
      expect(result, contains('1 more line'));
    });

    test('CMP_CAP05: caps a 1250-line umbrella dump to the limit', () {
      final cap = CompilerExecutor.maxFailureOutputLines;
      final result = CompilerExecutor.capOutput(_lines(1250));

      // Content lines shown == cap; the marker adds at most a couple of lines.
      final contentShown = RegExp(r'^line \d+$', multiLine: true)
          .allMatches(result)
          .length;
      expect(contentShown, equals(cap));
      expect(result, contains('truncated'));
      expect(result, contains('${1250 - cap} more line'));
      expect(result, contains('1250')); // names the total
    });

    test('CMP_CAP06: a trailing newline does not count as a content line', () {
      final cap = CompilerExecutor.maxFailureOutputLines;
      // `cap` content lines plus a trailing newline => still within the cap.
      final text = '${_lines(cap)}\n';
      expect(CompilerExecutor.capOutput(text), equals(text));
    });

    test('CMP_CAP07: honours a custom maxLines argument', () {
      final result = CompilerExecutor.capOutput(_lines(20), maxLines: 5);
      expect(result, contains('line 5'));
      expect(result, isNot(contains('line 6')));
      expect(result, contains('15 more line'));
    });

    test('CMP_CAP08: capped output ends with a newline for clean framing', () {
      final result =
          CompilerExecutor.capOutput(_lines(200));
      expect(result.endsWith('\n'), isTrue);
    });
  });
}
