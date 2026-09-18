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

/// The `dart` executable to use when a tool needs to spawn an SDK command.
///
/// SCE51. [Platform.resolvedExecutable] is the Dart runtime ONLY when the tool
/// runs under `dart run`. An AOT-compiled tom CLI *is* its own
/// `resolvedExecutable`, so spawning `Platform.resolvedExecutable analyze ...`
/// re-invokes the tool with arguments it does not understand. d4rtgen did
/// exactly that for `--verify-output`: the child parsed `analyze` as a
/// positional, generated bridges in the working directory, printed nothing the
/// parent recognised as a diagnostic, and exited 0 — so the parent reported
/// "analysed clean" having analysed nothing. The verification was a silent
/// no-op in every compiled run, and only became visible when the flag was made
/// default-on, at which point the child verified too and it turned into a fork
/// bomb.
///
/// Resolution order, first hit wins:
///
///   1. `resolvedExecutable` itself, when it IS the Dart runtime.
///   2. `DART_SDK/bin/dart`.
///   3. `FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart`.
///   4. The first `dart` on `PATH`.
///   5. The bare name `dart`, for the OS to resolve.
///
/// The last resort is deliberately a bare name rather than the current
/// executable: a command that cannot be found fails loudly, where one that
/// re-enters the tool does not fail at all.
String resolveDartExecutable({
  String? resolvedExecutable,
  Map<String, String>? environment,
  bool Function(String path)? exists,
}) {
  final executable = resolvedExecutable ?? Platform.resolvedExecutable;
  final env = environment ?? Platform.environment;
  final isFile = exists ?? (path) => File(path).existsSync();
  final dartName = Platform.isWindows ? 'dart.exe' : 'dart';

  final name = executable.split(RegExp(r'[/\\]')).last.toLowerCase();
  if (name == 'dart' || name == 'dart.exe') return executable;

  for (final candidate in [
    if (env['DART_SDK'] case final sdk?) '$sdk/bin/$dartName',
    if (env['FLUTTER_ROOT'] case final root?)
      '$root/bin/cache/dart-sdk/bin/$dartName',
  ]) {
    if (isFile(candidate)) return candidate;
  }

  final separator = Platform.isWindows ? ';' : ':';
  for (final entry in (env['PATH'] ?? '').split(separator)) {
    if (entry.isEmpty) continue;
    final candidate = '$entry/$dartName';
    if (isFile(candidate)) return candidate;
  }

  return dartName;
}
