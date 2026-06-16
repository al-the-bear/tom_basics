// A tom_build_base tool is a declarative value, not a script.
//
// The whole identity of `projreport` lives in a single `const ToolDefinition`:
// its name, version, calling convention (a one-operation tool is
// ToolMode.singleCommand), and the nature filter that decides which folders it
// visits. From that value the framework derives argument parsing, --help,
// --version, and the standard navigation flags — none of it hand-written. This
// example just inspects the definition and asks the framework to print its
// version, with the output captured so it is deterministic.
//
// Run with: dart run example/01_a_tool_is_a_value_example.dart
import 'package:tom_build_base_introduction_sample/projreport.dart';

Future<void> main() async {
  // The definition is an ordinary immutable value you can read.
  print('name:     ${projreportTool.name}');
  print('version:  ${projreportTool.version}');
  print('mode:     ${projreportTool.mode}');
  print('natures:  ${projreportTool.requiredNatures}');

  // --version is handled entirely by the framework from that same value.
  final buf = StringBuffer();
  await projreportRunner(output: buf).run(['--version']);
  print('--version prints: ${buf.toString().trim()}');

  // expected output:
  // name:     projreport
  // version:  1.0.0
  // mode:     ToolMode.singleCommand
  // natures:  {DartProjectFolder}
  // --version prints: projreport v1.0.0
}
