/// Runnable entrypoint for the `relkit` multi-command tool.
///
/// Like every `tom_build_base` tool, `main` is tiny: build the runner, hand it
/// the arguments, print the consolidated summary, and exit with a code that
/// reflects success. The `:command` parsing, per-command options, `--help`,
/// `--version`, traversal, sequencing, and `--nested` handling are all supplied
/// by the framework from the [relkitTool] definition.
///
/// Try it against any workspace:
///   dart run bin/relkit.dart :report -R /path/to/ws --scan /path/to/ws -r
///   dart run bin/relkit.dart :audit :report -R /path/to/ws --scan /path/to/ws -r
///   dart run bin/relkit.dart :bump --part=minor -R /path/to/ws --scan /path/to/ws -r
///
/// Run with: dart run bin/relkit.dart --help
import 'dart:io';

import 'package:tom_build_base_advanced_sample/relkit.dart';

Future<void> main(List<String> args) async {
  final runner = relkitRunner();
  final result = await runner.run(args);

  final summary = result.renderRunSummary();
  if (summary.isNotEmpty) {
    stdout.writeln(summary);
  }
  exit(result.success ? 0 : 1);
}
