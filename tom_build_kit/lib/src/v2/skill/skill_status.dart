/// `buildkit :skill-status`: what `status_probe.sh` answers on a host
/// (buildkit_ws_commands.md § 1.6; `.claude/skills/_lib/status_probe.sh`):
/// per repository of this host's repos.yaml (the root first, then the
/// entries deepest first) its state against `origin/<branch>` after a
/// fetch, the unmerged run branches under `.worktrees/`, the old trees beside
/// the root. Read-only, except `git fetch`.
///
/// `--rows` prints the probe's rows byte for byte (what `tom_fleet_status`
/// reads); `--json` the run report with a `status` section
/// (`buildkit help skill-json`). Exit 0 (a probe judges nothing; the
/// verdict is the skill's).
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../ws/ws_common.dart';
import 'skill_common.dart';
import 'skill_messages.dart';

/// One REPO row of the probe.
class SkillRepoStatus {
  SkillRepoStatus(this.entry, this.state);
  final SkillEntry entry;

  /// ok | missing | offpin | nobranch.
  final String state;
  String? head;
  int? behind;
  int? lagAt;
  int? ahead;
  int? unpushedAt;
  int? dirty;
  int? syncAt;

  String _v(Object? v) => v == null ? '-' : '$v';

  String row() => [
    'REPO',
    entry.rel,
    entry.kind,
    state,
    _v(head),
    _v(behind),
    _v(lagAt),
    _v(ahead),
    _v(unpushedAt),
    _v(dirty),
    _v(syncAt),
  ].join('\t');

  Map<String, Object?> toJson() => {
    'path': entry.rel,
    'kind': entry.kind,
    'state': state,
    'head': head,
    'behind': behind,
    'lagAt': lagAt,
    'ahead': ahead,
    'unpushedAt': unpushedAt,
    'dirty': dirty,
    'syncAt': syncAt,
  };
}

/// One probe of this host.
class SkillStatusRun {
  SkillStatusRun({
    required this.set,
    this.dryRun = false,
    DateTime? now,
    this.gitEnvironment,
    this.oldTreeSeconds = 45,
  }) : now = now ?? DateTime.now();

  final RepoSet set;
  final bool dryRun;
  final DateTime now;
  final Map<String, String>? gitEnvironment;

  /// How long measuring an old tree may take (`TFS_OLD_DU_SECONDS`).
  final int oldTreeSeconds;

  late final RunReport report;
  final repos = <SkillRepoStatus>[];
  final runBranches =
      <({String rel, String branch, int commits, String worktree})>[];
  final oldTrees = <({String path, int? size})>[];

  WsGit _git(String dir) => WsGit(dir, gitEnvironment);

  int? _int(String s) => int.tryParse(s.trim());

  Future<RunReport> run() async {
    final entries = [skillRoot(set), ...skillEntries(set)];
    report = RunReport(
      tool: 'buildkit',
      command: ':skill-status',
      root: set.root,
      host: set.host,
      started: now,
      given: const [],
      names: RepoNames([for (final e in entries) e.isRoot ? '' : e.rel]),
    );
    if (!dryRun) {
      await wsPool([
        for (final e in entries)
          if (e.kind != 'upstream' && e.cloned) e,
      ], (e) => _git(e.abs).run(['fetch', '-q', 'origin']));
    }
    for (final e in entries) {
      repos.add(await _probe(e));
    }
    await _oldTrees();
    report.lookedAt.addAll([for (final e in entries) e.isRoot ? '' : e.rel]);
    for (final r in repos) {
      final rel = r.entry.isRoot ? '' : r.entry.rel;
      final def = switch (r.state) {
        'missing' => skillMissing,
        'offpin' => skillOffPin,
        'nobranch' => skillNoBranch,
        _ => null,
      };
      if (def == null) continue;
      report.add(
        def.raise(
          repository: rel,
          branch: r.entry.branch,
          finding: switch (r.state) {
            'missing' => 'Not cloned (${r.entry.kind}).',
            'offpin' => 'At ${r.head}, its pin is ${r.entry.pin}.',
            _ => 'origin has no branch ${r.entry.branch}.',
          },
        ),
      );
    }
    for (final b in runBranches) {
      report.add(
        skillRunBranch.raise(
          repository: b.rel == '.' ? '' : b.rel,
          branch: b.branch,
          finding:
              '${b.branch} has ${b.commits} commit(s) its repository\'s branch '
              'lacks.',
          evidence: [
            ReportEvidence('worktree', [b.worktree], label: 'Worktree:'),
          ],
        ),
      );
    }
    for (final t in oldTrees) {
      report.add(
        skillOldTree.raise(
          finding:
              '${t.path} (${t.size == null ? 'size unknown' : '${t.size} KiB'}).',
          evidence: [
            ReportEvidence('paths', [t.path]),
          ],
        ),
      );
    }
    return report;
  }

  Future<SkillRepoStatus> _probe(SkillEntry e) async {
    final g = _git(e.abs);
    if (!e.cloned || !await g.ok(['rev-parse', '--git-dir'])) {
      return SkillRepoStatus(e, 'missing');
    }
    final head = await g.out(['log', '-1', '--pretty=%h']);
    final porcelain = await g.out([
      'status',
      '--porcelain',
      '--untracked-files=normal',
    ]);
    final dirty = [
      for (final l in porcelain.split('\n'))
        if (l.isNotEmpty && !l.startsWith('?? .worktrees/')) l,
    ].length;
    int? sync;
    final reflog = await g.out([
      'reflog',
      '--date=unix',
      '--format=%gd:%gs',
      'HEAD',
    ]);
    for (final line in reflog.split('\n')) {
      if (!RegExp(r':(pull|merge|rebase|clone)').hasMatch(line)) continue;
      sync = _int(
        RegExp(r'^HEAD@\{([0-9]*)\}').firstMatch(line)?.group(1) ?? '',
      );
      break;
    }
    SkillRepoStatus fill(String state) => SkillRepoStatus(e, state)
      ..head = head.isEmpty ? null : head
      ..dirty = dirty
      ..syncAt = sync;

    if (e.kind == 'upstream') {
      final full = await g.out(['rev-parse', 'HEAD']);
      return fill(full == e.pin ? 'ok' : 'offpin')
        ..behind = 0
        ..ahead = 0;
    }
    final branch = e.branch ?? '';
    final remote = 'origin/$branch';
    if (!await g.ok(['rev-parse', '-q', '--verify', 'refs/remotes/$remote'])) {
      return fill('nobranch');
    }
    final r = fill('ok')
      ..behind =
          _int(await g.out(['rev-list', '--count', 'HEAD..$remote'])) ?? 0
      ..lagAt = _int(
        (await g.out([
          'log',
          '--reverse',
          '--pretty=%ct',
          'HEAD..$remote',
        ])).split('\n').first,
      )
      ..ahead = _int(await g.out(['rev-list', '--count', '$remote..HEAD'])) ?? 0
      ..unpushedAt = _int(
        (await g.out([
          'log',
          '--reverse',
          '--pretty=%ct',
          '$remote..HEAD',
        ])).split('\n').first,
      );
    // The run worktrees (<root>/.worktrees/<run>/<path>) and whether their
    // branch is merged.
    String? wt;
    for (final line in (await g.out([
      'worktree',
      'list',
      '--porcelain',
    ])).split('\n')) {
      if (line.startsWith('worktree ')) {
        wt = line.substring('worktree '.length);
      } else if (line.startsWith('branch refs/heads/') && wt != null) {
        final b = line.substring('branch refs/heads/'.length);
        if (!wt.contains('/.worktrees/')) continue;
        final c =
            _int(await g.out(['rev-list', '--count', '$branch..$b'])) ?? 0;
        if (c > 0) {
          runBranches.add((rel: e.rel, branch: b, commits: c, worktree: wt));
        }
      }
    }
    return r;
  }

  /// The folders `<root>_old*` beside the root, with their size in KiB.
  Future<void> _oldTrees() async {
    final parent = Directory(p.dirname(set.root));
    final prefix = '${p.basename(set.root)}_old';
    final dirs = [
      for (final d in parent.listSync(followLinks: false))
        if (d is Directory && p.basename(d.path).startsWith(prefix)) d.path,
    ]..sort();
    for (final dir in dirs) {
      int? size;
      try {
        final proc = await Process.start('du', ['-sk', dir]);
        final out = proc.stdout
            .transform(const SystemEncoding().decoder)
            .join();
        unawaited(proc.stderr.drain<void>());
        final code = await proc.exitCode.timeout(
          Duration(seconds: oldTreeSeconds),
          onTimeout: () {
            proc.kill();
            return -1;
          },
        );
        if (code >= 0) size = _int((await out).split(RegExp(r'\s')).first);
      } on ProcessException {
        size = null;
      }
      oldTrees.add((path: dir, size: size));
    }
  }

  /// The probe's rows, as status_probe.sh prints them.
  List<String> rows() {
    final out = <String>[];
    for (final r in repos) {
      out.add(r.row());
      for (final b in runBranches.where((b) => b.rel == r.entry.rel)) {
        out.add(
          ['RUNBRANCH', b.rel, b.branch, '${b.commits}', b.worktree].join('\t'),
        );
      }
    }
    for (final t in oldTrees) {
      out.add(
        ['OLDTREE', t.path, t.size == null ? '?' : '${t.size}'].join('\t'),
      );
    }
    out.add('PROBED\t${repos.length}');
    return out;
  }

  Map<String, Object?> toJson() => {
    'repositories': [for (final r in repos) r.toJson()],
    'runBranches': [
      for (final b in runBranches)
        {
          'path': b.rel,
          'branch': b.branch,
          'commits': b.commits,
          'worktree': b.worktree,
        },
    ],
    'oldTrees': [
      for (final t in oldTrees) {'path': t.path, 'sizeKiB': t.size},
    ],
    'probed': repos.length,
  };
}

/// `:skill-status` (see the library comment).
class SkillStatusExecutor extends CommandExecutor {
  SkillStatusExecutor({this.out, this.now, this.gitEnvironment});

  final StringSink? out;
  final DateTime? now;
  final Map<String, String>? gitEnvironment;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.failure(
        path: context.path,
        name: context.name,
        error: ':skill-status runs over the whole tree, without the traversal',
      );

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final sink = out ?? stdout;
    final opts = args.optionsFor('skill-status');
    final json = opts['json'] == true;
    final started = now ?? DateTime.now();
    final found = await skillDiscover(
      args: args,
      command: ':skill-status',
      given: const [],
      json: json,
      sink: sink,
      started: started,
    );
    if (found.refused != null) return found.refused!;
    final run = SkillStatusRun(
      set: found.set!,
      dryRun: args.dryRun,
      now: started,
      gitEnvironment: gitEnvironment,
      oldTreeSeconds:
          int.tryParse(Platform.environment['TFS_OLD_DU_SECONDS'] ?? '') ?? 45,
    );
    await run.run();
    if (opts['rows'] == true) {
      sink.writeln(run.rows().join('\n'));
    } else if (json) {
      sink.writeln(skillJson(run.report, 'status', run.toJson()));
    } else {
      sink.writeln(run.report.renderText(verbose: args.verbose));
      for (final r in run.repos) {
        sink.writeln('  ${r.row().substring(5)}');
      }
    }
    return const ToolResult.success();
  }
}
