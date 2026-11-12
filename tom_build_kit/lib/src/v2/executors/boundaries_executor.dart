/// Native v2 executor for the `:boundaries` command: the context-boundary
/// check of tom_build_base ([checkContextBoundaries]) over the projects of
/// the traversal.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

/// Runs the context-boundary check on one project.
///
/// A project with rules is clean, or fails with its violations and rule
/// errors. A project without a `boundaries:` section is NOT MEASURED: when it
/// was asked for by name (`-p`) or is the folder the command runs in, that
/// fails, because a check that measured nothing is not a pass; met during a
/// wider traversal it is skipped and named.
class BoundariesExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final options = args.optionsFor('boundaries');
    final json = options['json'] == true;
    final tests = options['tests'] == true ? true : null;
    final relative = p.relative(context.path, from: context.executionRoot);
    final rel = relative == '.' ? context.name : relative;

    final report = checkContextBoundaries(context.path, includeTests: tests);

    if (json) {
      // Straight to stdout: print() runs through the console-markdown zone,
      // which would turn the backticks of the messages into colour codes.
      stdout.writeln(jsonEncode({...report.toJson(), 'project': rel}));
    }

    if (!report.measured) {
      final explicit =
          args.projectPatterns.isNotEmpty ||
          p.equals(
            p.normalize(p.absolute(context.path)),
            p.normalize(p.absolute(Directory.current.path)),
          );
      const why =
          'NOT MEASURED: no `$kBoundariesSection:` section in '
          'buildkit.yaml';
      if (!json) print('  $rel: $why');
      return explicit
          ? ItemResult.failure(
              path: context.path,
              name: context.name,
              error: why,
            )
          : ItemResult.skipped(
              path: context.path,
              name: context.name,
              message: why,
            );
    }

    if (!json) {
      for (final finding in [...report.ruleErrors, ...report.violations]) {
        print('  $rel: $finding');
      }
      print(
        '  $rel: ${report.verdict} — ${report.librariesChecked} libraries, '
        '${report.importsChecked} imports, ${report.violations.length} '
        'violation(s), ${report.ruleErrors.length} rule error(s)',
      );
    }

    if (report.clean) {
      return ItemResult.success(
        path: context.path,
        name: context.name,
        message: 'clean',
      );
    }
    return ItemResult.failure(
      path: context.path,
      name: context.name,
      error:
          '${report.violations.length} boundary violation(s), '
          '${report.ruleErrors.length} rule error(s)',
    );
  }
}
