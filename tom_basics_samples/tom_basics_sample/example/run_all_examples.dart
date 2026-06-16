// Smoke test for the tom_basics_sample examples.
//
// Imports each one-concept example's main() and runs them in order, catching
// any throw, tallying pass/fail, and exiting non-zero if any example fails.
//
// Run with: dart run example/run_all_examples.dart
import 'dart:io';

import '01_throw_and_catch_example.dart' as throw_and_catch;
import '02_request_correlation_example.dart' as request_correlation;
import '03_parameters_example.dart' as parameters;
import '04_wrapping_root_exception_example.dart' as wrapping_root_exception;
import '05_logging_with_levels_example.dart' as logging_with_levels;
import '06_bitwise_levels_example.dart' as bitwise_levels;
import '07_loggable_example.dart' as loggable;

/// Each example by name, in learning order.
final examples = <String, void Function()>{
  '01_throw_and_catch': throw_and_catch.main,
  '02_request_correlation': request_correlation.main,
  '03_parameters': parameters.main,
  '04_wrapping_root_exception': wrapping_root_exception.main,
  '05_logging_with_levels': logging_with_levels.main,
  '06_bitwise_levels': bitwise_levels.main,
  '07_loggable': loggable.main,
};

void main() {
  print('=' * 60);
  print('Running all tom_basics_sample examples');
  print('=' * 60);

  var passed = 0;
  var failed = 0;
  final failures = <String, Object>{};

  for (final entry in examples.entries) {
    print('\n--- ${entry.key} ---');
    try {
      entry.value();
      passed++;
    } catch (e, st) {
      failed++;
      failures[entry.key] = e;
      print('FAILED: $e\n$st');
    }
  }

  print('\n${'=' * 60}');
  print('Results: $passed passed, $failed failed '
      '(of ${examples.length} examples)');
  print('=' * 60);

  if (failures.isNotEmpty) {
    print('\nFailures:');
    for (final entry in failures.entries) {
      print('  ${entry.key}: ${entry.value}');
    }
    exit(1);
  }
}
