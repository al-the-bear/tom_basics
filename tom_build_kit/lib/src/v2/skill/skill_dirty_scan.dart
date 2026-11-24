/// `buildkit :skill-dirty-scan`: the scan behind `tom_dirty_work`
/// (buildkit_ws_commands.md § 1.6; `tom_dw_scan_tree` of
/// `.claude/skills/_lib/dirty_scan_lib.sh`): per repository the code, fork
/// and upstream entries (deepest first, each followed by its run worktrees
/// under `.worktrees/`), then the root — every uncommitted path in its group
/// (secret / generated / modified / new) with the group's fingerprint, and the
/// repositories that are no entry. `_ai` and `tom_binaries` are not scanned.
/// Read-only; the decision document stays in the skill.
///
/// `--rows` prints the rows of `tom_dirty_work --scan` byte for byte;
/// `--json` the run report with a `scan` section (`buildkit help
/// skill-json`); `--baseline` (a file) records every path uncommitted now
/// (`tom_dirty_work --baseline`), for `:skill-reconcile-code --own-since`.
/// Exit 0.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import 'skill_common.dart';
import 'skill_messages.dart';

/// `:skill-dirty-scan` (see the library comment).
class SkillDirtyScanExecutor extends CommandExecutor {
  SkillDirtyScanExecutor({this.out, this.now, this.gitEnvironment});

  final StringSink? out;
  final DateTime? now;
  final Map<String, String>? gitEnvironment;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.failure(
        path: context.path,
        name: context.name,
        error:
            ':skill-dirty-scan runs over the whole tree, without the traversal',
      );

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final sink = out ?? stdout;
    final opts = args.optionsFor('skill-dirty-scan');
    final json = opts['json'] == true;
    final baseline = opts['baseline'] as String?;
    final started = now ?? DateTime.now();
    final given = [
      if (baseline != null) ...['--baseline', baseline],
    ];
    final found = await skillDiscover(
      args: args,
      command: ':skill-dirty-scan',
      given: given,
      json: json,
      sink: sink,
      started: started,
    );
    if (found.refused != null) return found.refused!;
    final set = found.set!;

    if (baseline != null) {
      final file = p.isAbsolute(baseline)
          ? baseline
          : p.join(set.root, baseline);
      if (args.dryRun) {
        sink.writeln('Would write the baseline to $file.');
        return const ToolResult.success();
      }
      final n = await skillWriteBaseline(set, file, env: gitEnvironment);
      sink.writeln('Baseline: $n uncommitted path(s) recorded in $file.');
      return const ToolResult.success();
    }

    final scan = await skillScanTree(set, env: gitEnvironment, now: started);
    final names = RepoNames([
      for (final r in scan.repos) r.abs == set.root ? '' : r.disp,
    ]);
    final report = RunReport(
      tool: 'buildkit',
      command: ':skill-dirty-scan',
      root: set.root,
      host: set.host,
      started: started,
      given: given,
      names: names,
    );
    report.lookedAt.addAll([
      for (final r in scan.repos) r.abs == set.root ? '' : r.disp,
    ]);
    for (final r in scan.repos) {
      if (r.groups.isEmpty) continue;
      report.add(
        skillUncommitted.raise(
          repository: r.abs == set.root ? '' : r.disp,
          finding:
              '${r.files} uncommitted file(s) in ${r.groups.length} group(s).',
          evidence: [
            for (final g in r.groups)
              ReportEvidence(g.group, [
                for (final f in g.files) '${f.xy} ${f.path}',
              ], label: '${g.group} (${g.fingerprint}):'),
          ],
          state: 'Left where it is.',
        ),
      );
    }
    if (scan.unknown.isNotEmpty) {
      report.add(
        skillUnknownSeen.raise(
          finding:
              '${scan.unknown.length} repositor${scan.unknown.length == 1 ? 'y' : 'ies'} '
              'under the root that repos.yaml does not list:',
          evidence: [ReportEvidence('paths', scan.unknown)],
          state: 'Not scanned.',
        ),
      );
    }
    if (opts['rows'] == true) {
      sink.writeln(scan.rows().join('\n'));
    } else if (json) {
      sink.writeln(skillJson(report, 'scan', scan.toJson()));
    } else {
      sink.writeln(report.renderText(verbose: args.verbose));
    }
    return const ToolResult.success();
  }
}
