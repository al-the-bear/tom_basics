// A ToolRunner tool, as buildkit / testkit / issuekit are built: its help and
// its argument errors go through the console markdown zone. BB-STYLE runs it
// with stdout piped, under NO_COLOR and FORCE_COLOR, and in a pseudo-terminal.
import 'dart:io';

import 'package:tom_build_base/tom_build_base_v2.dart';

const _tool = ToolDefinition(
  name: 'styletool',
  description: 'A tool whose help carries **bold** and `code`',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.projectTool,
  commands: [
    CommandDefinition(name: 'first', description: 'The **first** command'),
  ],
);

Future<void> main(List<String> args) => runWithConsoleMarkdown(() async {
  final result = await ToolRunner(tool: _tool, executors: const {}).run(args);
  // A plain print through the zone, as a tool's own output is written.
  print('done: **${result.success}** `ok`');
  exitCode = result.success ? 0 : 1;
  await stdout.flush();
});
