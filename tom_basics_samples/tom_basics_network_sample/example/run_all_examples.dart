// Smoke test for the tom_basics_network_sample examples.
//
// Imports each one-concept example's main() and runs them in order (awaiting the
// async ones), catching any throw, tallying pass/fail, and exiting non-zero if
// any example fails. Every example stands up its own in-process server, so the
// whole run works offline.
//
// Run with: dart run example/run_all_examples.dart
import 'dart:async';
import 'dart:io';

import '01_retry_with_backoff_example.dart' as retry_with_backoff;
import '02_retry_exhausted_example.dart' as retry_exhausted;
import '03_controlling_what_retries_example.dart' as controlling_what_retries;
import '04_retryable_status_codes_example.dart' as retryable_status_codes;
import '05_default_backoff_schedule_example.dart' as default_backoff_schedule;
import '06_server_discovery_example.dart' as server_discovery;
import '07_subnet_addresses_example.dart' as subnet_addresses;

/// Each example by name, in learning order. Values may be sync or async; both
/// are awaited uniformly.
final examples = <String, FutureOr<void> Function()>{
  '01_retry_with_backoff': retry_with_backoff.main,
  '02_retry_exhausted': retry_exhausted.main,
  '03_controlling_what_retries': controlling_what_retries.main,
  '04_retryable_status_codes': retryable_status_codes.main,
  '05_default_backoff_schedule': default_backoff_schedule.main,
  '06_server_discovery': server_discovery.main,
  '07_subnet_addresses': subnet_addresses.main,
};

Future<void> main() async {
  print('=' * 60);
  print('Running all tom_basics_network_sample examples');
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
