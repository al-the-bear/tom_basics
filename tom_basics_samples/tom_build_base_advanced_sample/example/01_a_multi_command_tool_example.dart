// A multi-command tool is still just a value — now with a list of commands.
//
// Where the introduction sample's tool had one operation, `relkit` is a
// ToolMode.multiCommand tool: its identity is a const ToolDefinition carrying a
// *list* of CommandDefinitions, each with its own description and options, plus
// a defaultCommand for when the user names none. This example reads that
// structure straight off the value and lets the framework print the version —
// no command dispatch table written by hand.
//
// Run with: dart run example/01_a_multi_command_tool_example.dart
import 'package:tom_build_base_advanced_sample/relkit.dart';

Future<void> main() async {
  print('name:            ${relkitTool.name}');
  print('mode:            ${relkitTool.mode}');
  print('default command: ${relkitTool.defaultCommand}');
  print('commands:');
  for (final cmd in relkitTool.commands) {
    final opts = cmd.options.map((o) => o.name).join(', ');
    print('  :${cmd.name} — ${cmd.description} [options: $opts]');
  }

  // --version is handled by the framework from the same value.
  final buf = StringBuffer();
  await relkitRunner(output: buf).run(['--version']);
  print('--version prints: ${buf.toString().trim()}');

  // expected output:
  // name:            relkit
  // mode:            ToolMode.multiCommand
  // default command: report
  // commands:
  //   :report — Print one line per Dart project (name, version, deps). [options: with-path]
  //   :audit — Fail projects that are not release-ready. [options: min-desc]
  //   :bump — Show the next version each project would get (dry-run). [options: part]
  // --version prints: relkit v1.0.0
}
