/// `buildkit :skill-push-binaries`: tom_binaries committed and pushed as
/// `tom_push_binaries` does (`.claude/skills/tom_push_binaries`):
///
/// 1. `git add -A`; nothing staged and nothing unpushed: nothing to do.
/// 2. One commit, `chore: refresh binaries (<platforms>) at <iso time>` (the
///    platforms of the staged paths, never the host: tom_binaries is public).
/// 3. Fetch; a clone whose history shares no commit with origin's is refused
///    (origin was recreated; rebasing would publish the old history).
/// 4. Rebase onto what the other platforms pushed; a path both sides changed
///    (the same platform built elsewhere too) is taken from this build.
/// 5. Push, never forced; when origin moved meanwhile, fetch, rebase and push
///    again, three rounds at most.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../ws/ws_common.dart';
import 'binaries_messages.dart';

/// One push of tom_binaries.
class SkillPushBinariesRun {
  SkillPushBinariesRun({
    required this.binaries,
    this.dryRun = false,
    DateTime? now,
    this.gitEnvironment,
  }) : now = now ?? DateTime.now();

  final String binaries;
  final bool dryRun;
  final DateTime now;
  final Map<String, String>? gitEnvironment;
  late final RunReport report;

  /// `pushed`, `would push` (dry run), `no-op`, `not cloned` or `failed`.
  String outcome = 'failed';

  WsGit get _g => WsGit(binaries, gitEnvironment);

  String get _iso {
    final t = now.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:'
        '${two(t.minute)}:${two(t.second)}Z';
  }

  Future<RunReport> run() async {
    report = RunReport(
      tool: 'buildkit',
      command: ':skill-push-binaries',
      root: binaries,
      host: Platform.localHostname,
      started: now,
      given: const [],
      names: RepoNames(const ['']),
    );
    if (!Directory(p.join(binaries, '.git')).existsSync()) {
      // As tom_push_binaries: a host without the clone has nothing to push.
      outcome = 'not cloned';
      return report;
    }
    report.lookedAt.add('');
    final g = _g;
    var branch = (await g.out([
      'symbolic-ref',
      '--short',
      'refs/remotes/origin/HEAD',
    ])).replaceFirst('origin/', '');
    if (branch.isEmpty) branch = 'main';

    // 1. Stage; nothing to do?
    if (dryRun) {
      final status = await g.out(['status', '--porcelain']);
      final unpushed = await g.out(['rev-list', '@{u}..']);
      if (status.isEmpty && unpushed.isEmpty) {
        outcome = 'no-op';
        return report;
      }
      report.changed(
        ReportDone('', [
          if (status.isNotEmpty)
            'would commit ${status.split('\n').length} path(s)',
          'would fetch, rebase onto origin/$branch and push',
        ]),
      );
      outcome = 'would push';
      return report;
    }
    await g.run(['add', '-A']);
    final staged = await g.out(['diff', '--cached', '--name-only']);
    if (staged.isEmpty) {
      if ((await g.out(['rev-list', '@{u}..'])).isEmpty) {
        outcome = 'no-op';
        return report;
      }
    } else {
      // 2. One commit, named by the platforms.
      final platforms = <String>{
        for (final f in staged.split('\n'))
          if (f.split('/').length > 2 &&
              (f.startsWith('tom/') || f.startsWith('sqlite_vec/')))
            f.split('/')[1],
      }.toList()..sort();
      final msg =
          'chore: refresh binaries (${platforms.isEmpty ? 'other files' : platforms.join(',')}) at $_iso';
      final c = await g.run(['commit', '-q', '-m', msg]);
      if (c.exitCode != 0) {
        return _fail('The commit failed: ${WsGit.text(c)}');
      }
      report.changed(
        ReportDone('', [
          'committed ${staged.split('\n').length} path(s): $msg',
        ], files: staged.split('\n')),
      );
    }

    // 3.-5. Fetch, rebase, push; three rounds.
    for (var round = 1; round <= 3; round++) {
      final f = await g.run(['fetch', '-q', 'origin', branch]);
      if (f.exitCode != 0) return _fail('git fetch failed: ${WsGit.text(f)}');
      final remote = 'origin/$branch';
      if (await g.hasRef('HEAD') &&
          !await g.ok(['merge-base', 'HEAD', remote])) {
        outcome = 'failed';
        report.add(
          binUnrelated.raise(
            finding:
                "HEAD shares no commit with $remote (origin's history was "
                'replaced).',
            evidence: [
              ReportEvidence('commands', [
                "rm -rf '$binaries' && git -C '${p.dirname(binaries)}' clone "
                    '${await g.originUrl()}',
              ], label: 'Fresh clone:'),
            ],
            state: 'Nothing was pushed; the build is committed here.',
          ),
        );
        return report;
      }
      final behind =
          int.tryParse(await g.out(['rev-list', '--count', 'HEAD..$remote'])) ??
          0;
      if (behind > 0 && !await _rebase(g, remote)) {
        return _fail(
          'The rebase onto $remote could not be completed; aborted.',
        );
      }
      final push = await g.run(['push', '-q', 'origin', branch]);
      if (push.exitCode == 0) {
        outcome = 'pushed';
        report.changed(
          ReportDone('', [
            'pushed to origin/$branch'
                '${behind > 0 ? ' (rebased onto $behind commit(s) of other platforms)' : ''}',
          ]),
        );
        return report;
      }
    }
    return _fail(
      'The push was still rejected after 3 rounds of fetch and rebase.',
    );
  }

  /// Rebases onto [remote]; a path both sides changed is taken from this
  /// build ("theirs" during a rebase is the commit replayed).
  Future<bool> _rebase(WsGit g, String remote) async {
    if (await g.ok(['rebase', '-q', remote])) return true;
    for (var guard = 0; guard < 50; guard++) {
      if (!await _rebasing(g)) break;
      final conflicts = (await g.out([
        'diff',
        '--name-only',
        '--diff-filter=U',
      ])).split('\n').where((f) => f.isNotEmpty);
      for (final f in conflicts) {
        if (await g.ok(['cat-file', '-e', ':3:$f'])) {
          await g.run(['checkout', '-q', '--theirs', '--', f]);
          await g.run(['add', '--', f]);
        } else {
          await g.run(['rm', '-q', '--cached', '--', f]);
          final file = File(p.join(binaries, f));
          if (file.existsSync()) file.deleteSync();
        }
      }
      final cont = await Process.run(
        'git',
        ['rebase', '--continue'],
        workingDirectory: binaries,
        environment: {...?gitEnvironment, 'GIT_EDITOR': 'true'},
      );
      if (cont.exitCode == 0 && !await _rebasing(g)) return true;
    }
    if (await _rebasing(g)) {
      await g.run(['rebase', '--abort']);
      return false;
    }
    return true;
  }

  Future<bool> _rebasing(WsGit g) async =>
      (await wsOperationInProgress(g)) == 'a rebase';

  RunReport _fail(String why) {
    outcome = 'failed';
    report.add(
      binPushFailed.raise(
        finding: why,
        state: 'Nothing was forced; what is committed stays here.',
      ),
    );
    return report;
  }
}
