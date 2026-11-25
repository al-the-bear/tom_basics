/// A clone of the workspace for the suites of the build tools, so that no
/// test reads or writes the live tree other sessions are working in.
///
/// ## Why a clone
///
/// Several sessions edit the live workspace at once. A test that writes there
/// (a fixture `buildkit_master.yaml` at the root, a provisioned project, a
/// skip file, a `git checkout -- .` to clean up) can destroy another session's
/// uncommitted work, and a test that only reads it walks a tree that changes
/// under it and, under other sessions' load, times out.
///
/// ## What it is
///
/// One clone per machine, beside the workspace: `<parent>/<name>_testclone`
/// for a workspace at `<parent>/<name>`, or the directory `TOM_TEST_WORKSPACE`
/// names. Every repository of the live workspace is a repository of the
/// clone at the same path, laid out as the live one is, and `origin` carries
/// the live repository's URL (pushing is disabled), so tools that read a
/// tree's git layout see what they see in the live one:
///
/// - With a `repos.yaml` in the live workspace or a folder above it, the
///   repositories are the members of tom_build_base's `RepoSet` inside the
///   live workspace that its git commands take (the entries but upstreams,
///   and the quest clones); unmanaged, tool-owned and unknown clones are
///   left out. Each is an independent clone, as in the live tree.
/// - Without one, the superproject and each initialised submodule,
///   recursively; a submodule's `.git` is a file pointing into its parent's
///   `.git/modules/<name>`.
///
/// [TomWorkspaceClone.acquire] takes the machine's lock, creates the clone if
/// it is missing, resets it, and brings every repository to the commit (and
/// branch) the matching LIVE repository has checked out — fetched from the
/// live repository on this machine, so unpushed commits are included and
/// uncommitted edits are not. [TomWorkspaceClone.release] resets it again and
/// gives the lock back. A reset checks out the recorded commit, `git reset
/// --hard` and `git clean -ffd` in every repository: tracked and untracked
/// changes go, ignored files (`.dart_tool/`, `pubspec.lock`) stay, so package
/// resolution is not redone from scratch every run.
///
/// The clone carries a marker (`.git/tom_workspace_clone.json`, holding the
/// state of the last update); nothing here updates, resets or hands out a tree
/// without it, and [tomRequireWorkspaceClone] lets a test helper refuse to
/// change anything else.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart' show RepoSet;

import 'roots.dart';

/// The environment variable that names the clone's directory.
const tomTestWorkspaceEnv = 'TOM_TEST_WORKSPACE';

/// The skip file in the clone's root: every tool built on tom_build_base
/// leaves the clone out when it walks from above (`buildkit -w` at the
/// workspace's parent does not run in the clone).
const tomWorkspaceCloneSkipFile = 'tom_skip.yaml';

/// Marks [root], a workspace clone, as a folder the tools leave out: writes
/// [tomWorkspaceCloneSkipFile] into it and keeps the file out of the
/// clone's git status (`.git/info/exclude`), so the clone's reset keeps it.
/// Safe to call again.
void tomMarkWorkspaceClone(Directory root) {
  final skip = File(p.join(root.path, tomWorkspaceCloneSkipFile));
  if (!skip.existsSync()) {
    skip.writeAsStringSync(
      '# The build tools\' workspace clone (tom_test_support TomWorkspaceClone):\n'
      '# every tool built on tom_build_base skips this folder when it walks\n'
      '# from above. Written by the clone, kept out of its git status.\n',
    );
  }
  final exclude = File(p.join(root.path, '.git', 'info', 'exclude'));
  final line = '/$tomWorkspaceCloneSkipFile';
  final text = exclude.existsSync() ? exclude.readAsStringSync() : '';
  if (!text.split('\n').contains(line)) {
    exclude
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${text.isEmpty || text.endsWith('\n') ? text : '$text\n'}$line\n',
      );
  }
}

/// The marker and state file inside the clone root's `.git` directory.
const tomWorkspaceCloneMarker = 'tom_workspace_clone.json';

/// What pushing from a clone repository is pointed at: nothing.
const _disabledPushUrl = 'disabled:tom-workspace-clone-does-not-push';

/// Whether [dir] is the root of a workspace clone.
bool tomIsWorkspaceClone(Directory dir) =>
    File(p.join(dir.path, '.git', tomWorkspaceCloneMarker)).existsSync();

/// Throws unless [dir] is a workspace clone's root or lies inside one.
///
/// For a test helper that changes a tree: call it before every write, so a
/// helper handed the wrong root refuses instead of changing the live tree.
void tomRequireWorkspaceClone(Directory dir, {String operation = 'change'}) {
  final root = tomFindUp(dir, tomIsWorkspaceClone);
  if (root == null) {
    throw StateError(
      'Refusing to $operation ${dir.path}: it is not inside a workspace clone '
      '(no .git/$tomWorkspaceCloneMarker above it). Build-tool tests work in '
      'the clone TomWorkspaceClone.acquire() hands out, never in the live '
      'workspace.',
    );
  }
}

/// One repository of the workspace: its path relative to the root ('' for
/// the root itself) and, for a submodule, its name in the parent. A nested
/// repository without a parent is an independent clone (`repos.yaml`).
class _Repo {
  const _Repo(this.path, {this.parent, this.name, this.pathInParent});

  final String path;
  final String? parent;
  final String? name;
  final String? pathInParent;

  bool get isSubmodule => parent != null;
}

/// The checked-out state of one repository.
class _Head {
  const _Head(this.sha, this.branch);

  final String sha;
  final String? branch;

  Map<String, Object?> toJson() => {'sha': sha, 'branch': branch};

  static _Head fromJson(Map<String, Object?> json) =>
      _Head(json['sha']! as String, json['branch'] as String?);
}

/// The workspace clone, held under the machine's lock until [release].
class TomWorkspaceClone {
  TomWorkspaceClone._(this.root, this.liveRoot, this._lock, this._log);

  /// The clone's root: a workspace like the live one, for the tests to use.
  final Directory root;

  /// The live workspace the clone follows. Tests read nothing from it.
  final Directory liveRoot;

  final File _lock;
  final void Function(String) _log;
  bool _released = false;

  /// Repositories cloned during this run: their HEAD names the live commit
  /// but nothing is checked out yet.
  final Set<String> _fresh = {};

  /// The live workspace above [from] (default: the current directory): the
  /// nearest directory holding `buildkit_master.yaml` ([tomFindWorkspaceRoot]),
  /// or null.
  static Directory? findLiveRoot({Directory? from}) =>
      tomFindWorkspaceRoot(from: from);

  /// Where the clone of [liveRoot] lives: [tomTestWorkspaceEnv] when set,
  /// else `<parent>/<name>_testclone`.
  static Directory locationFor(Directory liveRoot) {
    final env = Platform.environment[tomTestWorkspaceEnv];
    if (env != null && env.trim().isNotEmpty) {
      return Directory(p.normalize(p.absolute(env.trim())));
    }
    final live = p.normalize(liveRoot.absolute.path);
    return Directory(p.join(p.dirname(live), '${p.basename(live)}_testclone'));
  }

  /// Take the machine's clone for this run.
  ///
  /// [liveRoot] defaults to the workspace the run is in ([findLiveRoot]);
  /// [cloneRoot] to [locationFor]. Waits up to
  /// [lockTimeout] for another run holding the clone, then throws naming it.
  /// Creating the clone the first time copies the whole workspace and takes
  /// minutes; an update fetches only what changed.
  static Future<TomWorkspaceClone> acquire({
    Directory? liveRoot,
    Directory? cloneRoot,
    Duration lockTimeout = const Duration(minutes: 30),
    void Function(String message)? log,
  }) async {
    final logger = log ?? (String m) => stderr.writeln('[workspace clone] $m');
    final live = liveRoot ?? findLiveRoot();
    if (live == null) {
      throw StateError(
        'No workspace above ${Directory.current.path} (no directory holding '
        '$tomWorkspaceMarker), so there is nothing to clone.',
      );
    }
    final livePath = p.normalize(live.absolute.path);
    final clone = Directory(
      p.normalize((cloneRoot ?? locationFor(live)).absolute.path),
    );
    if (p.equals(clone.path, livePath) ||
        p.isWithin(livePath, clone.path) ||
        p.isWithin(clone.path, livePath)) {
      throw StateError(
        'Refusing a clone at ${clone.path}: it overlaps the live workspace '
        '$livePath.',
      );
    }

    final lock = File('${clone.path}.lock');
    await _takeLock(lock, lockTimeout, logger);
    final held = TomWorkspaceClone._(clone, Directory(livePath), lock, logger);
    try {
      await held._prepare();
    } catch (_) {
      held._unlock();
      rethrow;
    }
    return held;
  }

  /// Reset the clone and give the lock back. Safe to call twice.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _reset(_readState());
    } finally {
      _unlock();
    }
  }

  // ---------------------------------------------------------------------------
  // Create, update, reset
  // ---------------------------------------------------------------------------

  Future<void> _prepare() async {
    if (!root.existsSync()) {
      _log(
        'creating ${root.path} from ${liveRoot.path} (first use; this '
        'copies the whole workspace)',
      );
      await _git(root.parent, [
        'clone',
        '--quiet',
        '--no-checkout',
        liveRoot.path,
        root.path,
      ]);
      _writeState(<String, _Head>{});
      _fresh.add('');
    } else if (!tomIsWorkspaceClone(root)) {
      throw StateError(
        'Refusing to use ${root.path}: it exists but is not a workspace '
        'clone (no .git/$tomWorkspaceCloneMarker). Move it away or set '
        '$tomTestWorkspaceEnv to another directory.',
      );
    }
    final state = _readState();
    await _reset(state);
    await _update();
    tomMarkWorkspaceClone(root);
  }

  /// Bring every repository to what its live repository has checked out.
  Future<void> _update() async {
    final repos = await _liveRepos();
    final heads = <String, _Head>{};
    var moved = 0;
    final sw = Stopwatch()..start();
    for (final repo in repos) {
      final live = Directory(p.join(liveRoot.path, repo.path));
      final head = await _liveHead(live);
      final cloneDir = Directory(p.join(root.path, repo.path));
      if (repo.path.isNotEmpty && !_hasGit(cloneDir)) {
        if (repo.isSubmodule) {
          await _addSubmodule(repo);
        } else {
          await _addClone(repo);
        }
        _fresh.add(repo.path);
      }
      if (_fresh.contains(repo.path)) {
        await _checkout(cloneDir, head);
        moved++;
      } else if (await _headOf(cloneDir) != head.sha) {
        // No submodule recursion: every submodule is updated from its own
        // live repository in this loop. git's on-demand recursion would ask
        // each submodule's origin for the commit its gitlink names, which
        // fails ('not our ref') for a commit that was never pushed.
        await _git(cloneDir, [
          'fetch',
          '--quiet',
          '--no-recurse-submodules',
          live.path,
          'HEAD',
        ]);
        await _checkout(cloneDir, head);
        moved++;
      } else if (await _branchOf(cloneDir) != head.branch) {
        await _checkout(cloneDir, head);
      }
      await _mirrorRemote(live, cloneDir);
      if (repo.isSubmodule) await _mirrorSubmoduleConfig(repo);
      heads[repo.path] = head;
    }
    _writeState(heads);
    _log(
      'up to date with ${liveRoot.path}: ${repos.length} repositories, '
      '$moved moved (${sw.elapsedMilliseconds} ms)',
    );
  }

  /// Every repository of the live workspace, each parent before the
  /// repositories inside it: from `repos.yaml` when one is at or above the
  /// live workspace, else its submodules.
  Future<List<_Repo>> _liveRepos() async =>
      _reposFromManifest() ?? await _liveSubmodules();

  /// The repositories of the git set ([RepoSet], tom_build_base) inside the
  /// live workspace, or null when no `repos.yaml` covers it (none above it,
  /// or the live workspace lies in a folder the set never looks at).
  List<_Repo>? _reposFromManifest() {
    final set = RepoSet.discover(liveRoot.path);
    if (set == null) return null;
    return [
      const _Repo(''),
      for (final m in set.members)
        if (m.inGitSet && m.onDisk && p.isWithin(liveRoot.path, m.path))
          _Repo(p.relative(m.path, from: liveRoot.path)),
    ];
  }

  /// The superproject and its submodules, recursively, each parent before
  /// its submodules.
  Future<List<_Repo>> _liveSubmodules() async {
    final out = await _git(liveRoot, [
      'submodule',
      'foreach',
      '--recursive',
      '--quiet',
      r'printf "%s\t%s\t%s\t%s\n" "$displaypath" "$sm_path" "$name" "$toplevel"',
    ]);
    final repos = <_Repo>[const _Repo('')];
    for (final line in LineSplitter.split(out)) {
      if (line.trim().isEmpty) continue;
      final f = line.split('\t');
      final parent = p.relative(f[3], from: liveRoot.path);
      repos.add(
        _Repo(
          p.normalize(f[0]),
          parent: parent == '.' ? '' : parent,
          name: f[2],
          pathInParent: f[1],
        ),
      );
    }
    return repos;
  }

  /// Clone a submodule from its live repository into the parent's
  /// `.git/modules/<name>`, the layout `git submodule` gives it.
  Future<void> _addSubmodule(_Repo repo) async {
    final parentDir = Directory(p.join(root.path, repo.parent!));
    final gitDir = (await _git(parentDir, [
      'rev-parse',
      '--absolute-git-dir',
    ])).trim();
    final moduleDir = Directory(p.join(gitDir, 'modules', repo.name!));
    final worktree = Directory(p.join(root.path, repo.path));
    if (moduleDir.existsSync()) moduleDir.deleteSync(recursive: true);
    moduleDir.parent.createSync(recursive: true);
    if (worktree.existsSync() && worktree.listSync().isNotEmpty) {
      throw StateError(
        'Cannot add submodule ${repo.path} to the clone: ${worktree.path} '
        'exists and is not empty.',
      );
    }
    await _git(parentDir, [
      'clone',
      '--quiet',
      '--no-checkout',
      '--separate-git-dir=${moduleDir.path}',
      p.join(liveRoot.path, repo.path),
      worktree.path,
    ]);
    // A relative gitdir, as `git submodule` writes it, so the tree can be
    // read the same way from anywhere.
    File(p.join(worktree.path, '.git')).writeAsStringSync(
      'gitdir: ${p.relative(moduleDir.path, from: worktree.path)}\n',
    );
  }

  /// Clone an independent repository from its live repository at its path,
  /// as the live tree has it (a `.git` directory of its own).
  Future<void> _addClone(_Repo repo) async {
    final worktree = Directory(p.join(root.path, repo.path));
    if (worktree.existsSync() && worktree.listSync().isNotEmpty) {
      throw StateError(
        'Cannot add repository ${repo.path} to the clone: ${worktree.path} '
        'exists and is not empty.',
      );
    }
    worktree.parent.createSync(recursive: true);
    await _git(worktree.parent, [
      'clone',
      '--quiet',
      '--no-checkout',
      p.join(liveRoot.path, repo.path),
      worktree.path,
    ]);
  }

  /// The parent's submodule entry as the live parent has it.
  Future<void> _mirrorSubmoduleConfig(_Repo repo) async {
    final liveParent = Directory(p.join(liveRoot.path, repo.parent!));
    final cloneParent = Directory(p.join(root.path, repo.parent!));
    final key = 'submodule.${repo.name}.url';
    final url =
        await _gitOrNull(liveParent, ['config', '--get', key]) ??
        await _gitOrNull(liveParent, [
          'config',
          '-f',
          '.gitmodules',
          '--get',
          key,
        ]);
    if (url != null) await _git(cloneParent, ['config', key, url.trim()]);
    await _git(cloneParent, [
      'config',
      'submodule.${repo.name}.active',
      'true',
    ]);
  }

  /// `origin` as the live repository has it; pushing goes nowhere.
  Future<void> _mirrorRemote(Directory live, Directory clone) async {
    final url = await _gitOrNull(live, [
      'config',
      '--get',
      'remote.origin.url',
    ]);
    if (url == null) return;
    final has = await _gitOrNull(clone, ['remote', 'get-url', 'origin']);
    if (has == null) {
      await _git(clone, ['remote', 'add', 'origin', url.trim()]);
    } else if (has.trim() != url.trim()) {
      await _git(clone, ['remote', 'set-url', 'origin', url.trim()]);
    }
    await _git(clone, [
      'remote',
      'set-url',
      '--push',
      'origin',
      _disabledPushUrl,
    ]);
  }

  /// Every recorded repository back to its recorded commit, tracked and
  /// untracked changes removed, ignored files kept.
  Future<void> _reset(Map<String, _Head> heads) async {
    var cleaned = 0;
    // Children first is not needed — a reset never descends into a
    // submodule — but deepest first keeps the parent's view settled last.
    final paths = heads.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final path in paths) {
      final dir = Directory(p.join(root.path, path));
      if (!_hasGit(dir)) continue;
      final head = heads[path]!;
      final status = await _git(dir, [
        'status',
        '--porcelain',
        '--ignore-submodules=all',
      ]);
      final atHead =
          await _headOf(dir) == head.sha && await _branchOf(dir) == head.branch;
      if (status.trim().isEmpty && atHead) continue;
      if (!atHead) await _checkout(dir, head);
      await _git(dir, ['reset', '--quiet', '--hard']);
      // -ff: also an untracked nested repository, e.g. the checkout a
      // submodule removed upstream leaves behind. Ignored files stay, and so
      // do the clone's own repositories inside this one (an independent
      // clone its parent does not ignore would otherwise go).
      await _git(dir, ['clean', '-ffdq', ..._innerExcludes(path, paths)]);
      cleaned++;
    }
    if (cleaned > 0) _log('reset $cleaned repositories');
  }

  /// `git clean` excludes for the repositories in [all] that lie inside the
  /// one at [path] (paths relative to the clone's root, '' for the root).
  static List<String> _innerExcludes(String path, Iterable<String> all) => [
    for (final inner in all)
      if (inner.isNotEmpty &&
          inner != path &&
          (path.isEmpty || p.isWithin(path, inner)))
        '--exclude=/${p.split(path.isEmpty ? inner : p.relative(inner, from: path)).join('/')}',
  ];

  Future<void> _checkout(Directory dir, _Head head) async {
    if (head.branch != null) {
      await _git(dir, [
        'checkout',
        '--quiet',
        '--force',
        '-B',
        head.branch!,
        head.sha,
      ]);
    } else {
      await _git(dir, ['checkout', '--quiet', '--force', '--detach', head.sha]);
    }
  }

  // ---------------------------------------------------------------------------
  // State and lock
  // ---------------------------------------------------------------------------

  File get _stateFile =>
      File(p.join(root.path, '.git', tomWorkspaceCloneMarker));

  Map<String, _Head> _readState() {
    final f = _stateFile;
    if (!f.existsSync()) return {};
    final json = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    final repos = (json['repos'] as Map<String, Object?>?) ?? {};
    return {
      for (final e in repos.entries)
        e.key: _Head.fromJson(e.value! as Map<String, Object?>),
    };
  }

  void _writeState(Map<String, _Head> heads) {
    _stateFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'what':
            'Workspace clone for the build-tool tests '
            '(tom_test_support workspace_clone.dart). Reset and updated by '
            'every test run; do not work in it.',
        'live': liveRoot.path,
        'updated': DateTime.now().toIso8601String(),
        'repos': {for (final e in heads.entries) e.key: e.value.toJson()},
      }),
    );
  }

  static Future<void> _takeLock(
    File lock,
    Duration timeout,
    void Function(String) log,
  ) async {
    final deadline = DateTime.now().add(timeout);
    var announced = false;
    while (true) {
      try {
        lock.parent.createSync(recursive: true);
        lock.createSync(exclusive: true);
        lock.writeAsStringSync(
          jsonEncode({
            'pid': pid,
            'started': DateTime.now().toIso8601String(),
            'cwd': Directory.current.path,
          }),
        );
        return;
      } on FileSystemException {
        final holder = _lockHolder(lock);
        if (holder == null || !_pidAlive(holder.pid)) {
          // Left by a run that ended without releasing it.
          try {
            lock.deleteSync();
          } on FileSystemException {
            // Taken over by another run in the meantime; try again.
          }
          continue;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw StateError(
            'The workspace clone is held by process ${holder.pid} since '
            '${holder.started} (${holder.cwd}); waited ${timeout.inMinutes} '
            'min. Lock file: ${lock.path}. Delete it only if that process '
            'is not a test run.',
          );
        }
        if (!announced) {
          log(
            'waiting for the clone, held by process ${holder.pid} '
            '(${holder.cwd}) since ${holder.started}',
          );
          announced = true;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  static ({int pid, String started, String cwd})? _lockHolder(File lock) {
    try {
      final json = jsonDecode(lock.readAsStringSync()) as Map<String, Object?>;
      return (
        pid: json['pid']! as int,
        started: json['started'] as String? ?? '?',
        cwd: json['cwd'] as String? ?? '?',
      );
    } catch (_) {
      // Being written right now, or unreadable: judged on the next round.
      return (pid: -1, started: '?', cwd: '?');
    }
  }

  static bool _pidAlive(int candidate) {
    if (candidate == pid) return true;
    if (candidate <= 0) return true;
    if (Platform.isWindows) {
      final r = Process.runSync('tasklist', [
        '/FI',
        'PID eq $candidate',
        '/NH',
      ]);
      return r.stdout.toString().contains('$candidate');
    }
    return Process.runSync('kill', ['-0', '$candidate']).exitCode == 0;
  }

  void _unlock() {
    try {
      final holder = _lockHolder(_lock);
      if (holder != null && holder.pid == pid) _lock.deleteSync();
    } on FileSystemException {
      // Already gone.
    }
  }

  // ---------------------------------------------------------------------------
  // git
  // ---------------------------------------------------------------------------

  static bool _hasGit(Directory dir) =>
      FileSystemEntity.typeSync(p.join(dir.path, '.git')) !=
      FileSystemEntityType.notFound;

  static Future<_Head> _liveHead(Directory dir) async => _Head(
    (await _git(dir, ['rev-parse', 'HEAD'])).trim(),
    await _branchOf(dir),
  );

  static Future<String?> _headOf(Directory dir) async => _hasGit(dir)
      ? (await _gitOrNull(dir, ['rev-parse', 'HEAD']))?.trim()
      : null;

  static Future<String?> _branchOf(Directory dir) async => (await _gitOrNull(
    dir,
    ['symbolic-ref', '--quiet', '--short', 'HEAD'],
  ))?.trim();

  static Future<String> _git(Directory dir, List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: dir.path);
    if (r.exitCode != 0) {
      throw StateError(
        'git ${args.join(' ')} failed in ${dir.path} (exit ${r.exitCode}): '
        '${r.stderr}',
      );
    }
    return r.stdout.toString();
  }

  static Future<String?> _gitOrNull(Directory dir, List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: dir.path);
    if (r.exitCode != 0) return null;
    return r.stdout.toString();
  }
}
