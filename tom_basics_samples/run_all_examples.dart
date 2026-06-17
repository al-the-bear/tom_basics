// Aggregator smoke test for the tom_ai/basics sample projects.
//
// Each sample under tom_basics_samples/ is a self-contained Dart package with
// its own example/run_all_examples.dart. This top-level aggregator runs each
// sample's runner as a subprocess and reports a combined pass / fail / pending
// tally, exiting non-zero only if a *scaffolded* sample fails.
//
// Run with: dart run run_all_examples.dart
//
// Samples that have not yet been scaffolded are reported as PENDING and do not
// fail the run — their links in README.md are forward references until their
// plan todos land. As each sample gains an example/run_all_examples.dart this
// aggregator picks it up automatically; no edit here is required.

import 'dart:io';

/// The planned samples, in learning-path order (see README.md). Each entry is a
/// sample package directory under tom_basics_samples/.
const sampleDirs = <String>[
  'tom_basics_sample',
  'tom_basics_console_sample',
  'tom_basics_network_sample',
  'tom_build_base_introduction_sample',
  'tom_build_base_advanced_sample',
  'tom_build_base_advanced_analyzer_sample',
  'tom_chattools_sample',
  'tom_crypto_sample',
];

Future<int> main() async {
  final root = File(Platform.script.toFilePath()).parent;

  print('=' * 60);
  print('Running all tom_ai/basics samples');
  print('=' * 60);

  var passed = 0;
  var failed = 0;
  var pending = 0;
  final failures = <String, String>{};

  for (final dir in sampleDirs) {
    final sampleDir = Directory('${root.path}/$dir');
    final runner = File('${sampleDir.path}/example/run_all_examples.dart');

    stdout.write('\n$dir... ');

    if (!runner.existsSync()) {
      print('PENDING (not yet scaffolded)');
      pending++;
      continue;
    }

    final result = await Process.run(
      'dart',
      ['run', 'example/run_all_examples.dart'],
      workingDirectory: sampleDir.path,
    );

    if (result.exitCode == 0) {
      print('✓ PASSED');
      passed++;
    } else {
      print('✗ FAILED (exit ${result.exitCode})');
      failures[dir] = '${result.stdout}\n${result.stderr}';
      failed++;
    }
  }

  print('\n${'=' * 60}');
  print('Results: $passed passed, $failed failed, $pending pending '
      '(of ${sampleDirs.length} planned samples)');
  print('=' * 60);

  if (failures.isNotEmpty) {
    print('\nFailures:');
    for (final entry in failures.entries) {
      print('\n--- ${entry.key} ---');
      print(entry.value);
    }
    exit(1);
  }

  if (pending == sampleDirs.length) {
    print('\nNo samples scaffolded yet — all ${sampleDirs.length} pending.');
  } else {
    print('\nAll scaffolded samples passed '
        '($pending still pending).');
  }
  return 0;
}
