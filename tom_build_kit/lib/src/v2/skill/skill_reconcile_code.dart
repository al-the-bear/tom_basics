/// `buildkit :skill-reconcile-code`: the per-host part of
/// `tom_reconcile_code` (buildkit_ws_commands.md § 1.6;
/// `.claude/skills/tom_reconcile_code/tom_reconcile_code.sh`), under its
/// rules:
///
/// 1. A repository under the root that is no entry of repos.yaml stops the
///    run before anything is touched (`skill-unknown`, exit 1).
/// 2. The merge drivers `generated-newer-wins` and
///    `pubspec-lock-last-changed` must be registered (`skill-driver`, exit 1).
/// 3. Uncommitted work is never committed: a lone run with any stops first
///    (`skill-decision`, exit 3); `--dirty=hold` (or a fleet run,
///    `TOM_FR_FLEET_RUN=1`, or `-n`) goes on and holds it.
/// 4. The code, fork and upstream entries deepest first, then the root: a
///    missing one cloned; code put on its branch, fetched, `origin/<branch>`
///    merged, pushed (a rejected push merged and retried once); a fork only
///    fast-forwarded (a diverged one fails); an upstream put at its pin; a
///    repository whose uncommitted files the merge would overwrite held.
///    `--own-since <file>` commits the files this run wrote after that
///    baseline (`:skill-dirty-scan --baseline`), nothing else.
///
/// Exit 0 every repository reconciled or held, 1 a failure or an unknown
/// repository, 2 a usage error or a refusal, 3 a decision is needed.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../ws/ws_common.dart';
import 'skill_common.dart';
import 'skill_messages.dart';

/// The drivers every reconcile needs (registered by the skills' install.sh).
const skillMergeDrivers = ['generated-newer-wins', 'pubspec-lock-last-changed'];

/// One `:skill-reconcile-code` run.
class SkillReconcileRun {
  SkillReconcileRun({
    required this.set,
    this.hold = false,
    this.ownSince,
    this.dryRun = false,
    DateTime? now,
    this.gitEnvironment,
    this.fleetRun = false,
  }) : now = now ?? DateTime.now();

  final RepoSet set;
  final bool hold;

  /// The baseline file of `--own-since`.
  final String? ownSince;
  final bool dryRun;
  final DateTime now;
  final Map<String, String>? gitEnvironment;

  /// Under a fleet run the orchestrator asked about uncommitted work already.
  final bool fleetRun;

  late final RunReport report;
  final changed = <({String rel, String what})>[];
  final held = <({String rel, String why})>[];
  final failed = <({String rel, String why})>[];
  var repositories = 0;
  Set<String>? _baseline;

  WsGit _git(String dir) => WsGit(dir, gitEnvironment);
  String _id(String rel) => rel == '.' ? '' : rel;

  String _would(String done, String would) => dryRun ? would : done;

  void _changed(String rel, String what) {
    changed.add((rel: rel, what: what));
    report.changed(ReportDone(_id(rel), [what]));
  }

  void _held(String rel, String why, {List<String> files = const []}) {
    held.add((rel: rel, why: why));
    report.add(
      skillHeld.raise(
        repository: _id(rel),
        finding: why,
        evidence: [if (files.isNotEmpty) ReportEvidence('files', files)],
        state: 'Left in place, never committed.',
      ),
    );
  }

  bool _failed(String rel, String why) {
    failed.add((rel: rel, why: why));
    report.add(
      skillFailed.raise(
        repository: _id(rel),
        finding: why,
        state: 'Left as it was; the other repositories went on.',
      ),
    );
    return false;
  }

  int get exitCode => report.exitCode;

  Future<RunReport> run() async {
    final entries = skillEntries(set, kinds: {'code', 'fork', 'upstream'});
    final root = skillRoot(set);
    report = RunReport(
      tool: 'buildkit',
      command: ':skill-reconcile-code',
      root: set.root,
      host: set.host,
      started: now,
      given: [
        if (hold) '--dirty=hold',
        if (ownSince != null) '--own-since=$ownSince',
      ],
      names: RepoNames(['', for (final e in entries) e.rel]),
    );

    // 1. Unknown repositories: reported, nothing touched.
    final unknown = skillUnknownRepos(set);
    if (unknown.isNotEmpty) {
      report.add(
        skillUnknown.raise(
          finding:
              '${unknown.length} repositor${unknown.length == 1 ? 'y' : 'ies'} '
              'under the root that repos.yaml does not list - nothing '
              'reconciled:',
          evidence: [ReportEvidence('paths', unknown)],
          state: 'Nothing was changed; they are never committed.',
        ),
      );
      return report;
    }

    // 2. The merge drivers.
    final g0 = _git(set.root);
    final missingDrivers = [
      for (final d in skillMergeDrivers)
        if (!await g0.ok(['config', '--get', 'merge.$d.driver'])) d,
    ];
    if (missingDrivers.isNotEmpty) {
      report.add(
        skillDriver.raise(
          finding: 'Not registered: ${missingDrivers.join(', ')}.',
          evidence: [ReportEvidence('drivers', missingDrivers)],
          state: 'Nothing was changed.',
        ),
      );
      return report;
    }

    // 3. Uncommitted work: a lone run asks first.
    if (!fleetRun && !hold) {
      final scan = await skillScanTree(set, env: gitEnvironment, now: now);
      if (scan.files > 0) {
        final ev = [
          for (final r in scan.repos)
            if (r.groups.isNotEmpty)
              ReportEvidence(r.disp, [
                for (final g in r.groups)
                  '${g.group}: ${g.files.length} (${g.fingerprint})',
              ], label: '${r.disp}:'),
        ];
        if (dryRun) {
          report.add(
            skillUncommitted.raise(
              finding:
                  'Would stop for a decision on ${scan.files} uncommitted '
                  'file(s) in ${scan.groups} group(s).',
              evidence: ev,
              state: 'Dry run: nothing changed.',
            ),
          );
        } else {
          report.add(
            skillDecision.raise(
              finding:
                  '${scan.files} uncommitted file(s) in ${scan.groups} '
                  'group(s) this run did not make.',
              evidence: ev,
              state: 'Nothing was changed.',
            ),
          );
          return report;
        }
      }
    }
    if (ownSince != null) _baseline = skillReadBaseline(ownSince!);

    // 4. The walk, deepest first; the root last.
    for (final e in entries) {
      repositories++;
      report.lookedAt.add(e.rel);
      if (!e.cloned) {
        if (!await _clone(e)) continue;
        if (dryRun) continue;
      }
      if (e.kind == 'upstream') {
        await _toPin(e);
      } else {
        await _branchRepo(e);
      }
    }
    repositories++;
    report.lookedAt.add('');
    await _branchRepo(root);
    return report;
  }

  Future<bool> _clone(SkillEntry e) async {
    final at = Directory(e.abs);
    if (FileSystemEntity.typeSync(e.abs, followLinks: false) !=
            FileSystemEntityType.notFound &&
        (FileSystemEntity.isLinkSync(e.abs) ||
            !FileSystemEntity.isDirectorySync(e.abs) ||
            at.listSync().isNotEmpty)) {
      return _failed(
        e.rel,
        'missing, and ${e.rel} exists and is no clone - not touched',
      );
    }
    if (dryRun) {
      _changed(e.rel, 'would clone (it is missing)');
      return true;
    }
    at.parent.createSync(recursive: true);
    final g = _git(at.parent.path);
    final r = e.kind == 'upstream'
        ? await g.run(['clone', '--quiet', '--no-checkout', e.url!, e.abs])
        : await g.run([
            'clone',
            '--quiet',
            '--branch',
            e.branch!,
            e.url!,
            e.abs,
          ]);
    if (r.exitCode == 0 && e.kind == 'upstream') {
      final c = await _git(
        e.abs,
      ).run(['checkout', '--quiet', '--detach', e.pin!]);
      if (c.exitCode != 0) {
        return _failed(
          e.rel,
          'missing, and the checkout of its pin failed: ${WsGit.text(c)}',
        );
      }
    }
    if (r.exitCode != 0) {
      return _failed(e.rel, 'missing, and the clone failed: ${WsGit.text(r)}');
    }
    _changed(e.rel, 'cloned (it was missing)');
    return true;
  }

  /// An upstream at its pin.
  Future<void> _toPin(SkillEntry e) async {
    final g = _git(e.abs);
    final pin = e.pin!;
    final head = await g.out(['rev-parse', 'HEAD']);
    if (head == pin) return;
    if (!await g.ok(['cat-file', '-e', '$pin^{commit}'])) {
      if (!dryRun && !await g.ok(['fetch', '--quiet', '--tags', 'origin'])) {
        _failed(e.rel, 'fetch for the pin failed');
        return;
      }
    }
    final content = [
      for (final l in await skillContentPorcelain(g)) skillPorcelainPath(l),
    ];
    if (content.isNotEmpty) {
      final moved = (await g.out([
        'diff',
        '--name-only',
        head,
        pin,
      ])).split('\n');
      final blocking = [
        for (final f in content)
          if (moved.contains(f)) f,
      ];
      if (blocking.isNotEmpty) {
        _held(
          e.rel,
          'uncommitted files the move to the pin would overwrite - not moved',
          files: blocking,
        );
        return;
      }
    }
    if (!dryRun && !await g.ok(['checkout', '--quiet', '--detach', pin])) {
      _failed(e.rel, 'checkout of the pin ${pin.substring(0, 12)} failed');
      return;
    }
    _changed(
      e.rel,
      _would(
        'moved to its pin ${pin.substring(0, 12)}',
        'would move to its pin ${pin.substring(0, 12)}',
      ),
    );
  }

  /// A code or fork repository, or the root.
  Future<void> _branchRepo(SkillEntry e) async {
    final g = _git(e.abs);
    final branch = e.branch!;
    if (e.isRoot) {
      final cur = await g.out(['symbolic-ref', '-q', '--short', 'HEAD']);
      if (cur != branch) {
        _failed(
          e.rel,
          "the root is on '${cur.isEmpty ? 'a detached HEAD' : cur}', "
          "repos.yaml's root branch is '$branch'",
        );
        return;
      }
    } else if (!await _ensureOnBranch(e, g)) {
      return;
    }
    final content = await skillContentPorcelain(g);
    if (ownSince != null) {
      if (!await _commitOwn(e, g, content)) return;
    } else if (content.isNotEmpty) {
      _held(
        e.rel,
        '${content.length} uncommitted path(s), left in place',
        files: [for (final l in content) skillPorcelainPath(l)],
      );
    }
    if (!dryRun && !await g.ok(['fetch', '--quiet', 'origin'])) {
      _failed(e.rel, 'git fetch failed');
      return;
    }
    if (!await g.hasRef('refs/remotes/origin/$branch')) {
      _failed(
        e.rel,
        "origin has no branch '$branch' - nothing taken in or pushed "
        '(publishing a branch is a decision)',
      );
      return;
    }
    final taken = await _takeIn(e, g, branch);
    if (taken != 0) return;
    await _pushOut(e, g, branch);
  }

  /// Puts the clone on its manifest branch without losing a commit
  /// (`tom_ensure_on_manifest_branch`): code as `tom_ensure_on_branch`, a fork
  /// fast-forward only.
  Future<bool> _ensureOnBranch(SkillEntry e, WsGit g) async {
    final branch = e.branch!;
    final cur = await g.out(['symbolic-ref', '-q', '--short', 'HEAD']);
    if (cur == branch) return true;
    if (dryRun) {
      _changed(e.rel, 'would put it on $branch');
      return true;
    }
    Future<bool> git(List<String> args) async {
      final r = await g.run(args);
      if (r.exitCode == 0) return true;
      return _failed(
        e.rel,
        "not on its manifest branch '$branch': ${WsGit.text(r)}",
      );
    }

    final c = await g.out(['rev-parse', 'HEAD']);
    final hasLocal = await g.hasRef('refs/heads/$branch');
    if (e.kind != 'fork') {
      if (cur.isNotEmpty) {
        return (await g.ok(['checkout', '--quiet', branch])) ||
            await git(['checkout', '--quiet', '-B', branch]);
      }
      if (!hasLocal) return git(['checkout', '--quiet', '-B', branch]);
      final b = await g.out(['rev-parse', 'refs/heads/$branch']);
      if (b == c || await g.contains(c, b)) {
        return git(['checkout', '--quiet', branch]);
      }
      if (await g.contains(b, c)) {
        return git(['checkout', '--quiet', '-B', branch, c]);
      }
      if (!await git(['checkout', '--quiet', branch])) return false;
      return git(['merge', '--no-edit', '-q', c]);
    }
    // A fork: fast-forward only.
    if (!hasLocal) {
      final remote = 'refs/remotes/origin/$branch';
      if (await g.hasRef(remote) &&
          !await g.contains(remote, c) &&
          !await g.contains(c, remote)) {
        return _failed(
          e.rel,
          'fork is at $c, which has diverged from origin/$branch - not '
          'attached; a fork is only fast-forwarded',
        );
      }
      if (cur.isNotEmpty) {
        return _failed(
          e.rel,
          "fork is on '$cur', repos.yaml says '$branch', and there is no "
          "local '$branch' - not switched",
        );
      }
      return git(['checkout', '--quiet', '-B', branch, c]);
    }
    final b = await g.out(['rev-parse', 'refs/heads/$branch']);
    if (cur.isNotEmpty) return git(['checkout', '--quiet', branch]);
    if (b == c || await g.contains(c, b)) {
      return git(['checkout', '--quiet', branch]);
    }
    if (await g.contains(b, c)) {
      return git(['checkout', '--quiet', '-B', branch, c]);
    }
    return _failed(
      e.rel,
      "fork is detached at $c, which has diverged from '$branch' ($b) - not "
      'attached; a fork is only fast-forwarded',
    );
  }

  /// With `--own-since`: commits the paths this run wrote; every other
  /// uncommitted path is held.
  Future<bool> _commitOwn(SkillEntry e, WsGit g, List<String> content) async {
    if (content.isEmpty) return true;
    bool isOwn(String line) =>
        !_baseline!.contains('${e.abs}\t${skillPorcelainPath(line)}');
    final own = [
      for (final l in content)
        if (isOwn(l)) l,
    ];
    final foreign = [
      for (final l in content)
        if (!isOwn(l)) l,
    ];
    if (foreign.isNotEmpty) {
      _held(
        e.rel,
        '${foreign.length} uncommitted path(s) this run did not make, left in place',
        files: [for (final l in foreign) skillPorcelainPath(l)],
      );
    }
    if (own.isEmpty) return true;
    final secret = [
      for (final l in own)
        if (skillSecretPattern.hasMatch(skillPorcelainPath(l)))
          skillPorcelainPath(l),
    ];
    if (secret.isNotEmpty) {
      return _failed(
        e.rel,
        "this run's own files include secret-pattern paths - not committed: "
        '${secret.join(', ')}',
      );
    }
    final paths = <String>{
      for (final l in own) ...[
        skillPorcelainPath(l),
        if (l.substring(3).contains(' -> '))
          l.substring(3, l.lastIndexOf(' -> ')).replaceAll('"', ''),
      ],
    }.toList();
    if (!dryRun) {
      final add = await g.run(['add', '-A', '--', ...paths]);
      final msg =
          'chore: reconcile ${e.rel} on ${set.host} at ${wsIsoMinute(now)}';
      final staged = await g.out([
        'diff',
        '--cached',
        '--name-only',
        '--',
        ...paths,
      ]);
      if (add.exitCode != 0 ||
          (staged.isNotEmpty &&
              !await g.ok(['commit', '-q', '-m', msg, '--', ...paths]))) {
        return _failed(e.rel, "commit of this run's own files failed");
      }
    }
    _changed(
      e.rel,
      '${_would('committed', 'would commit')} ${own.length} path(s) this '
      'run wrote (since the --own-since baseline)',
    );
    return true;
  }

  /// Brings `origin/<branch>` in: 0 done or nothing to do, 1 failed, 2 held.
  Future<int> _takeIn(SkillEntry e, WsGit g, String branch) async {
    final remote = 'origin/$branch';
    final behind =
        int.tryParse(await g.out(['rev-list', '--count', 'HEAD..$remote'])) ??
        0;
    if (behind == 0) return 0;
    final content = [
      for (final l in await skillContentPorcelain(g)) skillPorcelainPath(l),
    ];
    if (content.isNotEmpty) {
      final base = await g.out(['merge-base', 'HEAD', remote]);
      final incoming = base.isEmpty
          ? const <String>[]
          : (await g.out(['diff', '--name-only', base, remote])).split('\n');
      final blocking = [
        for (final f in content)
          if (incoming.contains(f)) f,
      ];
      if (blocking.isNotEmpty) {
        _held(
          e.rel,
          '${blocking.length} uncommitted path(s) the incoming $behind '
          'commit(s) would overwrite - not merged',
          files: blocking,
        );
        return 2;
      }
    }
    if (e.kind == 'fork') {
      if (!await g.contains('HEAD', remote)) {
        _failed(
          e.rel,
          'fork has diverged from $remote - not merged (a fork is only '
          'fast-forwarded)',
        );
        return 1;
      }
      if (!dryRun && !await g.ok(['merge', '--quiet', '--ff-only', remote])) {
        _failed(e.rel, 'fast-forward to $remote failed');
        return 1;
      }
      _changed(
        e.rel,
        '${_would('fast-forwarded', 'would fast-forward')} $behind commit(s)',
      );
      return 0;
    }
    if (dryRun) {
      _changed(e.rel, 'would take in $behind commit(s)');
      return 0;
    }
    if (await g.ok([
      '-c',
      'merge.ff=true',
      'merge',
      '--quiet',
      '--no-edit',
      remote,
    ])) {
      _changed(e.rel, 'took in $behind commit(s) from $remote');
      return 0;
    }
    final conflicts = (await g.out([
      'diff',
      '--name-only',
      '--diff-filter=U',
    ])).split('\n').where((l) => l.isNotEmpty).join(' ');
    await g.run(['merge', '--abort']);
    _failed(
      e.rel,
      'merge of $remote conflicts (${conflicts.isEmpty ? 'it did not start' : conflicts}) '
      '- aborted, resolve by hand',
    );
    return 1;
  }

  /// Pushes what origin lacks, never forced; a rejected push is retried once
  /// after a fetch and a merge.
  Future<void> _pushOut(SkillEntry e, WsGit g, String branch) async {
    final remote = 'origin/$branch';
    Future<int> ahead() async =>
        int.tryParse(await g.out(['rev-list', '--count', '$remote..HEAD'])) ??
        0;
    var n = await ahead();
    if (n == 0) return;
    if (dryRun) {
      _changed(e.rel, 'would push $n commit(s)');
      return;
    }
    final push = ['push', '--quiet', 'origin', 'HEAD:refs/heads/$branch'];
    if (await g.ok(push)) {
      _changed(e.rel, 'pushed $n commit(s)');
      return;
    }
    if (!await g.ok(['fetch', '--quiet', 'origin'])) {
      _failed(e.rel, 'fetch after the rejected push failed');
      return;
    }
    final taken = await _takeIn(e, g, branch);
    if (taken != 0) return;
    n = await ahead();
    if (await g.ok(push)) {
      _changed(e.rel, 'pushed $n commit(s) (after the retry)');
      return;
    }
    _failed(e.rel, 'push to $remote rejected twice');
  }

  Map<String, Object?> toJson() => {
    'repositories': repositories,
    'changed': [
      for (final c in changed) {'repository': c.rel, 'what': c.what},
    ],
    'held': [
      for (final h in held) {'repository': h.rel, 'why': h.why},
    ],
    'failed': [
      for (final f in failed) {'repository': f.rel, 'why': f.why},
    ],
  };
}

/// `:skill-reconcile-code` (see the library comment).
class SkillReconcileExecutor extends CommandExecutor {
  SkillReconcileExecutor({this.out, this.now, this.gitEnvironment});

  final StringSink? out;
  final DateTime? now;
  final Map<String, String>? gitEnvironment;

  @override
  Future<ItemResult> execute(
    CommandContext context,
    CliArgs args,
  ) async => ItemResult.failure(
    path: context.path,
    name: context.name,
    error:
        ':skill-reconcile-code runs over the whole tree, without the traversal',
  );

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final sink = out ?? stdout;
    final opts = args.optionsFor('skill-reconcile-code');
    final json = opts['json'] == true;
    final dirty = (opts['dirty'] as String?) ?? 'ask';
    var ownSince = opts['own-since'] as String?;
    final started = now ?? DateTime.now();
    if (dirty != 'ask' && dirty != 'hold') {
      sink.writeln("Error: --dirty must be ask or hold (got '$dirty').");
      return ToolResult.failure(
        '--dirty: $dirty',
        exitCode: ReportExitCode.refused,
      );
    }
    final found = await skillDiscover(
      args: args,
      command: ':skill-reconcile-code',
      given: [
        if (dirty == 'hold') '--dirty=hold',
        if (ownSince != null) '--own-since=$ownSince',
      ],
      json: json,
      sink: sink,
      started: started,
    );
    if (found.refused != null) return found.refused!;
    final set = found.set!;
    if (ownSince != null) {
      if (!p.isAbsolute(ownSince)) ownSince = p.join(set.root, ownSince);
      if (!File(ownSince).existsSync()) {
        sink.writeln('Error: --own-since baseline not readable: $ownSince');
        return ToolResult.failure(
          '--own-since: $ownSince',
          exitCode: ReportExitCode.refused,
        );
      }
    }
    final run = SkillReconcileRun(
      set: set,
      hold: dirty == 'hold',
      ownSince: ownSince,
      dryRun: args.dryRun,
      now: started,
      gitEnvironment: gitEnvironment,
      fleetRun:
          (gitEnvironment?['TOM_FR_FLEET_RUN'] ??
              Platform.environment['TOM_FR_FLEET_RUN']) ==
          '1',
    );
    await run.run();
    sink.writeln(
      json
          ? skillJson(run.report, 'reconcile', run.toJson())
          : run.report.renderText(verbose: args.verbose),
    );
    final code = run.exitCode;
    return code == 0
        ? const ToolResult.success()
        : ToolResult.failure(
            ':skill-reconcile-code: exit $code',
            exitCode: code,
          );
  }
}
