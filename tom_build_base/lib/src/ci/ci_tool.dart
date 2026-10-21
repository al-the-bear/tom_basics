/// A CI tool's command line, declared on this package's tool framework: one
/// command per stage plus `all`, `--help`, `--version` and prefix resolution
/// (`:te` is `:test`).
library;

import 'dart:io';

import '../v2/core/cli_arg_parser.dart';
import '../v2/core/command_definition.dart';
import '../v2/core/command_executor.dart';
import '../v2/core/tool_definition.dart';
import '../v2/core/tool_runner.dart';

/// The tool definition of a CI tool: one command per stage in [stages], plus
/// `all`, each described by [descriptions] (which must hold `all` too).
ToolDefinition ciToolDefinition({
  required String name,
  required String description,
  required String version,
  required List<String> stages,
  required Map<String, String> descriptions,
  String? helpFooter,
  String examplePrefix = 'ci.sh',
}) => ToolDefinition(
  name: name,
  description: description,
  version: version,
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.minimal,
  commands: [
    for (final stage in [...stages, 'all'])
      CommandDefinition(
        name: stage,
        description: descriptions[stage] ?? '',
        requiresTraversal: false,
        supportsProjectTraversal: false,
        examples: ['$examplePrefix :$stage'],
      ),
  ],
  helpFooter: helpFooter,
);

/// Builds the runner of a CI tool.
///
/// Every stage command shares one executor: the first one the runner invokes
/// hands **all** stages named on the command line, in the order given, to
/// [runStages], and turns the summary line it returns into the result — green
/// when it starts with `CI GREEN`. The rest find the work done. (Run one at a
/// time, the commands would stop at the first red, which is the wrong policy
/// for a verification run: every red is worth knowing.)
ToolRunner ciToolRunner({
  required ToolDefinition tool,
  required Future<String> Function(List<String> stages, StringSink console)
  runStages,
  StringSink? console,
}) {
  var done = false;
  Future<ToolResult> runAll(CliArgs args) async {
    if (done) return const ToolResult.success();
    done = true;
    final requested = [
      for (final name in args.commands) tool.findCommand(name)!.name,
    ];
    final out = console ?? stdout;
    final line = await runStages(requested, out);
    out.writeln(line);
    return line.startsWith('CI GREEN')
        ? const ToolResult.success()
        : ToolResult.failure(line);
  }

  final executor = CallbackExecutor(
    onExecute: (context, args) async => ItemResult.skipped(
      path: context.path,
      name: context.name,
      message: 'stages do not traverse',
    ),
    onExecuteWithoutTraversal: runAll,
  );
  return ToolRunner(
    tool: tool,
    executors: {for (final command in tool.commands) command.name: executor},
  );
}
