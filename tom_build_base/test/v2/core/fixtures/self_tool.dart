// A tool for BB-WSR-9: run by the test under the Dart VM with an empty PATH;
// `-w` must start the sub-workspace runs with this same program.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

const _tool = ToolDefinition(
  name: 'selftool',
  description: 'Tool for the -w self-start test',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.all,
  globalOptions: [
    OptionDefinition.flag(
      name: 'workspace-recursion',
      abbr: 'w',
      description: 'Also run in nested workspaces',
    ),
  ],
  commands: [
    CommandDefinition(
      name: 'write',
      description: 'Names each project',
      requiresTraversal: true,
      supportsProjectTraversal: true,
      worksWithNatures: {DartProjectFolder},
    ),
  ],
);

class _Visit extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    stdout.writeln('visited ${p.basename(context.path)}');
    return ItemResult.success(path: context.path, name: context.name);
  }
}

Future<void> main(List<String> args) async {
  final result = await ToolRunner(
    tool: _tool,
    executors: {'write': _Visit()},
  ).run(args);
  exit(result.success ? 0 : 1);
}
