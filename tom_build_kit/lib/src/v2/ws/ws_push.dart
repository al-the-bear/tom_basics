/// `buildkit :ws-push`: everything this machine has, committed, merged and on
/// the remote, in every repository of the tree (buildkit_ws_commands.md
/// § 1.3).
///
/// The tree is the combined repository set of the `repos.yaml` at or above
/// the folder it is started in (or `--manifest`): the root, the code, fork,
/// ai and binaries entries and the quest clones. `_ai` and the leaves are
/// done first, the root last. Status and fetch run eight repositories at a
/// time; what changes runs one repository after the other.
///
/// 1. **Checks** before anything changes (each refuses the run, exit 2):
///    an active Tom AI window on this host (`ws-active`), a secret
///    (`ws-secret`) or a file over 50 MB (`ws-large`) that would be
///    committed, a merge driver a `.gitattributes` names that is not
///    registered (`ws-driver`), a repository mid-merge / mid-rebase
///    (`ws-in-progress`); no or an invalid `repos.yaml` (`ws-manifest`).
/// 2. **Per repository:** a detached HEAD back on its branch when nothing is
///    lost (else `ws-detached`), off its branch `ws-off-branch`; then
///    `git add -A` and one commit with the run's message, fetch, merge
///    `origin/<branch>` with the merge drivers (a conflict is aborted:
///    `ws-conflict`), push (a rejected push merged once more and retried
///    once: `ws-push-rejected`). Never a force push.
/// 3. `tom_binaries` is pushed only with local commits (`ws-binaries` for
///    uncommitted binaries); unknown clones are skipped (`ws-unknown`), the
///    upstreams too (`ws-upstream-dirty`); `ws-rescue-open` lists unmerged
///    `ws-push/*` branches.
///
/// Exit 0 only when nothing is uncommitted in any repository of the set and
/// `origin/<branch>` contains `HEAD` everywhere; else 1; 2 refused.
library;

import 'dart:convert';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import 'ws_common.dart';
import 'ws_messages.dart';

/// The secret list of `tom_push_code` (`.claude/skills/_lib/git_lib.sh`).
final RegExp wsSecretPattern = RegExp(
  r'(^|/)(\.env(\..+)?|.*\.pem|credentials\..*)$',
);

/// Files larger than this are refused (`ws-large`).
const int wsLargeFileBytes = 50 * 1024 * 1024;

/// A window's heartbeat older than this is a gone window.
const Duration wsHeartbeatStale = Duration(seconds: 90);

/// The options of `:ws-push` that take repositories.
const wsPushRepoOptions = [
  'skip',
  'include-unknown',
  'rescue-detached',
  'push-current',
  'to-branch',
  'set-branch',
  'merge-branch',
  'ours',
  'theirs',
  'leave-conflict',
];

typedef _Git = WsGit;

typedef _Change = WsChange;

/// A repository of the run with what was measured.
class _Repo {
  _Repo(this.member, {this.unknown = false});

  final RepoSetMember member;
  final bool unknown;
  String get path => member.path;
  String get rel => member.relPath;
  bool get isBinaries => member.kind == RepoKind.binaries;
  bool get isUpstream => member.kind == RepoKind.upstream;

  String? branch;
  String? head;
  String? inProgress;
  List<_Change> changes = const [];
  String? fetchError;
  final missingDrivers = <({String driver, String file})>[];

  /// What it was left as (for the final check).
  bool unresolved = false;
  String? pushBranch;
}

/// A live Tom AI window that is working.
class WsActiveWindow {
  const WsActiveWindow(this.description);
  final String description;
}

/// Reads the window-state files in [dir] and answers the windows of this
/// host whose heartbeat is fresh and that have a queue item sending or a run
/// running (`ws-active`).
List<WsActiveWindow> wsActiveWindows(String dir, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final folder = Directory(dir);
  if (!folder.existsSync()) return const [];
  final out = <WsActiveWindow>[];
  for (final f in folder.listSync().whereType<File>()) {
    if (!f.path.endsWith('.window-state.json')) continue;
    Map<String, dynamic> state;
    try {
      state = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } on Object {
      continue;
    }
    final host = state['host'];
    if (host is String && host.isNotEmpty && host != Platform.localHostname) {
      continue;
    }
    final beat = DateTime.tryParse('${state['heartbeat'] ?? ''}');
    if (beat == null || at.difference(beat) > wsHeartbeatStale) continue;
    final where =
        '${state['workspace'] ?? '?'} (quest ${state['activeQuest'] ?? '-'})';
    final queue = state['queue'];
    final sending = queue is Map ? queue['sending'] : null;
    final lines = <String>[];
    if (sending is Map) {
      lines.add(
        '$where, run ${queue['run'] ?? '?'}: sending '
        '"${_shorten('${sending['preview'] ?? sending['id']}')}" since '
        '${sending['since'] ?? '?'} (session ${sending['session'] ?? '?'})',
      );
    }
    final runs = state['runs'];
    if (runs is List) {
      for (final r in runs.whereType<Map>()) {
        final s = '${r['state']}';
        if (s == 'running' || s.startsWith('waiting')) {
          lines.add(
            '$where, run ${r['run']}: $s "${_shorten('${r['detail'] ?? ''}')}"',
          );
        }
      }
    }
    if (lines.isNotEmpty) out.add(WsActiveWindow(lines.join('\n')));
  }
  return out;
}

String _shorten(String s) => s.length > 60 ? '${s.substring(0, 57)}...' : s;

/// The options of a run, as given.
class WsPushOptions {
  WsPushOptions({
    this.message,
    this.ignoreActive = false,
    this.commitBinaries = false,
    this.skipFiles = const [],
    this.allowFiles = const [],
    this.dryRun = false,
    this.verbose = false,
    this.json = false,
    this.repoLists = const {},
  });

  final String? message;
  final bool ignoreActive;
  final bool commitBinaries;
  final List<String> skipFiles;
  final List<String> allowFiles;
  final bool dryRun;
  final bool verbose;
  final bool json;

  /// Per repository-list option, its value as given (`core,basics`).
  final Map<String, String> repoLists;

  /// The command line as typed, for the header and the repeat lines (no
  /// `-n`: a repeat line is the real run).
  List<String> get given => [
    if (message != null) ...['-m', message!],
    if (ignoreActive) '--ignore-active',
    if (commitBinaries) '--commit-binaries',
    for (final g in skipFiles) ...['--skip-file', g],
    for (final g in allowFiles) ...['--allow-file', g],
    for (final e in repoLists.entries) ...['--${e.key}', e.value],
  ];
}

/// One `:ws-push` run over the tree of [set].
class WsPushRun {
  WsPushRun({
    required this.set,
    required this.options,
    DateTime? now,
    this.heartbeatDir,
    this.gitEnvironment,
  }) : now = now ?? DateTime.now();

  final RepoSet set;
  final WsPushOptions options;
  final DateTime now;

  /// The window-state folder (default `<root>/_ai/local`).
  final String? heartbeatDir;
  final Map<String, String>? gitEnvironment;

  late final RunReport report;
  late final RepoNames _names;
  late final RepoSelections _sel;
  final _skippedFiles = <String>[];
  var _leftOut = false;

  String get _host => set.host;

  /// `ws-push/<host>/<yymmdd-hhmm>`.
  String get rescueBranch => wsRescueBranch(_host, now);

  String get _message =>
      options.message ?? 'ws-push on $_host at ${wsIsoMinute(now)}';

  /// The run's exit code.
  int get exitCode {
    var code = report.exitCode;
    if (code < ReportExitCode.needsYou &&
        (_leftOut || _skippedFiles.isNotEmpty)) {
      code = ReportExitCode.needsYou;
    }
    return code;
  }

  _Git _git(String dir) => _Git(dir, gitEnvironment);

  /// Runs it; [RepoNameException] for an unknown or ambiguous repository
  /// name (a usage error).
  Future<RunReport> run() async {
    final inSet = [
      for (final m in set.members)
        if (m.onDisk &&
            (m.inGitSet ||
                m.repoClass == RepoClass.unknown ||
                m.kind == RepoKind.upstream))
          m,
    ];
    _names = RepoNames([for (final m in inSet) m.relPath]);
    _sel = RepoSelections({
      for (final e in options.repoLists.entries)
        e.key: _names.resolve(e.value).toSet(),
    });
    report = RunReport(
      tool: 'buildkit',
      command: ':ws-push',
      root: set.root,
      host: _host,
      started: now,
      given: options.given,
      names: _names,
    );

    final repos = <_Repo>[];
    final unknown = <_Repo>[];
    final upstreams = <_Repo>[];
    for (final m in inSet) {
      if (_sel.applies('skip', m.relPath)) {
        _leftOut = true;
        continue;
      }
      if (m.kind == RepoKind.upstream) {
        upstreams.add(_Repo(m));
      } else if (m.repoClass == RepoClass.unknown) {
        (_sel.applies('include-unknown', m.relPath) ? repos : unknown).add(
          _Repo(m, unknown: true),
        );
      } else {
        repos.add(_Repo(m));
      }
    }
    // _ai first, then the leaves (deepest first), the root last.
    int depth(_Repo r) => r.rel.isEmpty ? -1 : r.rel.split('/').length;
    repos.sort((a, b) {
      if (a.rel == kAiFolder) return -1;
      if (b.rel == kAiFolder) return 1;
      final d = depth(b).compareTo(depth(a));
      return d != 0 ? d : a.rel.compareTo(b.rel);
    });
    report.lookedAt.addAll([for (final r in repos) r.rel]);

    // Status and fetch, eight at a time.
    await _pool([...repos, ...unknown, ...upstreams], (r) async {
      final fetch =
          !options.dryRun && !r.isUpstream && (!r.unknown || repos.contains(r));
      await _measure(r, fetch: fetch);
    });

    if (_refuse(repos)) return report;

    for (final r in unknown) {
      await _reportUnknown(r);
    }
    for (final r in repos) {
      await _push(r);
    }
    for (final r in upstreams) {
      if (r.changes.isNotEmpty) {
        report.add(
          wsUpstreamDirty.raise(
            repository: r.rel,
            finding: '${r.changes.length} local change(s); never committed:',
            evidence: [
              ReportEvidence('files', [
                for (final c in r.changes.take(10)) '${c.code} ${c.path}',
              ]),
            ],
          ),
        );
      }
    }
    return report;
  }

  Future<void> _pool(
    List<_Repo> items,
    Future<void> Function(_Repo) job,
  ) async {
    for (var i = 0; i < items.length; i += 8) {
      await Future.wait([for (final r in items.skip(i).take(8)) job(r)]);
    }
  }

  Future<void> _measure(_Repo r, {required bool fetch}) async {
    final g = _git(r.path);
    if (fetch) {
      final f = await g.run(['fetch', '--quiet', 'origin']);
      if (f.exitCode != 0) r.fetchError = _Git.text(f);
    }
    final branch = await g.out(['symbolic-ref', '--short', '-q', 'HEAD']);
    r.branch = branch.isEmpty ? null : branch;
    final head = await g.run(['rev-parse', 'HEAD']);
    r.head = head.exitCode == 0 ? '${head.stdout}'.trim() : null;
    r.inProgress = await wsOperationInProgress(g);
    final status = await g.run(['status', '--porcelain=v1', '-z', '-uall']);
    r.changes = _parseStatus('${status.stdout}');
    if (!r.isUpstream) r.missingDrivers.addAll(await wsMissingDrivers(g));
  }

  static List<_Change> _parseStatus(String z) => wsParseStatus(z);

  bool _matches(List<String> globs, _Repo r, String path) {
    final fromRoot = r.rel.isEmpty ? path : '${r.rel}/$path';
    for (final g in globs) {
      final glob = Glob(g, context: p.posix);
      if (glob.matches(path) ||
          glob.matches(fromRoot) ||
          g == path ||
          g == fromRoot) {
        return true;
      }
    }
    return false;
  }

  /// The checks before anything changes; true when the run is refused.
  bool _refuse(List<_Repo> repos) {
    if (!options.ignoreActive) {
      final windows = wsActiveWindows(
        heartbeatDir ?? p.join(set.root, kAiFolder, 'local'),
        now: now,
      );
      if (windows.isNotEmpty) {
        report.add(
          wsActive.raise(
            finding:
                '${windows.length} Tom AI window(s) on this host are working:',
            evidence: [
              ReportEvidence('windows', [
                for (final w in windows) ...w.description.split('\n'),
              ]),
            ],
            state: 'Nothing was changed.',
          ),
        );
      }
    }
    for (final r in repos) {
      if (r.inProgress != null) {
        report.add(
          wsInProgress.raise(
            repository: r.rel,
            branch: r.branch,
            finding: 'The repository is in the middle of ${r.inProgress}.',
            evidence: [
              ReportEvidence('files', [
                for (final c in r.changes)
                  if (c.code.contains('U') || c.code == 'AA' || c.code == 'DD')
                    '${c.path}  (conflicted)',
              ]),
            ],
            state: 'Nothing was changed.',
          ),
        );
      }
      for (final d in r.missingDrivers) {
        report.add(
          wsDriver.raise(
            repository: r.rel,
            finding:
                'merge=${d.driver} is named in ${d.file}, but '
                'merge.${d.driver}.driver is not configured.',
            state: 'Nothing was changed.',
          ),
        );
      }
      if (r.isBinaries && !options.commitBinaries) continue;
      final secret = <String>[];
      final large = <String>[];
      for (final c in r.changes) {
        if (c.deleted) continue;
        if (_matches(options.allowFiles, r, c.path)) continue;
        if (_matches(options.skipFiles, r, c.path)) continue;
        if (wsSecretPattern.hasMatch(c.path)) secret.add(c.path);
        final f = File(p.join(r.path, c.path));
        if (f.existsSync() && f.lengthSync() > wsLargeFileBytes) {
          large.add(
            '${c.path}  (${(f.lengthSync() / (1024 * 1024)).toStringAsFixed(0)} MB)',
          );
        }
      }
      if (secret.isNotEmpty) {
        report.add(
          wsSecret.raise(
            repository: r.rel,
            finding:
                '${secret.length} file(s) on the secret list would be committed:',
            evidence: [
              ReportEvidence('files', [
                for (final s in secret) '$s  (matches $wsSecretPattern)',
              ]),
            ],
            state: 'Nothing was changed.',
            values: {'skip-file': secret.first, 'allow-file': secret.first},
          ),
        );
      }
      if (large.isNotEmpty) {
        final first = large.first.split('  (').first;
        report.add(
          wsLarge.raise(
            repository: r.rel,
            finding: '${large.length} file(s) over 50 MB would be committed:',
            evidence: [ReportEvidence('sizes', large)],
            state: 'Nothing was changed.',
            values: {'skip-file': first, 'allow-file': first},
          ),
        );
      }
    }
    return report.messages.any((m) => m.level == MessageLevel.refusal);
  }

  Future<void> _reportUnknown(_Repo r) async {
    final g = _git(r.path);
    final url = await g.originUrl();
    final unpushed = await g.out([
      'log',
      '--oneline',
      '--branches',
      '--not',
      '--remotes',
    ]);
    report.add(
      wsUnknown.raise(
        repository: r.rel,
        branch: r.branch,
        finding: 'A clone repos.yaml does not list; it was skipped.',
        evidence: [
          ReportEvidence('origin', [
            url.isEmpty ? '(no origin)' : url,
          ], label: 'Origin:'),
          ReportEvidence('state', [
            [
              r.changes.isEmpty ? 'clean' : '${r.changes.length} uncommitted',
              if (unpushed.isNotEmpty)
                '${unpushed.split('\n').length} unpushed commit(s)',
            ].join(', '),
          ], label: 'State:'),
        ],
      ),
    );
    _leftOut = true;
  }

  String? _expected(_Repo r) => r.unknown ? r.branch : r.member.expectedBranch;

  Future<bool> _hasRef(_Git g, String ref) =>
      g.ok(['rev-parse', '--verify', '-q', ref]);

  Future<bool> _contains(_Git g, String ancestor, String of) =>
      g.ok(['merge-base', '--is-ancestor', ancestor, of]);

  Future<List<String>> _log(_Git g, String range) async {
    final out = await g.out([
      'log',
      '--oneline',
      '-n',
      '10',
      ...range.split(' '),
    ]);
    return out.isEmpty ? const [] : out.split('\n');
  }

  /// One repository: back on its branch, commit, merge, push; then the
  /// unmerged `ws-push/*` branches of its remote, whatever happened.
  Future<void> _push(_Repo r) async {
    await _pushRepo(r);
    if (r.fetchError != null) return;
    final target = r.pushBranch ?? _expected(r) ?? r.branch;
    if (target != null) await _rescueOpen(r, _git(r.path), target);
  }

  Future<void> _pushRepo(_Repo r) async {
    final g = _git(r.path);
    final actions = <String>[];
    var files = <String>[];
    void done() {
      if (actions.isNotEmpty) {
        report.changed(ReportDone(r.rel, actions, files: files));
      }
    }

    if (r.fetchError != null) {
      r.unresolved = true;
      report.add(
        wsFetchFailed.raise(
          repository: r.rel,
          branch: r.branch,
          finding: 'git fetch origin failed:',
          evidence: [
            ReportEvidence('remote', [await g.originUrl()], label: 'Remote:'),
            ReportEvidence('git', [r.fetchError!], label: 'Git:'),
          ],
          state: 'Nothing was committed, merged or pushed for it.',
        ),
      );
      return;
    }

    var expected = _expected(r);
    final dry = options.dryRun;

    // A detached HEAD.
    if (r.branch == null) {
      final back =
          expected != null &&
          (await _hasRef(g, 'refs/heads/$expected')) &&
          (await _contains(g, 'HEAD', 'refs/heads/$expected') ||
              (await _hasRef(g, 'refs/remotes/origin/$expected') &&
                  await _contains(g, 'HEAD', 'refs/remotes/origin/$expected')));
      if (back) {
        if (!dry) {
          final s = await g.run(['switch', '-q', expected]);
          if (s.exitCode != 0) {
            return _detached(
              r,
              g,
              expected,
              'switching back failed: ${_Git.text(s)}',
            );
          }
        }
        r.branch = expected;
        actions.add('${dry ? 'would put' : 'put'} back on $expected');
      } else if (_sel.applies('rescue-detached', r.rel)) {
        final rescue = rescueBranch;
        if (!dry) {
          await g.run(['switch', '-q', '-c', rescue]);
          await g.run(['add', '-A']);
          if (!await g.ok(['diff', '--cached', '--quiet'])) {
            await g.run(['commit', '-q', '-m', _message]);
          }
          final pr = await g.run([
            'push',
            '-q',
            '--set-upstream',
            'origin',
            rescue,
          ]);
          if (pr.exitCode != 0) {
            r.unresolved = true;
            report.add(_rejected(r, rescue, _Git.text(pr)));
            done();
            return;
          }
          if (expected != null && await _hasRef(g, 'refs/heads/$expected')) {
            await g.run(['switch', '-q', expected]);
          }
        }
        actions.add(
          '${dry ? 'would rescue' : 'rescued'} the detached commits to $rescue',
        );
        r.branch = expected;
        r.changes = const [];
      } else {
        return _detached(r, g, expected, null);
      }
    }

    // Off its branch.
    var branch = r.branch!;
    if (expected != null && branch != expected && !r.unknown) {
      if (_sel.applies('push-current', r.rel)) {
        expected = branch;
      } else if (_sel.applies('to-branch', r.rel)) {
        if (!dry) {
          files = await _commit(r, g);
          final sw = await g.run(['switch', '-q', expected]);
          if (sw.exitCode != 0) {
            r.unresolved = true;
            report.add(
              _offBranch(
                r,
                branch,
                expected,
                'switching failed: ${_Git.text(sw)}',
              ),
            );
            done();
            return;
          }
          final mg = await g.run(['merge', '--no-edit', branch]);
          if (mg.exitCode != 0) {
            await g.run(['merge', '--abort']);
            r.unresolved = true;
            report.add(
              _offBranch(
                r,
                branch,
                expected,
                'merging $branch into $expected conflicts; aborted',
              ),
            );
            done();
            return;
          }
        }
        actions.add('${dry ? 'would merge' : 'merged'} $branch into $expected');
        branch = expected;
      } else if (_sel.applies('set-branch', r.rel)) {
        if (!dry) _setBranch(r.rel, branch);
        actions.add(
          '${dry ? 'would record' : 'recorded'} $branch as its branch in repos.yaml',
        );
        expected = branch;
      } else {
        r.unresolved = true;
        report.add(
          _offBranch(
            r,
            branch,
            expected,
            null,
            commits: await _log(g, '$expected..$branch'),
          ),
        );
        return;
      }
    }
    final target = expected ?? branch;
    r.pushBranch = target;

    // Commit everything (tom_binaries only with --commit-binaries). The
    // status is read again: an earlier step of the run may have changed
    // the repository (the root's repos.yaml with --set-branch).
    if (!dry) {
      r.changes = _parseStatus(
        '${(await g.run(['status', '--porcelain=v1', '-z', '-uall'])).stdout}',
      );
    }
    if (r.isBinaries && !options.commitBinaries) {
      if (r.changes.isNotEmpty) _binariesWarning(r);
    } else if (r.changes.isNotEmpty) {
      if (dry) {
        final keep = [
          for (final c in r.changes)
            if (!_matches(options.skipFiles, r, c.path)) c.path,
        ];
        if (keep.isNotEmpty) {
          files = keep;
          actions.add('would commit ${keep.length} file(s)');
        }
      } else {
        final committed = await _commit(r, g);
        if (committed.isNotEmpty) {
          files = [...files, ...committed];
          actions.add('committed ${committed.length} file(s)');
        }
      }
    }

    // Merge origin/<branch>.
    final remote = 'refs/remotes/origin/$target';
    if (await _hasRef(g, remote) && !await _contains(g, remote, 'HEAD')) {
      final incoming = await _log(g, 'HEAD..$remote');
      if (dry) {
        actions.add('would merge ${incoming.length} incoming commit(s)');
      } else {
        final merged = await _merge(r, g, target, actions);
        if (!merged) {
          done();
          return;
        }
      }
    }

    // Push.
    final ahead =
        !await _hasRef(g, remote) ||
        !await _contains(g, 'HEAD', remote) ||
        (dry && files.isNotEmpty);
    if (ahead) {
      if (dry) {
        actions.add('would push $target');
      } else {
        var push = await _pushBranch(g, target);
        if (push.exitCode != 0) {
          // Merged once more and retried once.
          await g.run(['fetch', '--quiet', 'origin']);
          final merged = await _merge(r, g, target, actions);
          if (!merged) {
            done();
            return;
          }
          push = await _pushBranch(g, target);
        }
        if (push.exitCode != 0) {
          if (_sel.applies('merge-branch', r.rel)) {
            await _pushRescue(r, g, actions);
          } else {
            r.unresolved = true;
            report.add(_rejected(r, target, _Git.text(push)));
          }
        } else {
          actions.add('pushed $target');
        }
      }
    }

    done();
  }

  Future<ProcessResult> _pushBranch(_Git g, String branch) async {
    final upstream = await g.ok([
      'rev-parse',
      '--abbrev-ref',
      '--symbolic-full-name',
      '@{u}',
    ]);
    return g.run([
      'push',
      '-q',
      if (!upstream) '--set-upstream',
      'origin',
      branch,
    ]);
  }

  /// `git add -A` (the `--skip-file` files left out) and one commit; the
  /// committed files.
  Future<List<String>> _commit(_Repo r, _Git g) async {
    await g.run(['add', '-A']);
    for (final c in r.changes) {
      if (_matches(options.skipFiles, r, c.path)) {
        await g.run(['reset', '-q', '--', c.path]);
        _skippedFiles.add('${r.rel}/${c.path}');
      }
    }
    final staged = (await g.out([
      'diff',
      '--cached',
      '--name-only',
      '-z',
    ])).split('\x00').where((f) => f.isNotEmpty).toList();
    if (staged.isEmpty) return const [];
    final c = await g.run(['commit', '-q', '-m', _message]);
    return c.exitCode == 0 ? staged : const [];
  }

  /// Merges `origin/<branch>`; false when the repository needs you.
  Future<bool> _merge(
    _Repo r,
    _Git g,
    String branch,
    List<String> actions,
  ) async {
    final remote = 'refs/remotes/origin/$branch';
    final incoming = await _log(g, 'HEAD..$remote');
    final local = await _log(g, '$remote..HEAD');
    final side = _sel.applies('ours', r.rel)
        ? 'ours'
        : _sel.applies('theirs', r.rel)
        ? 'theirs'
        : null;
    final m = await g.run([
      'merge',
      '--no-edit',
      if (side != null) ...['-X', side],
      remote,
    ]);
    if (m.exitCode == 0) {
      actions.add(
        'merged ${incoming.length} incoming commit(s)${side == null ? '' : ' (-X $side)'}',
      );
      return true;
    }
    final conflicted = (await g.out([
      'diff',
      '--name-only',
      '--diff-filter=U',
    ])).split('\n').where((l) => l.isNotEmpty).toList();
    final newest = await g.out(['log', '-1', '--format=%an, %cI "%s"', remote]);
    final evidence = [
      ReportEvidence('files', [for (final f in conflicted) '$f  both changed']),
      ReportEvidence('local', local, label: 'Local:'),
      ReportEvidence('incoming', [
        '${incoming.length} commit(s), newest by $newest',
      ], label: 'Incoming:'),
    ];
    if (_sel.applies('leave-conflict', r.rel)) {
      r.unresolved = true;
      report.add(
        wsConflict.raise(
          repository: r.rel,
          branch: branch,
          finding:
              'The merge of origin/$branch conflicts; it is left in the working tree:',
          evidence: evidence,
          state: 'Resolve the files, commit, and run :ws-push again.',
          offer: const [],
        ),
      );
      return false;
    }
    await g.run(['merge', '--abort']);
    if (_sel.applies('merge-branch', r.rel)) {
      await _pushRescue(r, g, actions);
      return false;
    }
    r.unresolved = true;
    report.add(
      wsConflict.raise(
        repository: r.rel,
        branch: branch,
        finding:
            'Your ${local.length} local commit(s) and ${incoming.length} incoming '
            'commit(s) change the same lines:',
        evidence: evidence,
        state:
            'Nothing was pushed for this repository; your commits are safe on '
            'this machine.',
        explanations: {
          'merge-branch':
              'Push your commits to $rescueBranch and leave $branch as it is.\n'
              'Your work is on the remote at once; merge the branch later.',
        },
      ),
    );
    return false;
  }

  Future<void> _pushRescue(_Repo r, _Git g, List<String> actions) async {
    final rescue = rescueBranch;
    final pr = await g.run(['push', '-q', 'origin', 'HEAD:refs/heads/$rescue']);
    r.unresolved = true; // origin/<branch> does not hold HEAD yet
    if (pr.exitCode != 0) {
      report.add(_rejected(r, rescue, _Git.text(pr)));
    } else {
      actions.add('pushed to $rescue (merge it later)');
    }
  }

  ReportMessage _rejected(_Repo r, String branch, String git) =>
      wsPushRejected.raise(
        repository: r.rel,
        branch: branch,
        finding: 'The push of $branch still fails after one more merge:',
        evidence: [
          ReportEvidence('git', [git], label: 'Git:'),
        ],
        state: 'Your commits are safe on this machine; nothing was forced.',
        explanations: {
          'merge-branch':
              'Push your commits to $rescueBranch instead; merge later.',
        },
      );

  Future<void> _detached(_Repo r, _Git g, String? expected, String? why) async {
    r.unresolved = true;
    final lost = await _log(g, 'HEAD --not --branches --remotes');
    report.add(
      wsDetached.raise(
        repository: r.rel,
        finding:
            'Detached at ${r.head?.substring(0, 7) ?? '?'}'
            '${expected == null ? '' : ', expected on $expected'}'
            '${why == null ? '' : ' ($why)'}; ${lost.length} commit(s) on no branch:',
        evidence: [ReportEvidence('commits', lost)],
        state: 'Nothing was committed or pushed for it.',
        explanations: {
          'rescue-detached':
              'Put them (and the uncommitted work) on $rescueBranch, push it,\n'
              'and return the repository to ${expected ?? 'its branch'}.',
        },
      ),
    );
  }

  ReportMessage _offBranch(
    _Repo r,
    String branch,
    String expected,
    String? why, {
    List<String> commits = const [],
  }) {
    final from = r.member.repoClass == RepoClass.questClone
        ? '_ai/quests.yaml'
        : 'repos.yaml';
    return wsOffBranch.raise(
      repository: r.rel,
      branch: branch,
      finding:
          'On $branch; $from expects $expected${why == null ? '' : ' ($why)'}.'
          '${commits.isEmpty ? '' : ' Commits on $branch that $expected lacks:'}',
      evidence: [if (commits.isNotEmpty) ReportEvidence('commits', commits)],
      state: 'Nothing was committed or pushed for it.',
      explanations: {
        'push-current': 'Commit and push $branch ($expected stays as it is).',
        'to-branch':
            'Commit, switch to $expected, merge $branch into it,\n'
            'then go on as usual (merge origin, push).',
        'set-branch':
            "Record $branch as the entry's branch: in repos.yaml (the root\n"
            'commits the change), then go on with it.',
      },
    );
  }

  void _binariesWarning(_Repo r) {
    final platforms = <String>{};
    DateTime? newest;
    for (final c in r.changes) {
      final parts = c.path.split('/');
      if (parts.length > 2 && parts.first == 'tom') platforms.add(parts[1]);
      final f = File(p.join(r.path, c.path));
      if (f.existsSync()) {
        final t = f.lastModifiedSync();
        if (newest == null || t.isAfter(newest)) newest = t;
      }
    }
    report.add(
      wsBinaries.raise(
        repository: r.rel,
        finding:
            '${r.changes.length} uncommitted file(s)'
            '${platforms.isEmpty ? '' : ' on ${(platforms.toList()..sort()).join(', ')}'}'
            '${newest == null ? '' : ', newest ${newest.toIso8601String().substring(0, 16)}'}.',
        state: 'Left for the next build; not committed.',
      ),
    );
  }

  Future<void> _rescueOpen(_Repo r, _Git g, String branch) async {
    final refs = await g.out([
      'for-each-ref',
      '--format=%(refname:short)\t%(committerdate:iso-strict)',
      'refs/remotes/origin/ws-push/',
    ]);
    if (refs.isEmpty) return;
    final open = <String>[];
    for (final line in refs.split('\n')) {
      final parts = line.split('\t');
      final ref = parts.first;
      final base = 'refs/remotes/origin/$branch';
      if (await _hasRef(g, base) && await _contains(g, ref, base)) continue;
      final count = await g.out([
        'rev-list',
        '--count',
        if (await _hasRef(g, base)) '$base..$ref' else ref,
      ]);
      open.add(
        '$ref  ($count commit(s), ${parts.length > 1 ? parts[1].substring(0, 16) : '?'})',
      );
    }
    if (open.isEmpty) return;
    report.add(
      wsRescueOpen.raise(
        repository: r.rel,
        finding:
            '${open.length} ws-push branch(es) on origin not merged into $branch:',
        evidence: [ReportEvidence('branches', open)],
      ),
    );
  }

  /// Writes [branch] as the `branch:` of the entry at [rel] in repos.yaml.
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

  /// After the run: every repository clean and its HEAD in
  /// `origin/<branch>`.
  Future<void> finalCheck(List<String> stillOpen) async {
    for (final m in set.members) {
      if (!m.onDisk || !m.inGitSet) continue;
      if (_sel.applies('skip', m.relPath)) continue;
      final g = _git(m.path);
      final dirty = (await g.out(['status', '--porcelain'])).isNotEmpty;
      final branch = await g.out(['symbolic-ref', '--short', '-q', 'HEAD']);
      final target = branch.isEmpty ? null : branch;
      final pushed =
          target != null &&
          await _hasRef(g, 'refs/remotes/origin/$target') &&
          await _contains(g, 'HEAD', 'refs/remotes/origin/$target');
      final binariesOnly =
          m.kind == RepoKind.binaries && !options.commitBinaries;
      if ((dirty && !binariesOnly) || !pushed) stillOpen.add(m.relPath);
    }
  }
}

/// Reads the run's options from [opts] (`args.optionsFor('ws-push')`).
WsPushOptions wsPushOptions(Map<String, dynamic> opts, CliArgs args) {
  List<String> list(Object? v) => [
    for (final x in switch (v) {
      final List<dynamic> l => l,
      final String s => [s],
      _ => const <dynamic>[],
    })
      '$x',
  ];
  return WsPushOptions(
    message: opts['message'] as String?,
    ignoreActive: opts['ignore-active'] == true,
    commitBinaries: opts['commit-binaries'] == true,
    skipFiles: list(opts['skip-file']),
    allowFiles: list(opts['allow-file']),
    dryRun: args.dryRun,
    verbose: args.verbose,
    json: opts['json'] == true,
    repoLists: {
      for (final name in wsPushRepoOptions)
        if (list(opts[name]).isNotEmpty) name: list(opts[name]).join(','),
    },
  );
}

/// `:ws-push` (see the library comment).
class WsPushExecutor extends CommandExecutor {
  WsPushExecutor({this.out, this.now, this.heartbeatDir});

  final StringSink? out;
  final DateTime? now;
  final String? heartbeatDir;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.failure(
        path: context.path,
        name: context.name,
        error: ':ws-push runs over the whole tree, without the traversal',
      );

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final sink = out ?? stdout;
    final options = wsPushOptions(args.optionsFor('ws-push'), args);
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
            command: ':ws-push',
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

    final run = WsPushRun(
      set: set,
      options: options,
      now: started,
      heartbeatDir: heartbeatDir,
    );
    try {
      await run.run();
    } on RepoNameException catch (e) {
      sink.writeln('Error: $e');
      return ToolResult.failure('$e', exitCode: ReportExitCode.refused);
    }
    if (!options.dryRun && run.report.exitCode < ReportExitCode.refused) {
      final open = <String>[];
      await run.finalCheck(open);
      if (open.isNotEmpty && run.exitCode == ReportExitCode.ok) {
        // Not cleanly done although no message says so: exit 1, named.
        stderr.writeln(
          'Not everything is committed and on origin: '
          '${open.map((r) => r.isEmpty ? '.' : r).join(', ')}',
        );
      }
      final code = open.isNotEmpty && run.exitCode == 0 ? 1 : run.exitCode;
      sink.writeln(
        options.json
            ? run.report.renderJson()
            : run.report.renderText(verbose: options.verbose),
      );
      return code == 0
          ? const ToolResult.success()
          : ToolResult.failure(':ws-push: exit $code', exitCode: code);
    }
    sink.writeln(
      options.json
          ? run.report.renderJson()
          : run.report.renderText(verbose: options.verbose),
    );
    final code = run.exitCode;
    return code == 0
        ? const ToolResult.success()
        : ToolResult.failure(':ws-push: exit $code', exitCode: code);
  }
}
