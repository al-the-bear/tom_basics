/// Native v2 executors for all git commands.
///
/// All git tools share a common pattern: run git commands per repository.
/// This file contains all git executors with shared helpers.
library;

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

/// Get per-command options for a git command.
Map<String, dynamic> _getGitCmdOpts(CliArgs args, List<String> commandNames) {
  for (final cmd in args.commands) {
    if (commandNames.contains(cmd)) {
      final cmdArgs = args.commandArgs[cmd];
      if (cmdArgs != null) return cmdArgs.options;
    }
  }
  return args.extraOptions;
}

// =============================================================================
// GitStatus Executor
// =============================================================================

/// Shows git status for each repository.
class GitStatusExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitstatus', 'gs']);
    final detailed = opts['details'] == true;
    final noFetch = opts['no-fetch'] == true;
    final showStash = opts['stash'] == true;

    try {
      // Fetch (unless --no-fetch)
      if (!noFetch && !args.dryRun) {
        await _runGit(
          ['fetch', '--all', '--quiet'],
          dir,
          verbose: args.verbose,
        );
      }

      final branch = await _getCurrentBranch(dir) ?? 'unknown';

      // Status
      final statusResult = await _runGit(['status', '--porcelain'], dir);
      final statusLines = statusResult.stdout.trim();
      final changes = statusLines.isEmpty ? 0 : statusLines.split('\n').length;

      // Unpushed
      var unpushed = 0;
      final logResult = await _runGit(['log', '@{u}..HEAD', '--oneline'], dir);
      if (logResult.exitCode == 0) {
        final logOut = logResult.stdout.trim();
        unpushed = logOut.isEmpty ? 0 : logOut.split('\n').length;
      }

      // Stash count
      var stashCount = 0;
      if (showStash) {
        final stashResult = await _runGit(['stash', 'list'], dir);
        if (stashResult.exitCode == 0) {
          final stashOut = stashResult.stdout.trim();
          stashCount = stashOut.isEmpty ? 0 : stashOut.split('\n').length;
        }
      }

      // Format output
      final parts = <String>[];
      parts.add('[$branch]');
      if (changes > 0) parts.add('$changes changed');
      if (unpushed > 0) parts.add('$unpushed unpushed');
      if (showStash && stashCount > 0) parts.add('$stashCount stashed');
      if (changes == 0 && unpushed == 0) parts.add('clean');

      print('  ${context.name}: ${parts.join(', ')}');

      if (detailed && statusLines.isNotEmpty) {
        for (final line in statusLines.split('\n')) {
          print('    $line');
        }
      }

      return ItemResult.success(
        path: dir,
        name: context.name,
        message: parts.join(', '),
      );
    } catch (e) {
      return ItemResult.failure(
        path: dir,
        name: context.name,
        error: 'git status failed: $e',
      );
    }
  }
}

// =============================================================================
// GitCommit Executor
// =============================================================================

/// Commits changes in each repository.
class GitCommitExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final dir = context.path;
    final opts = _getGitCmdOpts(args, ['gitcommit', 'gc']);
    final message = opts['message']?.toString();
    final amend = opts['amend'] == true;
    final push = opts['push'] == true;
    final stageAll = opts['all'] == true;

    // Check for changes
    final statusResult = await _runGit(['status', '--porcelain'], dir);
    final hasChanges = statusResult.stdout.trim().isNotEmpty;

    if (!hasChanges && !amend) {
      print('  ${context.name}: nothing to commit');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'nothing to commit',
      );
    }

    if (args.dryRun) {
      final action = amend ? 'amend' : 'commit "${message ?? "..."}"';
      print('  [DRY RUN] ${context.name}: $action${push ? ' + push' : ''}');
      return ItemResult.success(
        path: dir,
        name: context.name,
        message: 'dry-run',
      );
    }

    // Stage
    if (stageAll || hasChanges) {
      await _runGit(['add', '-A'], dir, verbose: args.verbose);
    }

    // Commit
    if (amend) {
      final result = await _runGit(
        ['commit', '--amend', '--no-edit'],
        dir,
        verbose: args.verbose,
      );
      if (result.exitCode != 0) {
        return ItemResult.failure(
          path: dir,
          name: context.name,
          error: 'amend failed',
        );
      }
      print('  ${context.name}: amended');
    } else {
      if (message == null || message.isEmpty) {
        return ItemResult.failure(
          path: dir,
          name: context.name,
          error: 'no commit message',
        );
      }
      final result = await _runGit(
        ['commit', '-m', message],
        dir,
        verbose: args.verbose,
      );
      if (result.exitCode != 0) {
        final stderr = result.stderr.trim();
        return ItemResult.failure(
          path: dir,
          name: context.name,
          error: 'commit failed: $stderr',
        );
      }
      print('  ${context.name}: committed "$message"');
    }

    // Push
    if (push) {
      final result = await _runGit(['push'], dir, verbose: args.verbose);
      if (result.exitCode != 0) {
        print('    Warning: push failed');
      } else {
        print('    pushed');
      }
    }

    return ItemResult.success(
      path: dir,
      name: context.name,
      message: 'committed',
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
