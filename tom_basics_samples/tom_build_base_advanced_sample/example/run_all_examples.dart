// Aggregator: runs every relkit example and reports a pass/fail tally.
//
// Each example runs hermetically against its own temp fixture tree, so they
// compose cleanly here. We call them in declaration order, catch any throw, and
// exit non-zero if any example fails — the single command CI needs to verify
// the whole sample stays green.
//
// Run with: dart run example/run_all_examples.dart
import 'dart:async';

import '01_a_multi_command_tool_example.dart' as ex01;
import '02_running_a_command_example.dart' as ex02;
import '03_per_command_options_example.dart' as ex03;
import '04_audit_and_exit_codes_example.dart' as ex04;
import '05_sequencing_commands_example.dart' as ex05;
import '06_nested_invocation_example.dart' as ex06;

Future<void> main() async {
  final examples = <String, FutureOr<void> Function()>{
    '01_a_multi_command_tool': ex01.main,
    '02_running_a_command': ex02.main,
    '03_per_command_options': ex03.main,
    '04_audit_and_exit_codes': ex04.main,
    '05_sequencing_commands': ex05.main,
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
