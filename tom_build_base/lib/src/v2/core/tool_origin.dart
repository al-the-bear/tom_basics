/// Where a running tool came from, for the line under its version banner.
///
/// SCE8. `--version` printed a number and nothing about which COPY answered.
/// During SCC70 a stale precompiled binary and the working-tree source printed
/// the same banner, and a whole regeneration batch was discarded because it
/// could not be attributed. SCD3 then made the number trustworthy — a version
/// stamp test in every package that prints a banner — which does not settle
/// this: two runs can share a number and differ in origin. A working tree
/// carrying an unpublished fix, a pub-cache copy, and a binary on PATH from a
/// DIFFERENT clone of the workspace all report the same version.
///
/// This lives in `tom_build_base` rather than in each tool because the banner
/// does: `ToolRunner` prints it, so every tom CLI gains the line at once and
/// none of them can word it differently.
library;

import 'dart:io';

/// The origin line for a run whose executable is [resolvedExecutable] and
/// whose entry point is [script].
///
/// `binary: /path/to/tool` when the process IS the tool — an AOT build.
/// `source: /path/to/entry.dart` when a Dart runtime is executing the tool, in
/// which case the runtime is the same string for every tool in the workspace
/// and the SCRIPT is the thing worth naming.
///
/// It does not try to label the source kind. A working tree, a pub-cache copy
/// and a `.dart_tool/pub/bin` snapshot are told apart by their paths, which is
/// what the reader needs and what cannot go out of date.
String toolOriginLine({
  required String resolvedExecutable,
  required Uri script,
}) {
  final executableName = resolvedExecutable
      .split(RegExp(r'[/\\]'))
      .last
      .toLowerCase();
  // Matched on the WHOLE name, not a substring: `d4rtgen` contains no "dart",
  // but a tool that did would otherwise report itself as its own interpreter.
  final isDartRuntime =
      executableName == 'dart' || executableName == 'dart.exe';
  if (isDartRuntime) {
    return 'source: ${script.toFilePath()}';
  }
  return 'binary: $resolvedExecutable';
}

/// [toolOriginLine] for the process running now.
String currentToolOriginLine() => toolOriginLine(
  resolvedExecutable: Platform.resolvedExecutable,
  script: Platform.script,
);
