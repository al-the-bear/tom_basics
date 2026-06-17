// Wiring behaviour to the definition and running it across a workspace.
//
// The definition says *what* the tool is; a CommandExecutor says what to *do*
// with each folder. A single-command tool registers its executor under the key
// 'default'. Here projreport's executor reads the DartProjectFolder nature off
// each CommandContext and prints one line per project. We point a ToolRunner at
// a throwaway fixture workspace (built in a temp directory) and capture its
// output so the run is hermetic and deterministic.
//
// Run with: dart run example/02_running_the_tool_example.dart
import 'package:tom_build_base_introduction_sample/projreport.dart';

import 'fixture.dart';

Future<void> main() async {
  final workspace = await createFixtureWorkspace();
  try {
    final out = StringBuffer();
    final runner = projreportRunner(output: out);

    // -R sets the workspace root, --scan the directory to walk, -r recurses
    // into it. These flags exist for free because the tool opted into the
    // project navigation features.
    await runner.run([
      '-R', workspace.path,
      '--scan', workspace.path,
      '-r',
    ]);

    print(out.toString().trimRight());
  } finally {
    await disposeFixture(workspace);
  }

  // expected output:
  // data_layer v1.0.0 — 0 dependencies
  // service_layer v1.2.0 — 1 dependencies
  // app_runner v0.9.0 — 1 dependencies
}
