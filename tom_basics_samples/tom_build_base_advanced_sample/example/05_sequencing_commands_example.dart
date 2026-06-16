// Sequencing: several commands, one traversal, folder by folder.
//
// `relkit :audit :report` runs *both* commands in a single walk of the tree:
// for each project the framework executes the commands in the order given.
// Two things to notice. First, the workspace is traversed once, not once per
// command — `:audit` and `:report` both run under the same `>>> folder`
// header. Second, if a command fails for a folder, the remaining commands for
// *that* folder are skipped: `draft` fails `:audit`, so its `:report` line
// never appears — while every other project still gets both. The run's success
// reflects the audit failure.
//
// Run with: dart run example/05_sequencing_commands_example.dart
import 'package:tom_build_base_advanced_sample/relkit.dart';

import 'fixture.dart';

Future<void> main() async {
  final workspace = await createFixtureWorkspace();
  try {
    final out = StringBuffer();
    final result = await relkitRunner(output: out).run([
      ':audit', ':report',
      '-R', workspace.path,
      '--scan', workspace.path,
      '-r',
    ]);
    print(out.toString().trimRight());
    print('--- summary ---');
    print(result.renderRunSummary().trimRight());
    print('processed ${result.processedCount}, exit ${result.success ? 0 : 1}');
  } finally {
    await disposeFixture(workspace);
  }

  // expected output:
  // >>> app/tool
  //   -> :audit release-ready
  //   -> :report app_tools v0.1.0 — 0 deps
  // >>> data
  //   -> :audit release-ready
  //   -> :report data_layer v1.0.0 — 0 deps
  // >>> draft
  //   -> :audit ERROR: no version, no description
  // >>> service
  //   -> :audit release-ready
  //   -> :report service_layer v1.2.0 — 1 deps
  // >>> app
  //   -> :audit release-ready
  //   -> :report app_runner v0.9.0 — 1 deps
  // --- summary ---
  // === Errors ===
  //   draft_pkg :audit — no version, no description
  // 1 error(s) in 1 project(s).
  // processed 9, exit 1
}
