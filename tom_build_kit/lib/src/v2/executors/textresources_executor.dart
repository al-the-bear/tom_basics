/// Native v2 executor for the `:textresources` command: an application's
/// text resource files assembled from its packages' files
/// ([runTextResources]), per project of the traversal that has a
/// `text-resources:` section.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../../textresources/text_resources.dart';

/// Assembles (or, with `--check`, compares) one project's text resources.
class TextresourcesExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final check = args.optionsFor('textresources')['check'] == true;
    return runTextResourcesStep(context, check: check, dryRun: args.dryRun);
  }
}

/// The step of [context]'s project: what `:textresources` does, and what
/// `:build` does first. A project without a `text-resources:` section
/// succeeds with nothing to do.
Future<ItemResult> runTextResourcesStep(
  CommandContext context, {
  bool check = false,
  bool dryRun = false,
}) async {
  final relative = p.relative(context.path, from: context.executionRoot);
  final rel = relative == '.' ? context.name : relative;
  final projectDir = p.normalize(p.absolute(context.path));
  // Straight to stdout: print() runs through the console-markdown zone.
  final TextResourcesRun? run;
  try {
    run = runTextResources(projectDir, check: check || dryRun);
  } on TextResourcesException catch (e) {
    stdout.writeln('  $rel: text resources: $e');
    return ItemResult.failure(
      path: context.path,
      name: context.name,
      error: 'text resources: $e',
    );
  }
  if (run == null) {
    return ItemResult.success(
      path: context.path,
      name: context.name,
      message: 'no text-resources',
    );
  }
  for (final warning in run.warnings) {
    stdout.writeln('  $rel: warning: $warning');
  }
  for (final file in run.written) {
    stdout.writeln('  $rel: wrote $file');
  }
  if (check || dryRun) {
    for (final file in run.differing) {
      stdout.writeln(
        '  $rel: ${dryRun && !check ? 'would write' : 'differs from a fresh assembly'}: $file',
      );
    }
    if (check && run.differing.isNotEmpty) {
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error:
            '${run.differing.length} text resource file(s) differ from a fresh '
            'assembly: run buildkit :textresources',
      );
    }
  }
  final summary =
      '${run.written.length} written, ${run.unchanged.length} unchanged'
      '${run.warnings.isEmpty ? '' : ', ${run.warnings.length} warning(s)'}';
  stdout.writeln('  $rel: text resources: $summary');
  return ItemResult.success(
    path: context.path,
    name: context.name,
    message: summary,
  );
}
