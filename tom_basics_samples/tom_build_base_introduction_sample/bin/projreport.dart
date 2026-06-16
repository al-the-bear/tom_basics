/// Runnable entrypoint for the `projreport` tool.
///
/// This is all a `tom_build_base` tool's `main` ever needs to be: build the
/// runner, hand it the arguments, print the consolidated summary, and exit with
/// a code that reflects success. Everything else — argument parsing, `--help`,
/// `--version`, the navigation flags, traversal, ordering — is supplied by the
/// framework from the [projreportTool] definition.
///
/// Point it at any workspace:
///   dart run bin/projreport.dart -R /path/to/workspace --scan /path/to/workspace -r
///
/// Run with: dart run bin/projreport.dart --help
import 'dart:io';

import 'package:tom_build_base_introduction_sample/projreport.dart';

Future<void> main(List<String> args) async {
  final runner = projreportRunner();
  final result = await runner.run(args);

  final summary = result.renderRunSummary();
  if (summary.isNotEmpty) {
    stdout.writeln(summary);
  }
  exit(result.success ? 0 : 1);
}
