// Scanning a workspace: the sumkit tool, cold then warm.
//
// Examples 01–04 used the libraries directly; this one runs the assembled tool.
// `sumkitRunner` walks the fixture in build order (leaves first), and its
// single-command executor writes one report line per project — straight to the
// sink, because a single-command tool prints its own body (there is no
// per-folder `>>>` tree; that is the multi-command shape). `draft` has no
// pubspec.lock, so it is skipped.
//
// Three passes tell the cold→warm story against one shared cache:
//   * cold  — every cacheable dependency is missing.
//   * --warm — fill the cache; note the `already cached` count climbing as
//     `meta`/`collection`, warmed for an earlier project, become hits for the
//     projects that follow (the shared-cache payoff).
//   * warm  — a second plain scan now reports 0 missing everywhere.
//
// Run with: dart run example/05_scanning_a_workspace_example.dart
import 'package:tom_build_base_advanced_analyzer_sample/sumkit.dart';

import 'fixture.dart';

Future<void> main() async {
  final workspace = await createFixtureWorkspace();
  try {
    Future<String> scan(List<String> extra) async {
      final out = StringBuffer();
      await sumkitRunner(output: out).run([
        '-R', workspace.path,
        '--scan', workspace.path,
        '-r',
        ...extra,
      ]);
      return out.toString().trimRight();
    }

    print('--- cold scan ---');
    print(await scan(const []));
    print('--- warm the cache ---');
    print(await scan(const ['--warm']));
    print('--- scan again (warm) ---');
    print(await scan(const []));
  } finally {
    await disposeFixture(workspace);
  }

  // expected output:
  // --- cold scan ---
  // data: 1 cacheable, 0 cached, 1 missing (0 uncacheable)
  // draft: skipped (no pubspec.lock)
  // service: 2 cacheable, 0 cached, 2 missing (1 uncacheable)
  // app: 3 cacheable, 0 cached, 3 missing (1 uncacheable)
  // --- warm the cache ---
  // data: warmed 1 (0 already cached, 0 uncacheable)
  // draft: skipped (no pubspec.lock)
  // service: warmed 1 (1 already cached, 1 uncacheable)
  // app: warmed 1 (2 already cached, 1 uncacheable)
  // --- scan again (warm) ---
  // data: 1 cacheable, 1 cached, 0 missing (0 uncacheable)
  // draft: skipped (no pubspec.lock)
  // service: 2 cacheable, 2 cached, 0 missing (1 uncacheable)
  // app: 3 cacheable, 3 cached, 0 missing (1 uncacheable)
}
