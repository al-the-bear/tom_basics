#!/usr/bin/env dart

library;

import 'dart:io';

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

  final result = await runner.run(args);

  // Shared, consistent end-of-run errors/skips summary (tom_build_base).
  // Empty for special/single-shot commands that traverse nothing.
  final summary = result.renderRunSummary();
  if (summary.isNotEmpty) {
    stdout.writeln('\n$summary');
  }

  // Set the exit code and return rather than hard-exiting. A bare `exit(1)`
  // can drop buffered stdout (the run summary just written above) and diverges
  // from testkit/issuekit, which set `exitCode`. Aligning here gives all three
  // tools identical, flush-safe failure semantics.
  // See tom_build_base doc/cli_error_handling.md.
  if (!result.success) {
    exitCode = 1;
  }
}
