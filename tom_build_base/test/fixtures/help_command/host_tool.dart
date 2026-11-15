// A host tool with one own command and one wired nested tool (`fakegen`, a
// standalone tool found on PATH). BB-HELPCMD-8 runs it as a process to check
// that `help fakegen` takes the help from the nested tool.
import 'dart:io';

import 'package:tom_build_base/tom_build_base_v2.dart';

const _tool = ToolDefinition(
  name: 'hosttool',
  description: 'A host tool with a wired nested tool',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.projectTool,
  commands: [CommandDefinition(name: 'own', description: 'The own command')],
  defaultIncludes: [
    ToolWiringEntry(binary: 'fakegen', mode: WiringMode.standalone),
  ],
);

Future<void> main(List<String> args) async {
  final result = await ToolRunner(tool: _tool, executors: const {}).run(args);
  exitCode = result.success ? 0 : 1;
  await stdout.flush();
}
