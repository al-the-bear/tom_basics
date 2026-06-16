// Aggregator: runs every sumkit example and reports a pass/fail tally.
//
// Each example runs hermetically against its own temp fixture tree, so they
// compose cleanly here. We call them in declaration order, catch any throw, and
// exit non-zero if any example fails — the single command CI needs to verify
// the whole sample stays green.
//
// Run with: dart run example/run_all_examples.dart
import 'dart:async';

import '01_the_cacheability_rule_example.dart' as ex01;
import '02_resolving_dependencies_example.dart' as ex02;
import '03_the_cache_directory_example.dart' as ex03;
import '04_the_caching_payoff_example.dart' as ex04;
import '05_scanning_a_workspace_example.dart' as ex05;
import '06_nested_invocation_example.dart' as ex06;

Future<void> main() async {
  final examples = <String, FutureOr<void> Function()>{
    '01_the_cacheability_rule': ex01.main,
    '02_resolving_dependencies': ex02.main,
    '03_the_cache_directory': ex03.main,
    '04_the_caching_payoff': ex04.main,
    '05_scanning_a_workspace': ex05.main,
    '06_nested_invocation': ex06.main,
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
