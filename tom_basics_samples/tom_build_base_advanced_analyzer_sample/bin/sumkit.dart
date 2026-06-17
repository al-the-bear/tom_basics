/// Runnable entrypoint for the `sumkit` analyzer-cache reporter.
///
/// Like every `tom_build_base` tool, `main` is tiny: build the runner, hand it
/// the arguments, print whatever the framework wants to add (skipped/error
/// blocks), and exit with a code that reflects success. The `--warm` /
/// `--rebuild` flags, `--help`, `--version`, traversal, the Dart-project nature
/// filter, and `--nested` handling are all supplied by the framework from the
/// [sumkitTool] definition. The per-project report lines are written by the
/// executor itself (a single-command tool prints its own body — see
/// `lib/sumkit.dart`).
///
/// Try it against any workspace:
///   dart run bin/sumkit.dart -R /path/to/ws --scan /path/to/ws -r
///   dart run bin/sumkit.dart --warm -R /path/to/ws --scan /path/to/ws -r
///   dart run bin/sumkit.dart --rebuild -R /path/to/ws --scan /path/to/ws -r
///
/// Run with: dart run bin/sumkit.dart --help
import 'dart:io';

import 'package:tom_build_base_advanced_analyzer_sample/sumkit.dart';

Future<void> main(List<String> args) async {
  final runner = sumkitRunner();
  final result = await runner.run(args);

  final summary = result.renderRunSummary();
  if (summary.isNotEmpty) {
    stdout.writeln(summary);
  }
  exit(result.success ? 0 : 1);
}
