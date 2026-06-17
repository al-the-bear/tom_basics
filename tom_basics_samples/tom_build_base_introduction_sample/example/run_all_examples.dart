// Aggregator: runs every projreport example and reports a pass/fail tally.
//
// Each example exposes a `main()` that runs hermetically against its own temp
// fixture, so they compose cleanly here. We call them in declaration order,
// catch any throw, and exit non-zero if any example fails — the single command
// CI needs to verify the whole sample stays green.
//
// Run with: dart run example/run_all_examples.dart
import 'dart:async';

import '01_a_tool_is_a_value_example.dart' as ex01;
import '02_running_the_tool_example.dart' as ex02;
import '03_the_run_summary_example.dart' as ex03;
import '04_navigation_for_free_example.dart' as ex04;
import '05_the_whole_cli_example.dart' as ex05;

Future<void> main() async {
  final examples = <String, FutureOr<void> Function()>{
    '01_a_tool_is_a_value': ex01.main,
    '02_running_the_tool': ex02.main,
    '03_the_run_summary': ex03.main,
    '04_navigation_for_free': ex04.main,
    '05_the_whole_cli': ex05.main,
  };

  var passed = 0;
  var failed = 0;

  for (final entry in examples.entries) {
    print('\n=== ${entry.key} ===');
    try {
      await entry.value();
      passed++;
    } catch (e, st) {
      failed++;
      print('FAILED: $e');
      print(st);
    }
  }

  print('\n----------------------------------------');
  print('$passed passed, $failed failed');
  if (failed > 0) {
    throw StateError('$failed example(s) failed');
  }
}
