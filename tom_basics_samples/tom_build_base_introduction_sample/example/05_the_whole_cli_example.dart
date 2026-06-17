// The whole CLI in one pass — exactly what bin/projreport.dart does.
//
// This ties the previous four concepts together: a single ToolDefinition,
// run by a ToolRunner against a real directory tree, producing per-project
// lines, a consolidated summary, and a success flag that becomes an exit code.
// The only difference from the production entrypoint is that we point it at a
// throwaway fixture and capture its output into a buffer so the run is
// deterministic. Swap the captured sink for stdout and the temp path for a real
// workspace and this *is* bin/projreport.dart.
//
// Run with: dart run example/05_the_whole_cli_example.dart
import 'package:tom_build_base_introduction_sample/projreport.dart';

import 'fixture.dart';

Future<void> main() async {
  final workspace = await createFixtureWorkspace();
  try {
    final out = StringBuffer();
    final runner = projreportRunner(output: out);

    final result = await runner.run([
      '-R', workspace.path,
      '--scan', workspace.path,
      '-r',
    ]);

    // The per-project lines the executor wrote.
    print(out.toString().trimRight());

    // The framework-rendered summary, printed by bin/projreport.dart too.
    final summary = result.renderRunSummary().trimRight();
    if (summary.isNotEmpty) {
      print(summary);
    }

    // The exit code a real main would hand back to the shell.
    print('exit ${result.success ? 0 : 1}');
  } finally {
    await disposeFixture(workspace);
  }

  // expected output:
  // data_layer v1.0.0 — 0 dependencies
  // service_layer v1.2.0 — 1 dependencies
  // app_runner v0.9.0 — 1 dependencies
  // === Skipped ===
  //   draft — no version in pubspec
  // 1 project(s) skipped.
  //
  // Done. No errors.
  // exit 0
}
