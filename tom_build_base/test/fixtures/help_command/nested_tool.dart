// The nested tool `fakegen` of BB-HELPCMD-8: a standalone tool that answers
// `--dump-definitions` (the host's wiring) and `--nested --help`.
import 'dart:io';

import 'package:tom_build_base/tom_build_base_v2.dart';

const _tool = ToolDefinition(
  name: 'fakegen',
  description: 'Generates the fake artefacts',
  version: '1.0.0',
  mode: ToolMode.singleCommand,
  features: NavigationFeatures.projectTool,
  globalOptions: [
    OptionDefinition.option(name: 'depth', description: 'How deep it goes'),
  ],
);

Future<void> main(List<String> args) async {
  final result = await ToolRunner(tool: _tool, executors: const {}).run(args);
  exitCode = result.success ? 0 : 1;
  await stdout.flush();
}
