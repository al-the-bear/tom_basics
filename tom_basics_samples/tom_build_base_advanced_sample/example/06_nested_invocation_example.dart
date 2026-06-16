// Nested invocation: run one command against a single project, no traversal.
//
// `--nested` is how a tool runs *inside* another tool's traversal: the host has
// already walked to a project directory, so the nested tool skips traversal and
// runs one command against the current working directory. There is no
// per-folder tree here — nested mode hands you back a ToolResult and lets you
// render it yourself. Because the host attaches no detected natures in this
// mode, `relkit`'s executor falls back to reading the pubspec from disk (see
// `packageFactsFor`), which is exactly what makes one tool work both standalone
// and nested.
//
// Run with: dart run example/06_nested_invocation_example.dart
import 'dart:io';

import 'package:tom_build_base_advanced_sample/relkit.dart';

import 'fixture.dart';

Future<void> main() async {
  final workspace = await createFixtureWorkspace();
  final saved = Directory.current;
  try {
    // Step into one project directory, as a host tool would before delegating.
    Directory.current = Directory('${workspace.path}/service');

    final out = StringBuffer();
    final result = await relkitRunner(output: out).run(['--nested', ':report']);

    // No traversal tree is printed; the result is yours to render.
    print('processed: ${result.processedCount}');
    for (final item in result.itemResults) {
      print('report line: ${item.message}');
    }
    print('success: ${result.success}');
  } finally {
    Directory.current = saved;
    await disposeFixture(workspace);
  }

  // expected output:
  // processed: 1
  // report line: service_layer v1.2.0 — 1 deps
  // success: true
}
