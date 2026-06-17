// Nested invocation: report one project, no traversal.
//
// `--nested` is how a tool runs *inside* another tool's traversal: the host has
// already walked to a project directory, so the nested tool skips its own walk
// and reports the current working directory once. A single-command tool makes
// this work by supplying an `onExecuteWithoutTraversal` callback — sumkit builds
// a one-off context for the cwd and runs the same scan it would in a traversal,
// so a nested report is identical to a standalone one.
//
// There is no per-folder output here; you get a ToolResult back to render
// yourself. (Note the cache root in nested mode is the cwd, so the `meta`
// summary written below lands under `data/.tom/`, which the fixture cleanup
// removes with everything else.)
//
// Run with: dart run example/06_nested_invocation_example.dart
import 'dart:io';

import 'package:tom_build_base_advanced_analyzer_sample/sumkit.dart';

import 'fixture.dart';

Future<void> main() async {
  final workspace = await createFixtureWorkspace();
  final saved = Directory.current;
  try {
    // Step into one project directory, as a host tool would before delegating.
    Directory.current = Directory('${workspace.path}/data');

    final out = StringBuffer();
    final result = await sumkitRunner(output: out).run(['--nested']);

    print('report line: ${out.toString().trim()}');
    print('processed:   ${result.processedCount}');
    print('success:     ${result.success}');
  } finally {
    Directory.current = saved;
    await disposeFixture(workspace);
  }

  // expected output:
  // report line: data: 1 cacheable, 0 cached, 1 missing (0 uncacheable)
  // processed:   1
  // success:     true
}
