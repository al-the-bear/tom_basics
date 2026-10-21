/// Native v2 executor for the `:unreferenced` command: the unreferenced-export
/// audit of a project's `unreferenced:` section in `buildkit.yaml`.
///
/// A project without the section is skipped. A finding, a stale allowlist
/// entry, a malformed section or an audit that checked nothing fails the
/// project, so the command's exit code is the audit's verdict.
library;

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../../unreferenced/unreferenced_config.dart';

class UnreferencedExecutor extends CommandExecutor {
  /// Where the report goes; standard output by default.
  final void Function(String line) write;

  UnreferencedExecutor({void Function(String line)? write})
    : write = write ?? print;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final UnreferencedExportsConfig? config;
    try {
      config = UnreferencedExportsConfig.load(context.path);
    } on FormatException catch (e) {
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error: e.message,
      );
    }
    if (config == null) {
      return ItemResult.skipped(
        path: context.path,
        name: context.name,
        message: 'no `$unreferencedConfigKey:` section in buildkit.yaml',
      );
    }
    if (args.listOnly) {
      write('  ${p.relative(context.path, from: context.executionRoot)}');
      return ItemResult.success(
        path: context.path,
        name: context.name,
        message: 'listed',
      );
    }

    final report = config.audit();
    if (report.symbolsChecked == 0) {
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error:
            'NOT MEASURED: no exported symbol was found under ${config.root} '
            'with the prefix ${config.packagePrefix}, so the audit proved '
            'nothing.',
      );
    }

    String? package;
    for (final finding in report.unreferenced) {
      if (finding.symbol.package != package) {
        package = finding.symbol.package;
        write('FAIL  $package');
      }
      final where = p.relative(finding.symbol.file, from: config.root);
      write(
        '        $where:${finding.symbol.line}  ${finding.symbol.symbol} '
        '(${finding.symbol.kind}) — ${finding.verdict}',
      );
    }
    for (final entry in report.stale) {
      write(
        'STALE allowlist entry: ${entry.package} ${entry.symbol} — no longer '
        'unreferenced, or no longer exists. Remove it.',
      );
    }
    if (args.verbose) {
      for (final (entry, finding) in report.allowed) {
        write(
          'allow ${entry.package} ${entry.symbol} '
          '(${finding.namedByTests ? 'tests only' : 'nowhere'}): '
          '${entry.reason}',
        );
      }
    }

    final failed = report.unreferenced.length + report.stale.length;
    if (failed > 0) {
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error:
            '${report.unreferenced.length} unreferenced export(s), '
            '${report.stale.length} stale allowlist '
            'entr${report.stale.length == 1 ? 'y' : 'ies'} '
            '(${report.symbolsChecked} symbols checked against '
            '${report.consumerFiles} consumer files).',
      );
    }
    final summary =
        'every exported symbol is referenced: ${report.symbolsChecked} '
        'checked against ${report.consumerFiles} consumer files; '
        '${report.testSeams} declared test seam(s), '
        '${report.allowed.length} allowlisted with a reason';
    write(summary);
    return ItemResult.success(
      path: context.path,
      name: context.name,
      message: summary,
    );
  }
}
