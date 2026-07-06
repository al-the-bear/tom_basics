#!/usr/bin/env dart

library;

import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/tom_build_kit.dart';

Future<void> main(List<String> args) async {
  // Run inside the shared console_markdown zone (tom_build_base) so
  // help/version/output render consistently with testkit and issuekit.
  await runWithConsoleMarkdown(() => _runCli(args));
}

/// Run the buildkit CLI flow through the v2 [ToolRunner].
Future<void> _runCli(List<String> args) async {
  final runner = ToolRunner(
    tool: buildkitTool,
    executors: createBuildkitExecutors(),
    verbose: true,
  );

  // Run to completion — the shared run → summary → exit-code tail lives in
  // ToolRunner.runToCompletion (tom_build_base) so buildkit/testkit/issuekit
  // share identical, flush-safe failure semantics (it sets exitCode and never
  // calls exit(), so buffered output — including the summary — is drained
  // first). See tom_build_base doc/cli_error_handling.md.
  await runner.runToCompletion(args);
}
