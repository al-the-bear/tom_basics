// Smoke test for the tom_basics_console_sample examples.
//
// Imports each one-concept example's main() and runs them in order (awaiting the
// async ones), catching any throw, tallying pass/fail, and exiting non-zero if
// any example fails.
//
// Run with: dart run example/run_all_examples.dart
import 'dart:async';
import 'dart:io';

import '01_platform_detection_example.dart' as platform_detection;
import '02_wiring_the_seam_example.dart' as wiring_the_seam;
import '03_console_output_example.dart' as console_output;
import '04_environment_and_isolate_example.dart' as environment_and_isolate;
import '05_http_client_example.dart' as http_client;
import '06_styled_logging_example.dart' as styled_logging;

/// Each example by name, in learning order. Values may be sync or async; both
/// are awaited uniformly.
final examples = <String, FutureOr<void> Function()>{
  '01_platform_detection': platform_detection.main,
  '02_wiring_the_seam': wiring_the_seam.main,
  '03_console_output': console_output.main,
  '04_environment_and_isolate': environment_and_isolate.main,
  '05_http_client': http_client.main,
  '06_styled_logging': styled_logging.main,
};

Future<void> main() async {
  print('=' * 60);
  print('Running all tom_basics_console_sample examples');
  print('=' * 60);

  var passed = 0;
  var failed = 0;
  final failures = <String, Object>{};

  for (final entry in examples.entries) {
    print('\n--- ${entry.key} ---');
    try {
      await entry.value();
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
