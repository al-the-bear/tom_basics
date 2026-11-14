/// Native v2 executor for the `:doccheck` command: the documents the
/// guidelines ask of a package ([checkPackageDocs]), per package of the
/// traversal.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../../doccheck/doc_check.dart';

/// Reports one package's missing documents and README sections.
///
/// Gaps are printed; they fail the package only with `--strict`. A package
/// that opts out (`doccheck: skip: <reason>`) is skipped with its reason and
/// none of its gaps is reported. A configuration error (an unknown check, an
/// opt-out without a reason) always fails: an opt-out that does not parse
/// must not pass silently.
class DoccheckExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final strict = args.optionsFor('doccheck')['strict'] == true;
    final relative = p.relative(context.path, from: context.executionRoot);
    final rel = relative == '.' ? context.name : relative;
    final packageDir = p.normalize(p.absolute(context.path));
    final workspaceRoot = p.normalize(p.absolute(context.executionRoot));

    final config = DocCheckConfig.load(
      packageDir,
      workspaceRoot: workspaceRoot,
    );
    // Straight to stdout: print() runs through the console-markdown zone.
    if (config.errors.isNotEmpty) {
      for (final e in config.errors) {
        stdout.writeln('  $rel: configuration: $e');
      }
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error: '${config.errors.length} doccheck configuration error(s)',
      );
    }
    if (config.skip != null) {
      stdout.writeln('  $rel: skipped — ${config.skip}');
      return ItemResult.skipped(
        path: context.path,
        name: context.name,
        message: 'doccheck: ${config.skip}',
      );
    }

    final report = checkPackageDocs(packageDir, config);
    for (final gap in report.gaps) {
      stdout.writeln('  $rel: missing: $gap');
    }
    final excluded = report.excluded.isEmpty
        ? ''
        : '; excluded: ${report.excluded.keys.join(', ')}';
    final summary = report.complete
        ? 'complete — ${report.checked.length} checks$excluded'
        : '${report.gaps.length} gap(s) in ${report.checked.length} checks'
              '$excluded';
    stdout.writeln('  $rel: $summary');

    if (report.complete || !strict) {
      return ItemResult.success(
        path: context.path,
        name: context.name,
        message: summary,
      );
    }
    return ItemResult.failure(
      path: context.path,
      name: context.name,
      error: '${report.gaps.length} documentation gap(s)',
    );
  }
}
