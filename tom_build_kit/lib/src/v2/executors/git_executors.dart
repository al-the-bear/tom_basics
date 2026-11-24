/// Native v2 executors for all git commands.
///
/// All git tools share a common pattern: run git commands per repository.
/// This file contains all git executors with shared helpers.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart'
    show ProcessRunner, ProcessRunResult;
import 'package:tom_build_base/tom_build_base_v2.dart';

// =============================================================================
// Git Helper
// =============================================================================

/// Run a git command and return the result.
Future<ProcessRunResult> _runGit(
  List<String> args,
  String workingDirectory, {
  bool verbose = false,
}) async {
  if (verbose) print('    git ${args.join(' ')}');
  return ProcessRunner.run('git', args, workingDirectory: workingDirectory);
}

/// Get current branch name.
Future<String?> _getCurrentBranch(String dir) async {
  final result = await _runGit(['rev-parse', '--abbrev-ref', 'HEAD'], dir);
  return result.exitCode == 0 ? result.stdout.trim() : null;
}

/// Get the options for a git command, written in EITHER position.
///
/// Was the ninth private copy of this lookup in this package. [commandNames]
/// already carries the command and its aliases, so the first is the name and
/// the rest are aliases.
Map<String, dynamic> _getGitCmdOpts(CliArgs args, List<String> commandNames) {
  if (commandNames.isEmpty) return args.extraOptions;
  return args.optionsFor(
    commandNames.first,
    aliases: commandNames.skip(1).toList(),
  );
}

// =============================================================================
// GitStatus Executor
// =============================================================================

/// The messages of `:gitstatus` (help topics `buildkit help <code>`).
final gitstatusMessages = MessageCatalog([
  const MessageDefinition(
    code: 'git-detached',
    level: MessageLevel.warning,
    label: 'DETACHED',
    summary: 'A repository is on a detached HEAD, not on its branch.',
    description:
        'Commits made there are on no branch; a later checkout leaves them '
        'behind. Put the repository back on its branch (git switch <branch>) '
        'after keeping the commits on a branch of their own, if it has any.',
  ),
  const MessageDefinition(
    code: 'git-off-branch',
    level: MessageLevel.warning,
    label: 'OFF BRANCH',
    summary:
        'A repository is on another branch than repos.yaml (or '
        '_ai/quests.yaml) expects.',
    description:
        'The fleet skills and the :ws-* commands merge and push the expected '
        'branch. Switch back (git switch <branch>), or record the branch the '
        "repository should follow in its entry's branch: in repos.yaml.",
  ),
  const MessageDefinition(
    code: 'git-off-pin',
    level: MessageLevel.warning,
    label: 'OFF PIN',
    summary: 'An upstream clone is not at the commit repos.yaml pins it to.',
    description:
        'An upstream (a third-party project) is checked out at its pin: '
        'git checkout <pin>, or record the new commit as its pin: in '
        'repos.yaml.',
  ),
  const MessageDefinition(
    code: 'git-no-remote-branch',
    level: MessageLevel.warning,
    label: 'NO REMOTE',
    summary: 'origin has no branch to compare the repository with.',
    description:
        'origin/<expected branch> is not there (never pushed, or the last '
        'fetch failed), so ahead and behind cannot be counted. Push the '
        'branch (buildkit :gitpush), or check the remote.',
  ),
]);

/// One repository's state as `:gitstatus` reports it.
class GitRepoStatus {
  GitRepoStatus({
    required this.path,
    required this.relPath,
    required this.name,
    this.repo,
  });

  final String path;

  /// From the root of the run ('' for the root).
  final String relPath;
  final String name;
  final RepoSetMember? repo;

  String? branch;
  String? head;
  String? expected;
  String? expectedFrom;
  int changes = 0;
  int? ahead;
  int? behind;
  int? stashes;
  String? error;

  bool get detached => branch == null && head != null;
  bool get offBranch =>
      !detached && expected != null && branch != null && branch != expected;
  bool get isUpstream => repo?.kind == RepoKind.upstream;
  bool get offPin =>
      isUpstream && repo!.pin != null && head != null && head != repo!.pin;

  Map<String, Object?> toJson() => {
    'path': relPath.isEmpty ? '.' : relPath,
    'name': name,
    'kind': repo?.kindName,
    'class': repo?.repoClass.name,
    'branch': branch,
    'detached': detached,
    'head': head,
    'expectedBranch': expected,
    'expectedFrom': expectedFrom,
    'offBranch': offBranch,
    'compareWith': expected == null ? null : 'origin/$expected',
    'ahead': ahead,
    'behind': behind,
    'changes': changes,
    if (stashes != null) 'stashes': stashes,
    if (isUpstream) 'pin': repo!.pin,
    if (isUpstream) 'offPin': offPin,
    if (error != null) 'error': error,
  };
}

/// Shows the state of every repository of the run: branch, uncommitted
/// changes, ahead / behind `origin/<expected branch>` (the branch repos.yaml
/// or `_ai/quests.yaml` names; else the branch checked out), a detached
/// HEAD, a repository off its branch, an upstream off its pin. `--json`: one
/// document (the run report with every repository's state).
///
/// It walks the repositories itself (the git traversal of tom_build_base:
/// the combined repository set of repos.yaml, else the folders), so the
/// JSON on stdout is the only output; `-w` covers the nested workspaces in
/// the same run. The upstreams of the set are listed too (never fetched).
class GitStatusExecutor extends CommandExecutor {
  GitStatusExecutor({StringSink? out}) : _out = out;
  final StringSink? _out;

  @override
  bool get handlesListMode => true;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.failure(
        path: context.path,
        name: context.name,
        error: 'gitstatus runs without the traversal',
      );

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final out = _out ?? stdout;
    final opts = _getGitCmdOpts(args, ['gitstatus', 'gs']);
    final detailed = opts['details'] == true;
    final noFetch = opts['no-fetch'] == true || args.dryRun;
    final showStash = opts['stash'] == true;
    final json = opts['json'] == true;
    final start = p.normalize(p.absolute(args.root ?? Directory.current.path));
    final started = DateTime.now();

    final info = args.toGitTraversalInfo(
      executionRoot: start,
      commandDefaultGitOrder: GitTraversalOrder.innerFirst,
    )!;

    // The repositories: the walk prints its skip notes; on stdout they would
    // break the JSON, so they go to stderr.
    final contexts = <CommandContext>[];
    RepoSet? set;
    try {
      set = RepoSet.discover(start, manifestPath: info.manifestPath);
      await runZoned(
        () => _collect(info, args.workspaceRecursion, contexts),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => stderr.writeln(line),
        ),
      );
    } on ReposManifestException catch (e) {
      out.writeln('Error: $e');
      return ToolResult.failure('$e');
    }

    final root = set?.root ?? start;
    String rel(String path) => path == root
        ? ''
        : p.isWithin(root, path)
        ? p.relative(path, from: root).replaceAll(r'\', '/')
        : path;
    final statuses = [
      for (final c in contexts)
        GitRepoStatus(
          path: c.path,
          relPath: rel(c.path),
          name: c.name,
          repo: c.repo,
        ),
    ];
    // The upstreams of the set in the same scope: listed, never fetched.
    if (set != null) {
      final covered = {for (final c in contexts) c.path};
      for (final m in set.members) {
        if (m.kind != RepoKind.upstream || !m.onDisk) continue;
        if (m.path != start && !p.isWithin(start, m.path)) continue;
        if (!covered.any((c) => m.path == c || p.isWithin(c, m.path))) continue;
        statuses.add(
          GitRepoStatus(
            path: m.path,
            relPath: m.relPath,
            name: p.basename(m.path),
            repo: m,
          ),
        );
      }
    }

    if (args.listOnly) {
      for (final s in statuses) {
        out.writeln(s.relPath.isEmpty ? '.' : s.relPath);
      }
      return const ToolResult.success();
    }

    // Eight repositories at a time: fetching is most of the time.
    for (var i = 0; i < statuses.length; i += 8) {
      await Future.wait([
        for (final s in statuses.skip(i).take(8))
          _measure(s, fetch: !noFetch && !s.isUpstream, stash: showStash),
      ]);
    }

    final names = RepoNames([for (final s in statuses) s.relPath]);
    final report = RunReport(
      tool: 'buildkit',
      command: ':gitstatus',
      root: root,
      host: set?.host ?? Platform.localHostname,
      started: started,
      given: [
        for (final MapEntry(:key, :value) in opts.entries)
          if (value == true)
            '--$key'
          else if (value is String) ...[
            '--$key',
            value,
          ],
      ],
      names: names,
    )..lookedAt.addAll(statuses.map((s) => s.relPath));
    for (final s in statuses) {
      for (final m in _messages(s)) {
        report.add(m);
      }
    }

    final failures = [
      for (final s in statuses)
        if (s.error != null) s,
    ];
    if (json) {
      out.writeln(
        const JsonEncoder.withIndent('  ').convert({
          ...report.toJson(),
          'repositories': [for (final s in statuses) s.toJson()],
        }),
      );
    } else {
      for (final s in statuses) {
        out.writeln('  ${s.relPath.isEmpty ? '.' : s.relPath}: ${_line(s)}');
        if (detailed && s.changes > 0) {
          final status = await _runGit(['status', '--porcelain'], s.path);
          for (final line in status.stdout.trimRight().split('\n')) {
            out.writeln('      $line');
          }
        }
      }
      for (final m in report.messages) {
        out.writeln(
          '  ${m.definition.label.toLowerCase()} ${m.repository == null ? '' : (m.repository!.isEmpty ? '.' : m.repository)}: '
          '${m.finding}  [${m.code}]',
        );
      }
    }
    return failures.isEmpty
        ? const ToolResult.success()
        : ToolResult.failure(
            '${failures.length} repositories could not be read: '
            '${failures.map((s) => s.relPath.isEmpty ? '.' : s.relPath).join(', ')}',
          );
  }

  /// The repositories of [info], and with [recursive] those of the nested
  /// workspaces the walk stopped at.
  static Future<void> _collect(
    GitTraversalInfo info,
    bool recursive,
    List<CommandContext> into,
  ) async {
    final result = await BuildBase.traverse(
      info: info,
      worksWithNatures: const {FsFolder},
      run: (context) async {
        into.add(context);
        return true;
      },
    );
    if (!recursive) return;
    for (final ws in result.skippedWorkspaces) {
      await _collect(info.copyWith(executionRoot: ws), recursive, into);
    }
  }

  static Future<void> _measure(
    GitRepoStatus s, {
    required bool fetch,
    required bool stash,
  }) async {
    final dir = s.path;
    try {
      if (fetch) await _runGit(['fetch', '--quiet', 'origin'], dir);
      final branch = (await _runGit([
        'symbolic-ref',
        '--short',
        '-q',
        'HEAD',
      ], dir)).stdout.trim();
      s.branch = branch.isEmpty ? null : branch;
      final head = await _runGit(['rev-parse', 'HEAD'], dir);
      s.head = head.exitCode == 0 ? head.stdout.trim() : null;
      if (s.repo?.expectedBranch != null) {
        s.expected = s.repo!.expectedBranch;
        s.expectedFrom = s.repo!.repoClass == RepoClass.questClone
            ? '_ai/quests.yaml'
            : 'repos.yaml';
      } else if (!s.isUpstream) {
        s.expected = s.branch;
        s.expectedFrom = s.branch == null ? null : 'checked out';
      }
      final status = await _runGit(['status', '--porcelain'], dir);
      final lines = status.stdout.trim();
      s.changes = lines.isEmpty ? 0 : lines.split('\n').length;
      if (s.expected != null) {
        final ref = 'refs/remotes/origin/${s.expected}';
        final known = await _runGit(['rev-parse', '--verify', '-q', ref], dir);
        if (known.exitCode == 0) {
          final counts = await _runGit([
            'rev-list',
            '--left-right',
            '--count',
            'HEAD...$ref',
          ], dir);
          final parts = counts.stdout.trim().split(RegExp(r'\s+'));
          if (counts.exitCode == 0 && parts.length == 2) {
            s.ahead = int.tryParse(parts[0]);
            s.behind = int.tryParse(parts[1]);
          }
        }
      }
      if (stash) {
        final list = (await _runGit(['stash', 'list'], dir)).stdout.trim();
        s.stashes = list.isEmpty ? 0 : list.split('\n').length;
      }
    } catch (e) {
      s.error = '$e';
    }
  }

  static String _short(String? sha) =>
      sha == null ? '?' : (sha.length > 7 ? sha.substring(0, 7) : sha);

  static String _line(GitRepoStatus s) {
    if (s.error != null) return 'ERROR ${s.error}';
    final parts = <String>[];
    if (s.isUpstream) {
      parts.add('[upstream at ${_short(s.head)}]');
      parts.add(s.offPin ? 'off its pin ${_short(s.repo!.pin)}' : 'at its pin');
    } else {
      parts.add(
        s.detached ? '[detached at ${_short(s.head)}]' : '[${s.branch}]',
      );
      if (s.offBranch) parts.add('expected ${s.expected}');
    }
    if (s.changes > 0) parts.add('${s.changes} changed');
    if (s.ahead != null && s.behind != null) {
      if (s.ahead! > 0) parts.add('${s.ahead} ahead');
      if (s.behind! > 0) parts.add('${s.behind} behind');
      if (s.ahead == 0 && s.behind == 0) {
        parts.add('even with origin/${s.expected}');
      } else {
        parts.add('of origin/${s.expected}');
      }
    } else if (s.expected != null && !s.isUpstream) {
      parts.add('no origin/${s.expected}');
    }
    if (s.stashes != null && s.stashes! > 0) parts.add('${s.stashes} stashed');
    if (s.changes == 0 &&
        (s.ahead ?? 0) == 0 &&
        (s.behind ?? 0) == 0 &&
        !s.isUpstream) {
      parts.add('clean');
    }
    return parts.join(', ');
  }

  static List<ReportMessage> _messages(GitRepoStatus s) {
    final out = <ReportMessage>[];
    if (s.error != null) return out;
    if (s.detached && !s.isUpstream) {
      out.add(
        gitstatusMessages['git-detached'].raise(
          repository: s.relPath,
          finding:
              'detached at ${_short(s.head)}'
              '${s.expected == null ? '' : ', expected on ${s.expected}'}',
        ),
      );
    }
    if (s.offBranch) {
      out.add(
        gitstatusMessages['git-off-branch'].raise(
          repository: s.relPath,
          branch: s.branch,
          finding: 'on ${s.branch}, ${s.expectedFrom} expects ${s.expected}',
        ),
      );
    }
    if (s.offPin) {
      out.add(
        gitstatusMessages['git-off-pin'].raise(
          repository: s.relPath,
          finding: 'at ${_short(s.head)}, pinned to ${_short(s.repo!.pin)}',
        ),
      );
    }
    if (!s.isUpstream && s.expected != null && s.ahead == null) {
      out.add(
        gitstatusMessages['git-no-remote-branch'].raise(
          repository: s.relPath,
          finding: 'no origin/${s.expected} to compare with',
        ),
      );
    }
    return out;
  }
}

// =============================================================================
// GitCommit Executor
// =============================================================================

/// Commits in each repository what you name: `--only <paths>` stages and
/// commits exactly those paths (the others stay as they are, staged or
/// not); `--all` stages every change first (`git add -A`); without either
/// nothing is staged and what is already staged is committed.
class GitCommitExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitcommit', 'gc']);
    final message = opts['message']?.toString();
    final amend = opts['amend'] == true;
    final push = opts['push'] == true;
    final stageAll = opts['all'] == true;
    final only = _stringList(opts['only']);

    if (stageAll && only.isNotEmpty) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: '--only and --all exclude each other',
      );
    }

    // --only: the given paths that belong to this repository and have
    // changes in it (a path of another repository of the run is not this
    // one's).
    final paths = only.isEmpty
        ? const <String>[]
        : await _ownChangedPaths(dir, only);
    if (only.isNotEmpty && paths.isEmpty && !amend) {
      print(
        '  ${context.name}: nothing to commit (no --only path changed here)',
      );
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'nothing to commit',
      );
    }

    final changed = (await _runGit([
      'status',
      '--porcelain',
    ], dir)).stdout.trim().isNotEmpty;
    final staged =
        (await _runGit(['diff', '--cached', '--quiet'], dir)).exitCode != 0;
    if (only.isEmpty && !amend && !(stageAll ? changed : staged)) {
      final why = !changed
          ? 'nothing to commit'
          : 'nothing staged (name the paths with --only, or --all)';
      print('  ${context.name}: $why');
      return ItemResult.success(path: dir, name: context.name, message: why);
    }

    if (args.dryRun) {
      final what = paths.isNotEmpty
          ? '${paths.length} path(s)'
          : stageAll
          ? 'every change'
          : 'what is staged';
      final action = amend ? 'amend' : 'commit "${message ?? "..."}"';
      print(
        '  [DRY RUN] ${context.name}: $action of $what${push ? ' + push' : ''}',
      );
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'dry-run',
      );
    }

    if (stageAll) {
      await _runGit(['add', '-A'], dir, verbose: args.verbose);
    } else if (paths.isNotEmpty) {
      // Untracked files are made known, so `commit --only` can take them.
      await _runGit(['add', '-N', '--', ...paths], dir, verbose: args.verbose);
    }

    final ProcessRunResult result;
    if (amend) {
      result = await _runGit(
        [
          'commit',
          '--amend',
          '--no-edit',
          if (paths.isNotEmpty) ...['--only', '--', ...paths],
        ],
        dir,
        verbose: args.verbose,
      );
    } else {
      if (message == null || message.isEmpty) {
        return ItemResult.failure(
          path: dir,
          name: context.name,
          error: 'no commit message (-m)',
        );
      }
      result = await _runGit(
        [
          'commit',
          if (paths.isNotEmpty) '--only',
          '-m',
          message,
          if (paths.isNotEmpty) ...['--', ...paths],
        ],
        dir,
        verbose: args.verbose,
      );
    }
    if (result.exitCode != 0) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error:
            '${amend ? 'amend' : 'commit'} failed: ${result.stderr.trim()}'
            '${result.stdout.trim().isEmpty ? '' : ' ${result.stdout.trim()}'}',
      );
    }
    print('  ${context.name}: ${amend ? 'amended' : 'committed "$message"'}');

    if (push) {
      final pushed = await _pushCurrentBranch(dir, verbose: args.verbose);
      print('    ${pushed.message}');
      if (!pushed.ok) {
        return ItemResult.failure(
          path: dir,
          name: context.name,
          error: 'committed, but ${pushed.message}',
        );
      }
    }

    return ItemResult.success(
      path: dir,
      name: context.name,
      message: 'committed',
    );
  }
}

/// [value] of a multi option as strings (a single string, a list, or
/// comma-separated).
List<String> _stringList(Object? value) => [
  for (final v in switch (value) {
    final List<dynamic> list => list,
    final String one => [one],
    _ => const <dynamic>[],
  })
    for (final part in '$v'.split(','))
      if (part.trim().isNotEmpty) part.trim(),
];

/// Of [paths] (absolute, or relative to the repository [dir]), those inside
/// [dir] that have changes there, relative to [dir] with `/`.
Future<List<String>> _ownChangedPaths(String dir, List<String> paths) async {
  final out = <String>[];
  for (final raw in paths) {
    final abs = p.normalize(p.isAbsolute(raw) ? raw : p.join(dir, raw));
    if (abs != dir && !p.isWithin(dir, abs)) continue;
    final rel = abs == dir
        ? '.'
        : p.relative(abs, from: dir).replaceAll(r'\', '/');
    final status = await _runGit(['status', '--porcelain', '--', rel], dir);
    if (status.exitCode == 0 && status.stdout.trim().isNotEmpty) out.add(rel);
  }
  return out;
}

/// Pushes the checked-out branch of [dir] to `origin` (setting its upstream
/// when it has none); never forced. A detached `HEAD` is not pushed.
Future<({bool ok, String message})> _pushCurrentBranch(
  String dir, {
  bool verbose = false,
}) async {
  final branch = (await _runGit([
    'symbolic-ref',
    '--short',
    '-q',
    'HEAD',
  ], dir)).stdout.trim();
  if (branch.isEmpty) {
    return (
      ok: false,
      message: 'not pushed: detached HEAD (check out a branch)',
    );
  }
  final hasUpstream =
      (await _runGit([
        'rev-parse',
        '--abbrev-ref',
        '--symbolic-full-name',
        '@{u}',
      ], dir)).exitCode ==
      0;
  final result = await _runGit(
    ['push', if (!hasUpstream) '--set-upstream', 'origin', branch],
    dir,
    verbose: verbose,
  );
  final text = '${result.stderr}\n${result.stdout}'.trim();
  if (result.exitCode != 0) {
    final rejected =
        text.contains('[rejected]') || text.contains('non-fast-forward');
    final first = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(3)
        .join(' | ');
    return (
      ok: false,
      message: rejected
          ? 'push of $branch rejected: origin has commits this branch lacks '
                '(merge origin/$branch, then push again; nothing is forced): $first'
          : 'push of $branch failed: $first',
    );
  }
  return (
    ok: true,
    message: text.contains('Everything up-to-date')
        ? '$branch: up to date with origin'
        : 'pushed $branch to origin',
  );
}

// =============================================================================
// GitPush Executor
// =============================================================================

/// Pushes the checked-out branch of each repository to `origin`, never
/// forced; a rejected push is reported as a failure of that repository.
class GitPushExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    if (args.dryRun) {
      final branch = await _getCurrentBranch(dir) ?? '?';
      print('  [DRY RUN] ${context.name}: push $branch to origin');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'dry-run',
      );
    }
    final pushed = await _pushCurrentBranch(dir, verbose: args.verbose);
    print('  ${context.name}: ${pushed.message}');
    return pushed.ok
        ? ItemResult.success(
            path: dir,
            name: context.name,
            message: pushed.message,
          )
        : ItemResult.failure(
            path: dir,
            name: context.name,
            error: pushed.message,
          );
  }
}

// =============================================================================
// GitPull Executor
// =============================================================================

/// Pulls latest from each repository.
class GitPullExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitpull', 'gpl']);
    final rebase = opts['rebase'] == true;
    final ffOnly = opts['ff-only'] == true;

    if (args.dryRun) {
      final mode = rebase ? '--rebase' : (ffOnly ? '--ff-only' : 'merge');
      print('  [DRY RUN] ${context.name}: pull ($mode)');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'dry-run',
      );
    }

    final pullArgs = ['pull'];
    if (rebase) {
      pullArgs.add('--rebase');
    } else if (ffOnly) {
      pullArgs.add('--ff-only');
    }

    final result = await _runGit(pullArgs, dir, verbose: args.verbose);
    final output = result.stdout.trim();

    if (result.exitCode != 0) {
      final stderr = result.stderr.trim();
      print('  ${context.name}: pull failed');
      if (args.verbose && stderr.isNotEmpty) print('    $stderr');
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'pull failed',
      );
    }

    final isUpToDate = output.contains('Already up to date');
    print('  ${context.name}: ${isUpToDate ? 'up to date' : 'pulled'}');
    return ItemResult.success(
      path: dir,
      name: context.name,
      message: isUpToDate ? 'up to date' : 'pulled',
    );
  }
}

// =============================================================================
// GitBranch Executor
// =============================================================================

/// Branch management across repositories.
class GitBranchExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitbranch', 'gb']);
    final create = opts['create']?.toString();
    final delete = opts['delete']?.toString();
    final showAll = opts['all'] == true;

    if (create != null) {
      if (args.dryRun) {
        print('  [DRY RUN] ${context.name}: create branch $create');
        return ItemResult.success(
          path: dir,
          name: context.name,
          message: 'dry-run',
        );
      }
      final result = await _runGit(['checkout', '-b', create], dir);
      if (result.exitCode != 0) {
        return ItemResult.failure(
          path: dir,
          name: context.name,
          error: 'create branch failed',
        );
      }
      print('  ${context.name}: created $create');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'created $create',
      );
    }

    if (delete != null) {
      if (args.dryRun) {
        print('  [DRY RUN] ${context.name}: delete branch $delete');
        return ItemResult.success(
          path: dir,
          name: context.name,
          message: 'dry-run',
        );
      }
      final result = await _runGit(['branch', '-d', delete], dir);
      if (result.exitCode != 0) {
        return ItemResult.failure(
          path: dir,
          name: context.name,
          error: 'delete branch failed',
        );
      }
      print('  ${context.name}: deleted $delete');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'deleted $delete',
      );
    }

    // List branches
    final branchArgs = showAll ? ['branch', '-a'] : ['branch'];
    final result = await _runGit(branchArgs, dir);
    final output = result.stdout.trim();
    print('  ${context.name}:');
    for (final line in output.split('\n')) {
      print('    $line');
    }
    return ItemResult.success(path: dir, name: context.name, message: 'listed');
  }
}

// =============================================================================
// GitTag Executor
// =============================================================================

/// Tag management across repositories.
class GitTagExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gittag', 'gt']);
    final create = opts['create']?.toString();
    final delete = opts['delete']?.toString();
    final message = opts['message']?.toString();
    final pushTags = opts['push'] == true;

    if (create != null) {
      if (args.dryRun) {
        print('  [DRY RUN] ${context.name}: create tag $create');
        return ItemResult.success(
          path: dir,
          name: context.name,
          message: 'dry-run',
        );
      }
      final tagArgs = message != null
          ? ['tag', '-a', create, '-m', message]
          : ['tag', create];
      final result = await _runGit(tagArgs, dir);
      if (result.exitCode != 0) {
        return ItemResult.failure(
          path: dir,
          name: context.name,
          error: 'create tag failed',
        );
      }
      print('  ${context.name}: tagged $create');
      if (pushTags) {
        await _runGit(['push', '--tags'], dir);
      }
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'tagged $create',
      );
    }

    if (delete != null) {
      if (args.dryRun) {
        print('  [DRY RUN] ${context.name}: delete tag $delete');
        return ItemResult.success(
          path: dir,
          name: context.name,
          message: 'dry-run',
        );
      }
      await _runGit(['tag', '-d', delete], dir);
      print('  ${context.name}: deleted tag $delete');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'deleted $delete',
      );
    }

    // List tags
    final result = await _runGit(['tag', '-l'], dir);
    final output = result.stdout.trim();
    if (output.isEmpty) {
      print('  ${context.name}: no tags');
    } else {
      print('  ${context.name}: ${output.split('\n').join(', ')}');
    }
    return ItemResult.success(path: dir, name: context.name, message: 'listed');
  }
}

// =============================================================================
// GitCheckout Executor
// =============================================================================

/// Checkout branches/tags across repositories.
class GitCheckoutExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitcheckout', 'gco']);
    final branch = opts['branch']?.toString();
    final createNew = opts['create'] == true;

    if (branch == null) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'no branch specified',
      );
    }

    if (args.dryRun) {
      print('  [DRY RUN] ${context.name}: checkout $branch');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'dry-run',
      );
    }

    final checkoutArgs = createNew
        ? ['checkout', '-b', branch]
        : ['checkout', branch];
    final result = await _runGit(checkoutArgs, dir);

    if (result.exitCode != 0) {
      final stderr = result.stderr.trim();
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'checkout failed: $stderr',
      );
    }

    print('  ${context.name}: checked out $branch');
    return ItemResult.success(
      path: dir,
      name: context.name,
      message: 'checked out $branch',
    );
  }
}

// =============================================================================
// GitReset Executor
// =============================================================================

/// Reset repositories to specific state.
class GitResetExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitreset', 'grst']);
    final hard = opts['hard'] == true;
    final soft = opts['soft'] == true;
    final toRef = opts['to']?.toString();

    final resetArgs = ['reset'];
    if (hard) resetArgs.add('--hard');
    if (soft) resetArgs.add('--soft');
    if (toRef != null) resetArgs.add(toRef);

    if (args.dryRun) {
      print('  [DRY RUN] ${context.name}: git ${resetArgs.join(' ')}');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'dry-run',
      );
    }

    final result = await _runGit(resetArgs, dir);
    if (result.exitCode != 0) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'reset failed',
      );
    }
    print(
      '  ${context.name}: reset${hard
          ? ' (hard)'
          : soft
          ? ' (soft)'
          : ''}',
    );
    return ItemResult.success(path: dir, name: context.name, message: 'reset');
  }
}

// =============================================================================
// GitClean Executor
// =============================================================================

/// Clean untracked files from repositories.
class GitCleanExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitclean', 'gcl']);
    final directories = opts['directories'] == true;
    final force = opts['force'] == true || args.force;

    final cleanArgs = ['clean'];
    if (force) cleanArgs.add('-f');
    if (directories) cleanArgs.add('-d');

    if (args.dryRun) {
      // Show what would be cleaned
      final dryResult = await _runGit([...cleanArgs, '-n'], dir);
      final output = dryResult.stdout.trim();
      if (output.isEmpty) {
        print('  ${context.name}: nothing to clean');
      } else {
        print('  [DRY RUN] ${context.name}:');
        for (final line in output.split('\n')) {
          print('    $line');
        }
      }
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'dry-run',
      );
    }

    final result = await _runGit(cleanArgs, dir);
    if (result.exitCode != 0) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'clean failed',
      );
    }
    print('  ${context.name}: cleaned');
    return ItemResult.success(
      path: dir,
      name: context.name,
      message: 'cleaned',
    );
  }
}

// =============================================================================
// GitSync Executor
// =============================================================================

/// Sync (fetch + merge/rebase) all repositories.
class GitSyncExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitsync', 'gsync']);
    final rebase = opts['rebase'] == true;

    if (args.dryRun) {
      print('  [DRY RUN] ${context.name}: sync${rebase ? ' (rebase)' : ''}');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'dry-run',
      );
    }

    // Fetch
    await _runGit(['fetch', '--all'], dir, verbose: args.verbose);

    // Pull
    final pullArgs = rebase ? ['pull', '--rebase'] : ['pull'];
    final result = await _runGit(pullArgs, dir);
    if (result.exitCode != 0) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'sync failed',
      );
    }

    print('  ${context.name}: synced');
    return ItemResult.success(path: dir, name: context.name, message: 'synced');
  }
}

// =============================================================================
// GitPrune Executor
// =============================================================================

/// Remove stale remote-tracking branches.
class GitPruneExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitprune', 'gpr']);
    final remote = opts['remote']?.toString() ?? 'origin';

    if (args.dryRun) {
      print('  [DRY RUN] ${context.name}: prune $remote');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'dry-run',
      );
    }

    final result = await _runGit(
      ['remote', 'prune', remote],
      dir,
      verbose: args.verbose,
    );
    if (result.exitCode != 0) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'prune failed',
      );
    }
    print('  ${context.name}: pruned $remote');
    return ItemResult.success(path: dir, name: context.name, message: 'pruned');
  }
}

// =============================================================================
// GitStash Executor
// =============================================================================

/// Stash uncommitted changes.
class GitStashExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitstash', 'gst']);
    final message = opts['message']?.toString();
    final includeUntracked = opts['include-untracked'] == true;

    if (args.dryRun) {
      print(
        '  [DRY RUN] ${context.name}: stash${message != null ? ' "$message"' : ''}',
      );
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'dry-run',
      );
    }

    final stashArgs = ['stash', 'push'];
    if (includeUntracked) stashArgs.add('--include-untracked');
    if (message != null) stashArgs.addAll(['-m', message]);

    final result = await _runGit(stashArgs, dir);
    final output = result.stdout.trim();
    final nothingToStash = output.contains('No local changes');

    if (nothingToStash) {
      print('  ${context.name}: nothing to stash');
    } else {
      print('  ${context.name}: stashed');
    }
    return ItemResult.success(
      path: dir,
      name: context.name,
      message: nothingToStash ? 'nothing to stash' : 'stashed',
    );
  }
}

// =============================================================================
// GitUnstash Executor
// =============================================================================

/// Restore stashed changes.
class GitUnstashExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitunstash', 'gust']);
    final pop = opts['pop'] == true;
    final index = opts['index']?.toString();

    if (args.dryRun) {
      print('  [DRY RUN] ${context.name}: ${pop ? 'pop' : 'apply'} stash');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'dry-run',
      );
    }

    final stashArgs = ['stash', pop ? 'pop' : 'apply'];
    if (index != null) stashArgs.add('stash@{$index}');

    final result = await _runGit(stashArgs, dir);
    if (result.exitCode != 0) {
      final stderr = result.stderr.trim();
      if (stderr.contains('No stash entries')) {
        print('  ${context.name}: no stash entries');
        return ItemResult.success(
          path: dir,
          name: context.name,
          message: 'no stash',
        );
      }
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'unstash failed',
      );
    }
    print('  ${context.name}: ${pop ? 'popped' : 'applied'} stash');
    return ItemResult.success(
      path: dir,
      name: context.name,
      message: pop ? 'popped' : 'applied',
    );
  }
}

// =============================================================================
// GitCompare Executor
// =============================================================================

/// Compare branches across repositories.
class GitCompareExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitcompare', 'gcmp']);
    final base = opts['base']?.toString() ?? 'main';
    final statOnly = opts['stat'] == true;

    final diffArgs = statOnly
        ? ['diff', '--stat', '$base..HEAD']
        : ['diff', '--shortstat', '$base..HEAD'];

    final result = await _runGit(diffArgs, dir);
    final output = result.stdout.trim();

    if (output.isEmpty) {
      print('  ${context.name}: no differences from $base');
    } else {
      print('  ${context.name} (vs $base):');
      for (final line in output.split('\n')) {
        print('    $line');
      }
    }
    return ItemResult.success(
      path: dir,
      name: context.name,
      message: 'compared with $base',
    );
  }
}

// =============================================================================
// GitMerge Executor
// =============================================================================

/// Merge branches across repositories.
class GitMergeExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitmerge', 'gm']);
    final branch = opts['branch']?.toString();
    final noFf = opts['no-ff'] == true;
    final squash = opts['squash'] == true;

    if (branch == null) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'no branch to merge',
      );
    }

    if (args.dryRun) {
      print('  [DRY RUN] ${context.name}: merge $branch');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'dry-run',
      );
    }

    final mergeArgs = ['merge', branch];
    if (noFf) mergeArgs.add('--no-ff');
    if (squash) mergeArgs.add('--squash');

    final result = await _runGit(mergeArgs, dir);
    if (result.exitCode != 0) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'merge failed',
      );
    }
    print('  ${context.name}: merged $branch');
    return ItemResult.success(
      path: dir,
      name: context.name,
      message: 'merged $branch',
    );
  }
}

// =============================================================================
// GitSquash Executor
// =============================================================================

/// Squash commits across repositories.
class GitSquashExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitsquash', 'gsq']);
    final count = int.tryParse(opts['count']?.toString() ?? '');
    final message = opts['message']?.toString();

    if (count == null || count < 2) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'specify --count >= 2',
      );
    }

    if (args.dryRun) {
      print('  [DRY RUN] ${context.name}: squash last $count commits');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'dry-run',
      );
    }

    // Soft reset to squash
    final resetResult = await _runGit(['reset', '--soft', 'HEAD~$count'], dir);
    if (resetResult.exitCode != 0) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'squash reset failed',
      );
    }

    // Commit with message
    final commitArgs = ['commit', '-m', message ?? 'squashed $count commits'];
    final commitResult = await _runGit(commitArgs, dir);
    if (commitResult.exitCode != 0) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'squash commit failed',
      );
    }

    print('  ${context.name}: squashed $count commits');
    return ItemResult.success(
      path: dir,
      name: context.name,
      message: 'squashed $count',
    );
  }
}

// =============================================================================
// GitRebase Executor
// =============================================================================

/// Rebase across repositories.
class GitRebaseExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitrebase', 'grb']);
    final onto = opts['onto']?.toString();
    final interactive = opts['interactive'] == true;
    final continueRebase = opts['continue'] == true;
    final abort = opts['abort'] == true;

    if (continueRebase) {
      if (args.dryRun) {
        print('  [DRY RUN] ${context.name}: would continue rebase');
        return ItemResult.success(
          path: dir,
          name: context.name,
          message: 'dry-run',
        );
      }
      final result = await _runGit(['rebase', '--continue'], dir);
      final success = result.exitCode == 0;
      print(
        '  ${context.name}: rebase ${success ? 'continued' : 'continue failed'}',
      );
      return success
          ? ItemResult.success(
              path: dir,
              name: context.name,
              message: 'continued',
            )
          : ItemResult.failure(
              path: dir,
              name: context.name,
              error: 'continue failed',
            );
    }

    if (abort) {
      if (args.dryRun) {
        print('  [DRY RUN] ${context.name}: would abort rebase');
        return ItemResult.success(
          path: dir,
          name: context.name,
          message: 'dry-run',
        );
      }
      await _runGit(['rebase', '--abort'], dir);
      print('  ${context.name}: rebase aborted');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'aborted',
      );
    }

    if (onto == null) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'no --onto branch specified',
      );
    }

    if (args.dryRun) {
      print('  [DRY RUN] ${context.name}: rebase onto $onto');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'dry-run',
      );
    }

    final rebaseArgs = ['rebase'];
    if (interactive) rebaseArgs.add('-i');
    rebaseArgs.add(onto);

    final result = await _runGit(rebaseArgs, dir);
    if (result.exitCode != 0) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'rebase failed',
      );
    }
    print('  ${context.name}: rebased onto $onto');
    return ItemResult.success(
      path: dir,
      name: context.name,
      message: 'rebased onto $onto',
    );
  }
}

// =============================================================================
// Git Passthrough Executor
// =============================================================================

/// Runs arbitrary git commands across repositories.
class GitPassthroughExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;

    // Get the git arguments from positional args (everything after --)
    final gitArgs = args.positionalArgs;
    if (gitArgs.isEmpty) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'no git command specified',
      );
    }

    if (args.dryRun) {
      print('  [DRY RUN] ${context.name}: git ${gitArgs.join(' ')}');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'dry-run',
      );
    }

    final result = await _runGit(gitArgs, dir, verbose: args.verbose);
    final output = result.stdout.trim();
    final stderr = result.stderr.trim();

    print('  ${context.name}:');
    if (output.isNotEmpty) {
      for (final line in output.split('\n')) {
        print('    $line');
      }
    }
    if (stderr.isNotEmpty && args.verbose) {
      for (final line in stderr.split('\n')) {
        print('    [err] $line');
      }
    }

    return result.exitCode == 0
        ? ItemResult.success(path: dir, name: context.name, message: 'ok')
        : ItemResult.failure(
            path: dir,
            name: context.name,
            error: 'git command failed (exit ${result.exitCode})',
          );
  }
}
