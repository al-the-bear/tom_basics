#!/usr/bin/env dart

library;

import 'dart:async';
import 'dart:io';

import 'package:console_markdown/console_markdown.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/tom_build_kit.dart';

Future<void> main(List<String> args) async {
  if (Zone.current[#consoleMarkdownActive] != true) {
    return runZoned(
      () => main(args),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          parent.print(zone, line.toConsole());
        },
      ),
      zoneValues: {#consoleMarkdownActive: true},
    );
  }

  final runner = ToolRunner(
    tool: buildkitTool,
    executors: createBuildkitExecutors(),
    verbose: true,
  );

  final result = await runner.run(args);

  // Shared, consistent end-of-run errors/skips summary (tom_build_base).
  // Empty for special/single-shot commands that traverse nothing.
  final summary = result.renderRunSummary();
  if (summary.isNotEmpty) {
    stdout.writeln('\n$summary');
  }

  if (!result.success) {
    exit(1);
  }
}
