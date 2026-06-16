// The run summary: success, skips, and the exit code, all from one value.
//
// `runner.run(...)` returns a ToolResult — not just a stream of side effects.
// That value knows how many projects it processed, how many it skipped, and
// whether the run succeeded. The framework renders a consolidated summary block
// from it (the same block `bin/projreport.dart` prints), and the boolean
// `result.success` is what a real `main` turns into an exit code. The fixture's
// version-less `draft` package shows up here as a non-failing *skip*: it is
// listed in the summary but does not drag `success` to false.
//
// Run with: dart run example/03_the_run_summary_example.dart
import 'package:tom_build_base_introduction_sample/projreport.dart';

import 'fixture.dart';

Future<void> main() async {
  final workspace = await createFixtureWorkspace();
  try {
    final out = StringBuffer();
    final result = await projreportRunner(output: out).run([
      '-R', workspace.path,
      '--scan', workspace.path,
      '-r',
    ]);

    // The aggregate counters live on the result value.
    print('success:        ${result.success}');
    print('processed:      ${result.processedCount}');
    print('failed:         ${result.failedCount}');

    // The framework renders the consolidated summary from the same value.
    print('--- summary ---');
    print(result.renderRunSummary().trimRight());

    // This is exactly what bin/projreport.dart turns into its exit code.
    print('--- exit code: ${result.success ? 0 : 1} ---');
  } finally {
    await disposeFixture(workspace);
  }

  // expected output:
  // success:        true
  // processed:      4
  // failed:         0
  // --- summary ---
  // === Skipped ===
  //   draft — no version in pubspec
  // 1 project(s) skipped.
  //
  // Done. No errors.
  // --- exit code: 0 ---
}
