/// `projreport` — the simple single-command build tool this sample teaches.
///
/// It is the smallest interesting `tom_build_base` tool: it scans a workspace,
/// and for every Dart project it finds it prints one line — name, version, and
/// dependency count — then lets the framework render the consolidated run
/// summary. It has exactly one operation, so it is a [ToolMode.singleCommand]
/// tool whose single executor is registered under the key `'default'`.
///
/// This file is "the tool". The `bin/projreport.dart` entrypoint is a tiny
/// `main` that hands its arguments to [projreportRunner]; the `example/` files
/// each exercise one facet of it against a throwaway fixture workspace.
library;

import 'dart:io';

import 'package:tom_build_base/tom_build_base.dart';

/// The declarative description of the tool — an immutable `const` value.
///
/// Everything the framework needs to parse arguments, generate `--help` and
/// `--version`, expose the standard navigation flags, and decide which folders
/// to visit is encoded here. There is no imperative setup.
const projreportTool = ToolDefinition(
  name: 'projreport',
  description: 'Report the name, version, and dependency count of each '
      'Dart project in a workspace.',
  version: '1.0.0',
  mode: ToolMode.singleCommand,
  // The whole tool only makes sense on Dart projects, so the nature filter
  // lives on the tool itself (single-command tools have no per-command
  // requiredNatures to carry it).
  requiredNatures: {DartProjectFolder},
);

/// The one piece of behaviour the framework cannot supply: what to *do* with
/// each visited Dart project.
///
/// A single-command tool registers its executor under the key `'default'`. The
/// callback receives a [CommandContext] (the folder plus its detected natures)
/// and the parsed [CliArgs], and returns an [ItemResult] the runner aggregates.
/// A project with no version is reported as a (non-failing) *skip* so it shows
/// up in the summary without breaking the exit code.
Map<String, CommandExecutor> projreportExecutors(StringSink out) {
  return {
    'default': CallbackExecutor(
      onExecute: (context, args) async {
        final dart = context.getNature<DartProjectFolder>();
        final version = dart.version;
        if (version == null || version.isEmpty) {
          return ItemResult.skipped(
            path: context.path,
            name: context.name,
            message: 'no version in pubspec',
          );
        }
        final deps = dart.dependencies.length;
        out.writeln('${dart.projectName} v$version — $deps dependencies');
        return ItemResult.success(path: context.path, name: context.name);
      },
    ),
  };
}

/// Build a [ToolRunner] for the tool, wired to a single [output] sink.
///
/// Both the per-project lines (from the executor) and any framework messages
/// go to [output]. Pass a `StringBuffer` to capture everything for a
/// deterministic, testable run — that is exactly how the `example/` files work.
/// With no sink the runner and executor both write to `stdout`, which is what
/// `bin/projreport.dart` wants.
ToolRunner projreportRunner({StringSink? output}) {
  final sink = output ?? stdout;
  return ToolRunner(
    tool: projreportTool,
    executors: projreportExecutors(sink),
    output: sink,
    verbose: false,
  );
}
