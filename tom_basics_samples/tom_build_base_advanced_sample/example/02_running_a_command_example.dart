// Running one command — and the per-folder tree a multi-command tool renders.
//
// `relkit :report` selects the report command and runs it across the fixture
// tree. Note the output shape: a multi-command tool prints a *tree* — one
// `>>> <folder>` header per project, then one `  -> :<command> <message>` line
// per command. Those lines come from the framework, built from the ItemResult
// each executor returns; the executor itself prints nothing. (This is the
// structural difference from a single-command tool, whose executor does its own
// printing.) The order is dependency/build order: leaves first, so app_runner —
// which depends on the others — lands last.
//
// Run with: dart run example/02_running_a_command_example.dart
import 'package:tom_build_base_advanced_sample/relkit.dart';

import 'fixture.dart';

Future<void> main() async {
  final workspace = await createFixtureWorkspace();
  try {
    final out = StringBuffer();
    await relkitRunner(output: out).run([
      ':report',
      '-R', workspace.path,
      '--scan', workspace.path,
      '-r',
    ]);
    print(out.toString().trimRight());
  } finally {
    await disposeFixture(workspace);
  }

  // expected output:
  // >>> app/tool
  //   -> :report app_tools v0.1.0 — 0 deps
  // >>> data
  //   -> :report data_layer v1.0.0 — 0 deps
  // >>> draft
  //   -> :report draft_pkg (no version) — 0 deps
  // >>> service
  //   -> :report service_layer v1.2.0 — 1 deps
  // >>> app
  //   -> :report app_runner v0.9.0 — 1 deps
}
