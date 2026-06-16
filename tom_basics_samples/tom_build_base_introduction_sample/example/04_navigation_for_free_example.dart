// Navigation the tool never had to write: filtering and dependency ordering.
//
// Because projreport opted into the project-navigation features, two behaviours
// come for free from the same ToolDefinition:
//
//   1. --project <glob> selects a subset of the workspace. Here we ask for just
//      service_layer and only its line comes back.
//   2. The default traversal is *build order* — every package is visited only
//      after the packages it depends on. The fixture deliberately creates its
//      packages in scrambled order (app, then service, then data), yet the run
//      emits data_layer → service_layer → app_runner. app_runner sorts first
//      alphabetically but lands last, because it depends on the other two: the
//      proof that the framework is doing a real dependency sort, not echoing
//      directory order.
//
// Run with: dart run example/04_navigation_for_free_example.dart
import 'package:tom_build_base_introduction_sample/projreport.dart';

import 'fixture.dart';

Future<void> main() async {
  final workspace = await createFixtureWorkspace();
  try {
    // 1. --project filters the workspace down to one package.
    final filtered = StringBuffer();
    await projreportRunner(output: filtered).run([
      '-R', workspace.path,
      '--scan', workspace.path,
      '-r',
      '--project', 'service_layer',
    ]);
    print('--- only service_layer ---');
    print(filtered.toString().trimRight());

    // 2. The default run visits every package in dependency (build) order.
    final ordered = StringBuffer();
    await projreportRunner(output: ordered).run([
      '-R', workspace.path,
      '--scan', workspace.path,
      '-r',
    ]);
    print('--- full workspace, build order ---');
    print(ordered.toString().trimRight());
  } finally {
    await disposeFixture(workspace);
  }

  // expected output:
  // --- only service_layer ---
  // service_layer v1.2.0 — 1 dependencies
  // --- full workspace, build order ---
  // data_layer v1.0.0 — 0 dependencies
  // service_layer v1.2.0 — 1 dependencies
  // app_runner v0.9.0 — 1 dependencies
}
