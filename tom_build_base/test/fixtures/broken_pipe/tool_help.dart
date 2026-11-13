// A ToolRunner tool, as buildkit / testkit / issuekit are built: `--help`
// writes through ConsoleMarkdownSink. BB-PIPE-3 pipes it into `head -1`.
import 'package:tom_build_base/tom_build_base_v2.dart';

const _tool = ToolDefinition(
  name: 'pipetool',
  description: 'A tool whose help is long enough to fill a pipe',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.projectTool,
  commands: [
    CommandDefinition(name: 'first', description: 'The first command'),
    CommandDefinition(name: 'second', description: 'The second command'),
  ],
);

Future<void> main(List<String> args) => runWithConsoleMarkdown(() async {
  final runner = ToolRunner(tool: _tool, executors: const {});
  // Many runs of the help, so the pipe's buffer fills after `head` is gone.
  for (var i = 0; i < 400; i++) {
    await runner.run(args);
  }
});
