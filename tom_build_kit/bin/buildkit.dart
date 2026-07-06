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
  // Normalize non-standard -help / -version flags via the shared tom_build_base
  // helper (identical to what ToolRunner.run applies), so the guided pre-parse
  // below sees the same tokens the runner would.
  final normalizedArgs = ToolRunner.normalizeArgs(args);

  final runner = ToolRunner(
    tool: buildkitTool,
    executors: createBuildkitExecutors(),
    verbose: true,
  );

  // Guided-mode dispatch: when `-g` / `--guide` targets a git command that has
  // an interactive flow, walk the user through the options, resolve them into
  // the exact command-line flags the git executor already understands, then
  // re-dispatch through the normal runner. This reuses the tested per-repo git
  // executors instead of duplicating git logic in the guided layer.
  final resolvedArgs = _resolveGuidedArgs(normalizedArgs);
  if (resolvedArgs != null) {
    await runner.runToCompletion(resolvedArgs);
    return;
  }

  // Run to completion — the shared run → summary → exit-code tail lives in
  // ToolRunner.runToCompletion (tom_build_base) so buildkit/testkit/issuekit
  // share identical, flush-safe failure semantics (it sets exitCode and never
  // calls exit(), so buffered output — including the summary — is drained
  // first). See tom_build_base doc/cli_error_handling.md.
  await runner.runToCompletion(normalizedArgs);
}

/// Resolve a guided (`-g` / `--guide`) invocation into a concrete argument
/// list, or return `null` to fall through to the normal (non-guided) run.
///
/// Returns:
/// - a rewritten argument list (original argv minus `-g`, plus the flags the
///   guided flow gathered) when a supported git command is guided and the user
///   completes the flow, or
/// - an empty list when the user cancels or declines the confirmation gate, so
///   the caller runs `runToCompletion([])` (help output) and executes nothing,
///   or
/// - `null` when the invocation is not guided or targets a command without a
///   guided flow, so the caller falls through to the default help/preview.
List<String>? _resolveGuidedArgs(List<String> normalizedArgs) {
  final cliArgs =
      CliArgParser(toolDefinition: buildkitTool).parse(normalizedArgs);
  if (!cliArgs.guide) return null;

  // Resolve the first targeted command (name or alias) to a supported canonical
  // guided command. Both this resolution and the argv rewrite below are pure and
  // unit-tested in test/guided/guided_git_flows_test.dart.
  final command = GuidedGitFlows.targetCommand(
    cliArgs.commands,
    (typed) => buildkitTool.findCommand(typed)?.name ?? typed,
  );
  if (command == null) return null; // no guided flow for this command

  final flags = GuidedGitFlows().resolve(command);
  if (flags == null) {
    // Cancelled or declined at the confirmation gate — do nothing further.
    print('Guided mode cancelled.');
    return const <String>[];
  }

  return GuidedGitFlows.rewriteArgs(normalizedArgs, flags);
}
