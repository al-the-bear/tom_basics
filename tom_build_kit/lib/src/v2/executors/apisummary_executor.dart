/// Native v2 executor for the `:apisummary` command: the API-summary drift
/// check ([checkApiSummary]) over the Dart packages of the traversal.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../../apisummary/api_summary_check.dart';

/// Compares one package's public API with its `doc/api/api_summary_*.md`.
///
/// Findings are printed; they fail the package only with `--strict`. A
/// package without a summary, or without a `lib/` library, is skipped and
/// named: there is nothing to compare, which is not a pass.
class ApisummaryExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final options = args.optionsFor('apisummary');
    final strict = options['strict'] == true;
    final relative = p.relative(context.path, from: context.executionRoot);
    final rel = relative == '.' ? context.name : relative;
    final packageDir = p.normalize(p.absolute(context.path));

    final report = checkApiSummary(packageDir, _packageName(packageDir));
    if (!report.measured) {
      const why = 'no API summary ($kApiSummaryDir/api_summary_*.md)';
      stdout.writeln('  $rel: NOT MEASURED — $why');
      return ItemResult.skipped(
        path: context.path,
        name: context.name,
        message: why,
      );
    }

    // Straight to stdout: print() runs through the console-markdown zone,
    // which would read backticks and brackets as markup.
    for (final f in report.missing) {
      stdout.writeln('  $rel: missing from the summary: $f');
    }
    for (final f in report.stale) {
      stdout.writeln('  $rel: not in the API: $f');
    }
    final verdict = report.clean ? 'up to date' : 'out of date';
    final summary =
        '$verdict — ${report.apiSymbols} public symbols, ${report.claims} '
        'summary claims in ${report.summaryFiles.length} file(s); '
        '${report.missing.length} missing, ${report.stale.length} not in the '
        'API';
    stdout.writeln('  $rel: $summary');

    if (report.clean || !strict) {
      return ItemResult.success(
        path: context.path,
        name: context.name,
        message: summary,
      );
    }
    return ItemResult.failure(
      path: context.path,
      name: context.name,
      error:
          'API summary out of date: ${report.missing.length} missing, '
          '${report.stale.length} not in the API',
    );
  }

  /// The `name:` of the package's pubspec, else its folder name.
  String _packageName(String packageDir) {
    final pubspec = File(p.join(packageDir, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final m = RegExp(
        r'^name:\s*([A-Za-z0-9_]+)',
        multiLine: true,
      ).firstMatch(pubspec.readAsStringSync());
      if (m != null) return m.group(1)!;
    }
    return p.basename(packageDir);
  }
}
