/// `buildkit :ws-update`: this machine brought up to the remote, nothing
/// pushed (buildkit_ws_commands.md § 1.4).
///
/// 1. Checks before anything changes (exit 2): no or an invalid repos.yaml
///    (`ws-manifest`), an unregistered merge driver (`ws-driver`), a
///    repository mid-merge / mid-rebase (`ws-in-progress`).
/// 2. The root first: fetch and merge (it holds repos.yaml), then repos.yaml
///    is read again.
/// 3. Missing entries for this host are cloned (an upstream at its pin;
///    `ws-clone-failed`); a changed origin URL is re-pointed; a moved entry
///    (its URL checked out at another path) is moved when clean and fully
///    pushed, else `ws-move-blocked`.
/// 4. Every repository of the set: put on its branch (`ws-off-branch`,
///    `ws-detached`), fetched, `origin/<branch>` merged. Forks only
///    fast-forward (`ws-fork-diverged`, `--merge-fork`); upstreams go to
///    their pin (a dirty one is left alone: `ws-upstream-dirty`);
///    `tom_binaries` takes the remote (latest wins). Uncommitted files the
///    merge would overwrite hold the repository (`ws-held`: `--commit-first`,
///    `--stash-merge`); otherwise the merge goes through with them in place.
///    A conflict: `ws-conflict` (`--merge-branch`, `--ours`, `--theirs`,
///    `--leave-conflict`).
/// 5. The parents' generated ignore blocks are written (as wssetup); unknown
///    clones are reported (`ws-unknown-seen`, `--include-unknown`).
///
/// Nothing is pushed but what an option given for a repository pushes: a
/// `--rescue-detached` or `--merge-branch` branch `ws-push/<host>/<stamp>`,
/// and the branch a `--push-current` repository is on.
///
/// Exit 0 when every repository of the set is at or ahead of
/// `origin/<branch>` (forks and upstreams by their rules); 1 when one needs
/// you; 2 refused.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../../wssetup/wssetup.dart' show wssetupIgnoreBlocks;
import 'ws_common.dart';
import 'ws_messages.dart';

/// The options of `:ws-update` that take repositories.
const wsUpdateRepoOptions = [
  'skip',
  'include-unknown',
  'rescue-detached',
  'push-current',
  'to-branch',
  'set-branch',
  'merge-fork',
  'commit-first',
  'stash-merge',
  'merge-branch',
  'ours',
  'theirs',
  'leave-conflict',
];

/// The options of a run, as given.
class WsUpdateOptions {
  WsUpdateOptions({
    this.message,
    this.dryRun = false,
    this.verbose = false,
    this.json = false,
    this.repoLists = const {},
  });

  /// The message of a `--commit-first` / `--to-branch` commit.
  final String? message;
  final bool dryRun;
  final bool verbose;
  final bool json;
  final Map<String, String> repoLists;

  /// The command line as typed (no `-n`).
  List<String> get given => [
    if (message != null) ...['-m', message!],
    for (final e in repoLists.entries) ...['--${e.key}', e.value],
  ];
}

/// Reads the run's options from [opts] (`args.optionsFor('ws-update')`).
WsUpdateOptions wsUpdateOptions(Map<String, dynamic> opts, CliArgs args) {
  List<String> list(Object? v) => [
    for (final x in switch (v) {
      final List<dynamic> l => l,
      final String s => [s],
      _ => const <dynamic>[],
    })
      '$x',
  ];
  return WsUpdateOptions(
    message: opts['message'] as String?,
    dryRun: args.dryRun,
    verbose: args.verbose,
    json: opts['json'] == true,
    repoLists: {
      for (final name in wsUpdateRepoOptions)
        if (list(opts[name]).isNotEmpty) name: list(opts[name]).join(','),
    },
  );
}

/// One `:ws-update` run over the tree of [set].
class WsUpdateRun {
  WsUpdateRun({
    required this.set,
    required this.options,
    DateTime? now,
    this.gitEnvironment,
  }) : now = now ?? DateTime.now();

  /// The set; read again after the root's merge and after the clones.
  RepoSet set;
  final WsUpdateOptions options;
  final DateTime now;
  final Map<String, String>? gitEnvironment;

  late final RunReport report;
  late RepoNames _names;
  late RepoSelections _sel;
  var _leftOut = false;
  final _unresolved = <String>{};
  final _fetchFailed = <String>{};

  String get _host => set.host;
  bool get _dry => options.dryRun;
  WsGit _git(String dir) => WsGit(dir, gitEnvironment);

  /// The run's exit code.
  int get exitCode {
    final code = report.exitCode;
    if (code < ReportExitCode.needsYou &&
        (_leftOut || _unresolved.isNotEmpty)) {
      return ReportExitCode.needsYou;
    }
    return code;
  }

  String get _message =>
      options.message ?? 'ws-update on $_host at ${wsIsoMinute(now)}';

  bool _taken(RepoSetMember m) =>
      m.repoClass != RepoClass.unmanaged && m.repoClass != RepoClass.toolOwned;

  void _resolveNames() {
    _names = RepoNames([
      for (final m in set.members)
        if (_taken(m)) m.relPath,
    ]);
    _sel = RepoSelections({
      for (final e in options.repoLists.entries)
        e.key: _names.resolve(e.value).toSet(),
    });
  }

  bool _skipped(String rel) => _sel.applies('skip', rel);

  /// Whether the run updates [m]: a member of the git set, or an unknown
  /// clone named by `--include-unknown`.
  bool _takes(RepoSetMember m) =>
      m.inGitSet ||
      (m.repoClass == RepoClass.unknown &&
          _sel.applies('include-unknown', m.relPath));

  /// Runs it; [RepoNameException] for an unknown or ambiguous name.
  Future<RunReport> run() async {
    _resolveNames();
    report = RunReport(
      tool: 'buildkit',
      command: ':ws-update',
      root: set.root,
      host: _host,
      started: now,
      given: options.given,
      names: _LiveNames(() => _names),
    );
    if (options.repoLists.containsKey('skip')) _leftOut = true;

    // 1. Checks before anything changes.
    final onDisk = [
      for (final m in set.members)
        if (m.onDisk && m.inGitSet && !_skipped(m.relPath)) m,
    ];
    final checks =
        <
          RepoSetMember,
          ({String? op, List<({String driver, String file})> drivers})
        >{};
    await wsPool(onDisk, (m) async {
      final g = _git(m.path);
      checks[m] = (
        op: await wsOperationInProgress(g),
        drivers: await wsMissingDrivers(g),
      );
    });
    for (final m in onDisk) {
      final c = checks[m]!;
      if (c.op != null) {
        final conflicted = [
          for (final ch in await _git(m.path).changes())
            if (ch.conflicted) '${ch.path}  (conflicted)',
        ];
        report.add(
          wsInProgress.raise(
            repository: m.relPath,
            finding: 'The repository is in the middle of ${c.op}.',
            evidence: [ReportEvidence('files', conflicted)],
            state: 'Nothing was changed.',
          ),
        );
      }
      for (final d in c.drivers) {
        report.add(
          wsDriver.raise(
            repository: m.relPath,
            finding:
                'merge=${d.driver} is named in ${d.file}, but '
                'merge.${d.driver}.driver is not configured.',
            state: 'Nothing was changed.',
          ),
        );
      }
    }
    if (report.messages.any((m) => m.level == MessageLevel.refusal)) {
      return report;
    }

    // 2. The root first, then repos.yaml again.
    final root = set.members.where((m) => m.isRoot && m.onDisk).firstOrNull;
    final done = <String>{};
    if (root != null && !_skipped('')) {
      if (!_dry) await _fetch(root);
      await _update(root);
      done.add('');
      if (!_dry) {
        try {
          set = RepoSet.load(
            root: set.root,
            manifestPath: set.manifestPath,
            host: _host,
          );
          _resolveNames();
        } on ReposManifestException catch (e) {
          report.add(
            wsManifest.raise(
              finding: 'After the root\'s merge: $e',
              state: 'The root was merged; nothing else was changed.',
            ),
          );
          return report;
        }
      }
    }

    // 3. Missing entries, moved entries, changed origins.
    await _placeEntries();
    if (!_dry) {
      set = RepoSet.load(
        root: set.root,
        manifestPath: set.manifestPath,
        host: _host,
      );
      _resolveNames();
    }

    // 4. Every repository of the set, parents first; an unknown clone
    // named by --include-unknown is updated like an entry.
    final rest = [
      for (final m in set.members)
        if (m.onDisk &&
            !done.contains(m.relPath) &&
            !_skipped(m.relPath) &&
            (_takes(m) || m.kind == RepoKind.upstream))
          m,
    ];
    report.lookedAt.addAll([
      for (final m in set.members)
        if (m.onDisk && _takes(m)) m.relPath,
    ]);
    if (!_dry) {
      await wsPool([
        for (final m in rest)
          if (m.kind != RepoKind.upstream) m,
      ], _fetch);
    }
    for (final m in rest) {
      if (m.kind == RepoKind.upstream) {
        await _toPin(m);
      } else {
        await _update(m);
      }
    }

    // 5. The ignore blocks; the unknown clones.
    final blocks = wssetupIgnoreBlocks(
      set.manifest,
      set.root,
      reduced: File(p.join(set.root, '.gitmodules')).existsSync(),
      dryRun: _dry,
    );
    final written = [
      for (final b in blocks)
        if (b.status == 'block written' || b.status == 'would write block') b,
    ];
    if (written.isNotEmpty) {
      report.changed(
        ReportDone('', [
          for (final b in written)
            '${_dry ? 'would write' : 'wrote'} the ignore block of ${b.path}',
        ]),
      );
    }
    final unknown = [
      for (final m in set.members)
        if (m.repoClass == RepoClass.unknown &&
            !_sel.applies('include-unknown', m.relPath))
          m.relPath,
    ];
    for (final rel in unknown) {
      report.add(
        wsUnknownSeen.raise(
          repository: rel,
          finding: 'A clone on disk that repos.yaml does not list:',
          evidence: [
            ReportEvidence('paths', [rel]),
          ],
          state: 'Left alone; :ws-repo-cleanup reports and removes it.',
        ),
      );
    }

    if (!_dry) await _finalCheck();
    return report;
  }

  Future<void> _fetch(RepoSetMember m) async {
    final r = await _git(m.path).run(['fetch', '--quiet', 'origin']);
    if (r.exitCode == 0) return;
    _fetchFailed.add(m.relPath);
    _unresolved.add(m.relPath);
    final remote = await _git(m.path).originUrl();
    report.add(
      wsFetchFailed.raise(
        repository: m.relPath,
        finding: 'git fetch origin failed:',
        evidence: [
          ReportEvidence('remote', [remote], label: 'Remote:'),
          ReportEvidence('git', [WsGit.text(r)], label: 'Git:'),
        ],
        state: 'Nothing was merged for it.',
      ),
    );
  }

  /// Clones the missing entries of this host, moves the moved ones,
  /// re-points changed origins.
  Future<void> _placeEntries() async {
    final unknownByUrl = <String, RepoSetMember>{};
    for (final m in set.members) {
      if (m.repoClass != RepoClass.unknown) continue;
      final url = await _git(m.path).originUrl();
      if (url.isNotEmpty) unknownByUrl[url] = m;
    }
    for (final m in set.members) {
      if (_skipped(m.relPath)) continue;
      final entry = m.entry;
      if (entry == null) continue;
      if (m.repoClass == RepoClass.missing) {
        if (entry.kind == RepoKind.ai) continue; // linked by the fleet skill
        final moved = unknownByUrl.entries
            .where((e) => wsSameUrl(e.key, entry.url))
            .map((e) => e.value)
            .firstOrNull;
        if (moved != null) {
          await _move(moved, m);
        } else {
          await _clone(m);
        }
        continue;
      }
      if (m.repoClass != RepoClass.entry || !m.onDisk) continue;
      final g = _git(m.path);
      final url = await g.originUrl();
      if (url.isNotEmpty && !wsSameUrl(url, entry.url)) {
        if (!_dry) await g.run(['remote', 'set-url', 'origin', entry.url]);
        report.changed(
          ReportDone(m.relPath, [
            '${_dry ? 'would re-point' : 're-pointed'} origin from $url to ${entry.url}',
          ]),
        );
      }
    }
  }

  Future<void> _clone(RepoSetMember m) async {
    final entry = m.entry!;
    final label = entry.kind == RepoKind.upstream
        ? 'at its pin ${entry.pin!.substring(0, 7)}'
        : 'on ${entry.branch}';
    if (_dry) {
      report.changed(ReportDone(m.relPath, ['would clone $label']));
      return;
    }
    Directory(p.dirname(m.path)).createSync(recursive: true);
    final parent = _git(p.dirname(m.path));
    final ProcessResult r;
    if (entry.kind == RepoKind.upstream) {
      r = await parent.run(['clone', '-q', '--no-checkout', entry.url, m.path]);
      if (r.exitCode == 0) {
        final co = await _git(
          m.path,
        ).run(['checkout', '-q', '--detach', entry.pin!]);
        if (co.exitCode != 0) return _cloneFailed(m, co);
      }
    } else {
      r = await parent.run([
        'clone',
        '-q',
        '-b',
        entry.branch!,
        entry.url,
        m.path,
      ]);
    }
    if (r.exitCode != 0) return _cloneFailed(m, r);
    report.changed(ReportDone(m.relPath, ['cloned $label']));
  }

  void _cloneFailed(RepoSetMember m, ProcessResult r) {
    _unresolved.add(m.relPath);
    report.add(
      wsCloneFailed.raise(
        repository: m.relPath,
        finding: 'git clone failed:',
        evidence: [
          ReportEvidence('url', [m.entry!.url], label: 'URL:'),
          ReportEvidence('target', [m.path], label: 'Target:'),
          ReportEvidence('git', [WsGit.text(r)], label: 'Git:'),
        ],
        state: 'Nothing was written at the target.',
      ),
    );
  }

  /// Moves the checkout [from] (an unknown clone with the entry's URL) to
  /// [to], when nothing would be lost.
  Future<void> _move(RepoSetMember from, RepoSetMember to) async {
    final g = _git(from.path);
    final dirty = await g.changes();
    final unpushed = await g.log('--branches --not --remotes');
    if (dirty.isNotEmpty || unpushed.isNotEmpty) {
      _unresolved.add(to.relPath);
      report.add(
        wsMoveBlocked.raise(
          repository: to.relPath,
          finding:
              'repos.yaml moved this entry from ${from.relPath}; the old '
              'checkout cannot move yet:',
          evidence: [
            ReportEvidence('paths', [
              '${from.relPath} -> ${to.relPath}',
            ], label: 'Move:'),
            if (dirty.isNotEmpty)
              ReportEvidence('files', [
                for (final c in dirty.take(10)) '${c.code} ${c.path}',
              ], label: 'Uncommitted:'),
            if (unpushed.isNotEmpty)
              ReportEvidence('commits', unpushed, label: 'Unpushed:'),
          ],
          state: 'Both paths are as they were.',
        ),
      );
      return;
    }
    if (!_dry) {
      Directory(p.dirname(to.path)).createSync(recursive: true);
      Directory(from.path).renameSync(to.path);
    }
    report.changed(
      ReportDone(to.relPath, [
        '${_dry ? 'would move' : 'moved'} from ${from.relPath}',
      ]),
    );
  }

  /// An upstream to its pin; a dirty one is left alone.
  Future<void> _toPin(RepoSetMember m) async {
    final g = _git(m.path);
    final dirty = await g.changes();
    final head = await g.out(['rev-parse', 'HEAD']);
    if (dirty.isNotEmpty) {
      report.add(
        wsUpstreamDirty.raise(
          repository: m.relPath,
          finding:
              '${dirty.length} local change(s); left alone'
              '${head == m.pin ? '' : ', off its pin ${m.pin!.substring(0, 7)} (at ${head.isEmpty ? '?' : head.substring(0, 7)})'}:',
          evidence: [
            ReportEvidence('files', [
              for (final c in dirty.take(10)) '${c.code} ${c.path}',
            ]),
          ],
        ),
      );
      return;
    }
    if (head == m.pin) return;
    if (_dry) {
      report.changed(
        ReportDone(m.relPath, [
          'would put at its pin ${m.pin!.substring(0, 7)}',
        ]),
      );
      return;
    }
    if (!await g.hasRef('${m.pin}^{commit}')) {
      await g.run(['fetch', '--quiet', 'origin']);
    }
    final co = await g.run(['checkout', '-q', '--detach', m.pin!]);
    if (co.exitCode != 0) {
      _unresolved.add(m.relPath);
      report.add(
        wsFetchFailed.raise(
          repository: m.relPath,
          finding: 'The pin ${m.pin} is not on origin:',
          evidence: [
            ReportEvidence('git', [WsGit.text(co)], label: 'Git:'),
          ],
          state: 'Left at ${head.substring(0, 7)}.',
        ),
      );
      return;
    }
    report.changed(
      ReportDone(m.relPath, ['put at its pin ${m.pin!.substring(0, 7)}']),
    );
  }

  /// One repository: on its branch, then `origin/<branch>` merged.
  Future<void> _update(RepoSetMember m) async {
    if (_fetchFailed.contains(m.relPath)) return;
    final g = _git(m.path);
    final actions = <String>[];
    void done() {
      if (actions.isNotEmpty) report.changed(ReportDone(m.relPath, actions));
    }

    var expected = m.expectedBranch;
    var pushCurrent = false;
    final current = await g.out(['symbolic-ref', '--short', '-q', 'HEAD']);
    var branch = current.isEmpty ? null : current;

    // A detached HEAD.
    if (branch == null) {
      final back =
          expected != null &&
          await g.hasRef('refs/heads/$expected') &&
          (await g.contains('HEAD', 'refs/heads/$expected') ||
              (await g.hasRef('refs/remotes/origin/$expected') &&
                  await g.contains('HEAD', 'refs/remotes/origin/$expected')));
      if (back) {
        if (!_dry) {
          final s = await g.run(['switch', '-q', expected]);
          if (s.exitCode != 0) return _detached(m, g, expected, WsGit.text(s));
        }
        actions.add('${_dry ? 'would put' : 'put'} back on $expected');
        branch = expected;
      } else if (_sel.applies('rescue-detached', m.relPath)) {
        final rescue = wsRescueBranch(_host, now);
        if (!_dry) {
          await g.run(['switch', '-q', '-c', rescue]);
          await g.run(['add', '-A']);
          if (!await g.ok(['diff', '--cached', '--quiet'])) {
            await g.run(['commit', '-q', '-m', _message]);
          }
          await g.run(['push', '-q', '--set-upstream', 'origin', rescue]);
          if (expected != null && await g.hasRef('refs/heads/$expected')) {
            await g.run(['switch', '-q', expected]);
          }
        }
        actions.add(
          '${_dry ? 'would rescue' : 'rescued'} the detached commits to $rescue',
        );
        branch = expected;
      } else {
        return _detached(m, g, expected, null);
      }
    }
    if (branch == null) {
      done();
      return;
    }

    // Off its branch.
    if (expected != null && branch != expected) {
      if (_sel.applies('push-current', m.relPath)) {
        // This run only: the branch it is on, brought up to its origin and
        // pushed; repos.yaml keeps the expected branch.
        expected = branch;
        pushCurrent = true;
      } else if (_sel.applies('to-branch', m.relPath)) {
        if (!_dry) {
          await g.run(['add', '-A']);
          if (!await g.ok(['diff', '--cached', '--quiet'])) {
            await g.run(['commit', '-q', '-m', _message]);
          }
          final sw = await g.run(['switch', '-q', expected]);
          if (sw.exitCode != 0) {
            _unresolved.add(m.relPath);
            report.add(
              _offBranch(
                m,
                branch,
                expected,
                'switching failed: ${WsGit.text(sw)}',
              ),
            );
            done();
            return;
          }
          final mg = await g.run(['merge', '--no-edit', branch]);
          if (mg.exitCode != 0) {
            await g.run(['merge', '--abort']);
            _unresolved.add(m.relPath);
            report.add(
              _offBranch(
                m,
                branch,
                expected,
                'merging $branch into $expected conflicts; aborted',
              ),
            );
            done();
            return;
          }
        }
        actions.add(
          '${_dry ? 'would merge' : 'merged'} $branch into $expected (not pushed)',
        );
        branch = expected;
      } else if (_sel.applies('set-branch', m.relPath)) {
        if (!_dry) _setBranch(m.relPath, branch);
        actions.add(
          '${_dry ? 'would record' : 'recorded'} $branch as its branch in repos.yaml',
        );
        expected = branch;
      } else {
        _unresolved.add(m.relPath);
        report.add(
          _offBranch(
            m,
            branch,
            expected,
            null,
            commits: await g.log('$expected..$branch'),
          ),
        );
        return;
      }
    }

    final remote = 'refs/remotes/origin/${expected ?? branch}';
    if (!await g.hasRef(remote) || await g.contains(remote, 'HEAD')) {
      if (pushCurrent) await _pushCurrent(m, g, branch, remote, actions);
      done();
      return;
    }
    final incoming = await g.log('HEAD..$remote', max: 1000);

    // A fork only fast-forwards.
    final isFork = m.kind == RepoKind.fork;
    if (isFork &&
        !_sel.applies('merge-fork', m.relPath) &&
        !await g.contains('HEAD', remote)) {
      final ahead = await g.out(['rev-list', '--count', '$remote..HEAD']);
      _unresolved.add(m.relPath);
      report.add(
        wsForkDiverged.raise(
          repository: m.relPath,
          branch: branch,
          finding:
              'The fork is $ahead commit(s) ahead of and ${incoming.length} '
              'behind origin/$branch; it cannot fast-forward.',
          evidence: [
            ReportEvidence(
              'commits',
              await g.log('$remote..HEAD'),
              label: 'Local:',
            ),
          ],
          state: 'Nothing was changed.',
          explanations: {
            'merge-fork':
                'Merge origin/$branch into it like a code repository (a merge commit).',
          },
        ),
      );
      done();
      return;
    }

    // Uncommitted files the merge would overwrite: held.
    final base = await g.out(['merge-base', 'HEAD', remote]);
    final changedThere = (await g.out([
      'diff',
      '--name-only',
      base,
      remote,
    ])).split('\n').where((l) => l.isNotEmpty).toSet();
    final dirty = await g.changes();
    final overlap = [
      for (final c in dirty)
        if (changedThere.contains(c.path)) c.path,
    ];
    var stashed = false;
    if (overlap.isNotEmpty) {
      if (_sel.applies('commit-first', m.relPath)) {
        if (!_dry) {
          await g.run(['add', '-A']);
          await g.run(['commit', '-q', '-m', _message]);
        }
        actions.add(
          '${_dry ? 'would commit' : 'committed'} ${dirty.length} file(s) first (not pushed)',
        );
      } else if (_sel.applies('stash-merge', m.relPath)) {
        if (!_dry) {
          await g.run([
            'stash',
            'push',
            '-q',
            '--include-untracked',
            '-m',
            'ws-update ${wsIsoMinute(now)}',
          ]);
          stashed = true;
        }
      } else {
        _unresolved.add(m.relPath);
        report.add(
          wsHeld.raise(
            repository: m.relPath,
            branch: branch,
            finding:
                '${overlap.length} uncommitted file(s) that the merge of '
                'origin/$branch would overwrite:',
            evidence: [
              ReportEvidence('files', overlap),
              ReportEvidence(
                'commits',
                await g.log('HEAD..$remote -- ${overlap.join(' ')}'),
                label: 'Incoming:',
              ),
            ],
            state:
                'The repository was held: not merged, your files as they were.',
            explanations: {
              'commit-first':
                  'Commit them (with -m, or "$_message"), then merge.\n'
                  'The commit is not pushed; :ws-push pushes it later.',
            },
          ),
        );
        done();
        return;
      }
    }

    if (_dry) {
      actions.add(
        '${isFork && !_sel.applies('merge-fork', m.relPath) ? 'would fast-forward' : 'would merge'} '
        '${incoming.length} incoming commit(s)${stashed ? '' : ''}',
      );
      if (_sel.applies('stash-merge', m.relPath) && overlap.isNotEmpty) {
        actions.add('would stash and restore ${dirty.length} file(s)');
      }
      if (pushCurrent) actions.add('would push $branch');
      done();
      return;
    }

    // tom_binaries: the remote wins.
    final side = m.kind == RepoKind.binaries
        ? 'theirs'
        : _sel.applies('ours', m.relPath)
        ? 'ours'
        : _sel.applies('theirs', m.relPath)
        ? 'theirs'
        : null;
    final ffOnly = isFork && !_sel.applies('merge-fork', m.relPath);
    final merge = await g.run([
      'merge',
      if (ffOnly) '--ff-only' else '--no-edit',
      if (!ffOnly && side != null) ...['-X', side],
      remote,
    ]);
    if (merge.exitCode == 0) {
      actions.add(
        '${ffOnly ? 'fast-forwarded' : 'merged'} ${incoming.length} incoming commit(s)'
        '${side == null ? '' : ' (-X $side)'}',
      );
      if (pushCurrent) await _pushCurrent(m, g, branch, remote, actions);
      if (stashed) {
        final pop = await g.run(['stash', 'pop', '-q']);
        if (pop.exitCode != 0) {
          _unresolved.add(m.relPath);
          report.add(
            wsHeld.raise(
              repository: m.relPath,
              branch: branch,
              finding: 'Merged; putting your stashed files back conflicts:',
              evidence: [
                ReportEvidence('git', [WsGit.text(pop)], label: 'Git:'),
              ],
              state:
                  'Your files stay in the stash (git stash list); resolve the '
                  'working tree, then git stash drop.',
              offer: const [],
            ),
          );
        } else {
          actions.add('stashed and restored ${dirty.length} file(s)');
        }
      }
      done();
      return;
    }

    // A conflict.
    final conflicted = (await g.out([
      'diff',
      '--name-only',
      '--diff-filter=U',
    ])).split('\n').where((l) => l.isNotEmpty).toList();
    final local = await g.log('$remote..HEAD');
    final localCount =
        int.tryParse(await g.out(['rev-list', '--count', '$remote..HEAD'])) ??
        local.length;
    final evidence = [
      ReportEvidence('files', [for (final f in conflicted) '$f  both changed']),
      ReportEvidence('local', local, label: 'Local:'),
      ReportEvidence('incoming', [
        '${incoming.length} commit(s)',
      ], label: 'Incoming:'),
    ];
    if (_sel.applies('merge-branch', m.relPath) &&
        !_sel.applies('leave-conflict', m.relPath)) {
      await g.run(['merge', '--abort']);
      if (stashed) await g.run(['stash', 'pop', '-q']);
      await _mergeBranch(m, g, branch, remote, localCount, actions);
      done();
      return;
    }
    _unresolved.add(m.relPath);
    if (_sel.applies('leave-conflict', m.relPath)) {
      report.add(
        wsConflict.raise(
          repository: m.relPath,
          branch: branch,
          finding:
              'The merge of origin/$branch conflicts; it is left in the working tree:',
          evidence: evidence,
          state: 'Resolve the files and commit; :ws-update pushes nothing.',
          offer: const [],
        ),
      );
    } else {
      await g.run(['merge', '--abort']);
      if (stashed) await g.run(['stash', 'pop', '-q']);
      report.add(
        wsConflict.raise(
          repository: m.relPath,
          branch: branch,
          finding:
              'Your $localCount local commit(s) and ${incoming.length} '
              'incoming commit(s) change the same lines:',
          evidence: evidence,
          state: 'The merge was aborted; the repository is as it was.',
          offer: const [
            'merge-branch',
            'ours',
            'theirs',
            'leave-conflict',
            'skip',
          ],
          explanations: {
            'merge-branch':
                'Push your $localCount local commit(s) to ${wsRescueBranch(_host, now)},\n'
                'then put $branch on origin/$branch (your uncommitted files stay).\n'
                'Merge the branch later.',
            'ours':
                'Merge again; where both sides changed a line, yours wins.\n'
                'The incoming change on those lines is lost (it stays in the history).',
            'theirs':
                'Merge again; where both sides changed a line, the incoming one wins.\n'
                'Your change on those lines is lost (it stays in your commit).',
            'leave-conflict':
                'Merge again and stop with the conflict in the working tree\n'
                'for you to resolve by hand; then commit.',
          },
        ),
      );
    }
    done();
  }

  /// `--push-current`: pushes [branch] when origin lacks its commits.
  Future<void> _pushCurrent(
    RepoSetMember m,
    WsGit g,
    String branch,
    String remote,
    List<String> actions,
  ) async {
    if (await g.hasRef(remote) && await g.contains('HEAD', remote)) return;
    if (_dry) {
      actions.add('would push $branch');
      return;
    }
    final push = await g.run([
      'push',
      '-q',
      '--set-upstream',
      'origin',
      branch,
    ]);
    if (push.exitCode == 0) {
      actions.add('pushed $branch');
      return;
    }
    _unresolved.add(m.relPath);
    report.add(_pushRejected(m, branch, push));
  }

  /// `--merge-branch` on a conflict: the local commits pushed to the rescue
  /// branch, then [branch] put on [remote] (`git reset --keep`: uncommitted
  /// files stay, and one the move would overwrite stops it).
  Future<void> _mergeBranch(
    RepoSetMember m,
    WsGit g,
    String branch,
    String remote,
    int localCount,
    List<String> actions,
  ) async {
    final rescue = wsRescueBranch(_host, now);
    final push = await g.run([
      'push',
      '-q',
      'origin',
      'HEAD:refs/heads/$rescue',
    ]);
    if (push.exitCode != 0) {
      _unresolved.add(m.relPath);
      report.add(_pushRejected(m, rescue, push));
      return;
    }
    actions.add(
      'pushed $localCount local commit(s) to $rescue (merge it later)',
    );
    final reset = await g.run(['reset', '-q', '--keep', remote]);
    if (reset.exitCode == 0) {
      actions.add('put $branch on origin/$branch');
      return;
    }
    _unresolved.add(m.relPath);
    report.add(
      wsConflict.raise(
        repository: m.relPath,
        branch: branch,
        finding:
            'Your commits are on $rescue; putting $branch on origin/$branch '
            'would overwrite uncommitted files:',
        evidence: [
          ReportEvidence('git', [WsGit.text(reset)], label: 'Git:'),
        ],
        state:
            '$branch stays at your commits; commit or move the files, then '
            'git reset --keep origin/$branch.',
        offer: const ['skip'],
      ),
    );
  }

  ReportMessage _pushRejected(
    RepoSetMember m,
    String branch,
    ProcessResult push,
  ) => wsPushRejected.raise(
    repository: m.relPath,
    branch: branch,
    finding: 'The push of $branch fails:',
    evidence: [
      ReportEvidence('git', [WsGit.text(push)], label: 'Git:'),
    ],
    state: 'Your commits are safe on this machine; nothing was forced.',
    offer: const ['skip'],
  );

  Future<void> _detached(
    RepoSetMember m,
    WsGit g,
    String? expected,
    String? why,
  ) async {
    _unresolved.add(m.relPath);
    final lost = await g.log('HEAD --not --branches --remotes');
    final head = await g.out(['rev-parse', '--short', 'HEAD']);
    final rescue = wsRescueBranch(_host, now);
    report.add(
      wsDetached.raise(
        repository: m.relPath,
        finding:
            'Detached at $head${expected == null ? '' : ', expected on $expected'}'
            '${why == null ? '' : ' ($why)'}; ${lost.length} commit(s) on no branch:',
        evidence: [ReportEvidence('commits', lost)],
        state: 'Nothing was merged for it.',
        explanations: {
          'rescue-detached':
              'Put them (and the uncommitted work) on $rescue, push it,\n'
              'and return the repository to ${expected ?? 'its branch'}.',
        },
      ),
    );
  }

  ReportMessage _offBranch(
    RepoSetMember m,
    String branch,
    String expected,
    String? why, {
    List<String> commits = const [],
  }) {
    final from = m.repoClass == RepoClass.questClone
        ? '_ai/quests.yaml'
        : 'repos.yaml';
    return wsOffBranch.raise(
      repository: m.relPath,
      branch: branch,
      finding:
          'On $branch; $from expects $expected${why == null ? '' : ' ($why)'}.'
          '${commits.isEmpty ? '' : ' Commits on $branch that $expected lacks:'}',
      evidence: [if (commits.isNotEmpty) ReportEvidence('commits', commits)],
      state: 'Nothing was merged for it.',
      offer: const ['push-current', 'to-branch', 'set-branch', 'skip'],
      explanations: {
        'push-current':
            'Bring $branch up to origin/$branch and push it there, this run\n'
            'only ($expected stays the recorded branch; nothing is committed).',
        'to-branch':
            'Commit the uncommitted files on $branch (-m), switch to\n'
            '$expected, merge $branch into it, then bring it up to\n'
            'origin/$expected. Nothing is pushed.',
        'set-branch':
            "Record $branch as the entry's branch: in repos.yaml, then\n"
            'bring it up to origin/$branch.',
      },
    );
  }

  void _setBranch(String rel, String branch) {
    final file = File(set.manifestPath);
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.contains('path: $rel,') && !line.contains('path: $rel}')) {
        continue;
      }
      lines[i] = line.replaceFirst(
        RegExp(r'branch: [^,}\s]+'),
        'branch: $branch',
      );
      break;
    }
    file.writeAsStringSync('${lines.join('\n')}\n');
  }

  /// Every repository of the set at or ahead of `origin/<branch>`; one that
  /// is not and has no message is named (exit 1).
  Future<void> _finalCheck() async {
    final behind = <String>[];
    for (final m in set.members) {
      if (!m.onDisk ||
          !_takes(m) ||
          _skipped(m.relPath) ||
          _unresolved.contains(m.relPath)) {
        continue;
      }
      final g = _git(m.path);
      final branch = await g.out(['symbolic-ref', '--short', '-q', 'HEAD']);
      if (branch.isEmpty) continue;
      final remote = 'refs/remotes/origin/$branch';
      if (await g.hasRef(remote) && !await g.contains(remote, 'HEAD')) {
        behind.add(m.relPath);
      }
    }
    if (behind.isNotEmpty) {
      _unresolved.addAll(behind);
      stderr.writeln(
        'Still behind origin: ${behind.map((r) => r.isEmpty ? '.' : r).join(', ')}',
      );
    }
  }
}

/// `:ws-update` (see the library comment).
class WsUpdateExecutor extends CommandExecutor {
  WsUpdateExecutor({this.out, this.now, this.gitEnvironment});

  final StringSink? out;
  final DateTime? now;
  final Map<String, String>? gitEnvironment;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.failure(
        path: context.path,
        name: context.name,
        error: ':ws-update runs over the whole tree, without the traversal',
      );

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final sink = out ?? stdout;
    final options = wsUpdateOptions(args.optionsFor('ws-update'), args);
    final start = p.normalize(p.absolute(args.root ?? Directory.current.path));
    final started = now ?? DateTime.now();

    RepoSet? set;
    String? problem;
    try {
      set = RepoSet.discover(start, manifestPath: args.manifest);
      if (set == null) {
        problem = 'No repos.yaml at or above $start (give --manifest).';
      }
    } on ReposManifestException catch (e) {
      problem = '$e';
    } on FileSystemException catch (e) {
      problem = 'repos.yaml cannot be read: ${e.message} (${e.path})';
    }
    if (set == null) {
      final report =
          RunReport(
            tool: 'buildkit',
            command: ':ws-update',
            root: start,
            host: Platform.localHostname,
            started: started,
            given: options.given,
            names: RepoNames(const []),
          )..add(
            wsManifest.raise(finding: problem!, state: 'Nothing was changed.'),
          );
      sink.writeln(options.json ? report.renderJson() : report.renderText());
      return ToolResult.failure(problem, exitCode: ReportExitCode.refused);
    }

    final run = WsUpdateRun(
      set: set,
      options: options,
      now: started,
      gitEnvironment: gitEnvironment,
    );
    try {
      await run.run();
    } on RepoNameException catch (e) {
      sink.writeln('Error: $e');
      return ToolResult.failure('$e', exitCode: ReportExitCode.refused);
    }
    sink.writeln(
      options.json
          ? run.report.renderJson()
          : run.report.renderText(verbose: options.verbose),
    );
    final code = run.exitCode;
    return code == 0
        ? const ToolResult.success()
        : ToolResult.failure(':ws-update: exit $code', exitCode: code);
  }
}

/// The run's names as they are now: repos.yaml is read again after the
/// root's merge and after the clones, and an entry it gained is named in
/// the report as the next run names it.
class _LiveNames implements RepoNames {
  _LiveNames(this._current);
  final RepoNames Function() _current;

  @override
  List<String> get paths => _current().paths;

  @override
  String nameOf(String path) => _current().nameOf(path);

  @override
  List<String> resolve(String list) => _current().resolve(list);
}
