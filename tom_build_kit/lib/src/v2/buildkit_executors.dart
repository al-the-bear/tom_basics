/// Buildkit v2 command executors.
///
/// All buildkit commands are implemented as native v2 [CommandExecutor]s.
/// Project/git traversal is handled by the v2 ToolRunner framework based
/// on each command's [CommandDefinition.requiresTraversal] flag.
///
/// - Traversal executors implement [execute] (called per folder).
/// - Non-traversal executors implement [executeWithoutTraversal].
library;

import 'dart:io';

import 'package:tom_build_base/tom_build_base.dart';

import 'executors/buildsorter_executor.dart';
import 'executors/bumppubspec_executor.dart';
import 'executors/bumpversion_executor.dart';
import 'executors/cleanup_executor.dart';
import 'executors/compiler_executor.dart';
import 'executors/dependencies_executor.dart';
import 'executors/execute_executor.dart';
import 'executors/git_executors.dart';
import 'executors/findproject_executor.dart';
import 'executors/publisher_executor.dart';
import 'executors/runner_executor.dart';
import 'executors/status_executor.dart';
import 'executors/versioner_executor.dart';

// =============================================================================
// Pub Command Executors
// =============================================================================

/// Executor for :pubget - runs `dart pub get` or `flutter pub get` per project.
///
/// Uses framework traversal to work on each project individually.
/// Detects Flutter projects and uses appropriate command.
class PubGetExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final projectPath = context.path;

    // Detect if this is a Flutter project
    final isFlutter = context.hasNature<FlutterProjectFolder>();
    final executable = isFlutter ? 'flutter' : 'dart';

    if (args.dryRun) {
      print('  [DRY RUN] $executable pub get in ${context.name}');
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'dry-run',
      );
    }

    if (args.verbose) {
      print('  Running: $executable pub get');
      print('  Working directory: ${context.name}');
    }

    // Use streaming for live output
    final exitCode = await ProcessRunner.runStreaming(
      executable,
      ['pub', 'get'],
      workingDirectory: projectPath,
      runInShell: Platform.isWindows,
    );

    if (exitCode != 0) {
      return ItemResult.failure(
        path: projectPath,
        name: context.name,
        error: '$executable pub get failed (exit $exitCode)',
      );
    }

    return ItemResult.success(
      path: projectPath,
      name: context.name,
      message: 'pub get OK',
    );
  }
}

/// Executor for :pubgetall - alias for :pubget with full recursive.
///
/// Deprecated: Use `:pubget` which now defaults to recursive.
/// Kept for backwards compatibility.
class PubGetAllExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    // Delegate to same logic as PubGetExecutor
    final projectPath = context.path;
    final isFlutter = context.hasNature<FlutterProjectFolder>();
    final executable = isFlutter ? 'flutter' : 'dart';

    if (args.dryRun) {
      print('  [DRY RUN] $executable pub get in ${context.name}');
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'dry-run',
      );
    }

    if (args.verbose) {
      print('  Running: $executable pub get');
      print('  Working directory: ${context.name}');
    }

    final exitCode = await ProcessRunner.runStreaming(
      executable,
      ['pub', 'get'],
      workingDirectory: projectPath,
      runInShell: Platform.isWindows,
    );

    if (exitCode != 0) {
      return ItemResult.failure(
        path: projectPath,
        name: context.name,
        error: '$executable pub get failed (exit $exitCode)',
      );
    }

    return ItemResult.success(
      path: projectPath,
      name: context.name,
      message: 'pub get OK',
    );
  }
}

/// Executor for :pubupdate - runs `dart pub upgrade` or `flutter pub upgrade` per project.
///
/// Uses framework traversal to work on each project individually.
/// Detects Flutter projects and uses appropriate command.
class PubUpdateExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final projectPath = context.path;

    // Detect if this is a Flutter project
    final isFlutter = context.hasNature<FlutterProjectFolder>();
    final executable = isFlutter ? 'flutter' : 'dart';

    if (args.dryRun) {
      print('  [DRY RUN] $executable pub upgrade in ${context.name}');
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'dry-run',
      );
    }

    if (args.verbose) {
      print('  Running: $executable pub upgrade');
      print('  Working directory: ${context.name}');
    }

    // Use streaming for live output
    final exitCode = await ProcessRunner.runStreaming(
      executable,
      ['pub', 'upgrade'],
      workingDirectory: projectPath,
      runInShell: Platform.isWindows,
    );

    if (exitCode != 0) {
      return ItemResult.failure(
        path: projectPath,
        name: context.name,
        error: '$executable pub upgrade failed (exit $exitCode)',
      );
    }

    return ItemResult.success(
      path: projectPath,
      name: context.name,
      message: 'pub upgrade OK',
    );
  }
}

/// Executor for :pubupdateall - alias for :pubupdate with full recursive.
///
/// Deprecated: Use `:pubupdate` which now defaults to recursive.
/// Kept for backwards compatibility.
class PubUpdateAllExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    // Delegate to same logic as PubUpdateExecutor
    final projectPath = context.path;
    final isFlutter = context.hasNature<FlutterProjectFolder>();
    final executable = isFlutter ? 'flutter' : 'dart';

    if (args.dryRun) {
      print('  [DRY RUN] $executable pub upgrade in ${context.name}');
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'dry-run',
      );
    }

    if (args.verbose) {
      print('  Running: $executable pub upgrade');
      print('  Working directory: ${context.name}');
    }

    final exitCode = await ProcessRunner.runStreaming(
      executable,
      ['pub', 'upgrade'],
      workingDirectory: projectPath,
      runInShell: Platform.isWindows,
    );

    if (exitCode != 0) {
      return ItemResult.failure(
        path: projectPath,
        name: context.name,
        error: '$executable pub upgrade failed (exit $exitCode)',
      );
    }

    return ItemResult.success(
      path: projectPath,
      name: context.name,
      message: 'pub upgrade OK',
    );
  }
}

// =============================================================================
// Other Executors
// =============================================================================

/// Executor for :dcli command.
class DcliExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    return ItemResult.failure(
      path: context.path,
      name: context.name,
      error: 'dcli uses executeWithoutTraversal',
    );
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    if (args.positionalArgs.isEmpty) {
      return const ToolResult.failure('Missing dcli script or expression');
    }

    final dcliArgs = <String>[];

    final initSource = args.extraOptions['init-source'];
    if (initSource is String) {
      dcliArgs.addAll(['-init-source', initSource]);
    }
    if (args.extraOptions['no-init-source'] == true) {
      dcliArgs.add('-no-init-source');
    }
    dcliArgs.addAll(args.positionalArgs);

    if (args.dryRun) {
      print('[DRY RUN] Would run: dcli ${dcliArgs.join(' ')}');
      return const ToolResult.success();
    }

    try {
      final result = await ProcessRunner.run('dcli', dcliArgs);
      if (result.stdout.isNotEmpty) {
        stdout.write(result.stdout);
      }
      if (result.exitCode != 0) {
        if (result.stderr.isNotEmpty) {
          stderr.write(result.stderr);
        }
        return ToolResult.failure('dcli exited with code ${result.exitCode}');
      }
      return const ToolResult.success();
    } catch (e) {
      return ToolResult.failure(e.toString());
    }
  }
}

// =============================================================================
// Factory Function
// =============================================================================

/// Create all buildkit executors.
///
/// All tool commands use native v2 executors. Git executors are defined
/// in [git_executors.dart]. Project tool executors are in individual files
/// under `executors/`.
///
Map<String, CommandExecutor> createBuildkitExecutors() {
  return {
    // Build tools
    'versioner': VersionerExecutor(),
    'bumpversion': BumpVersionExecutor(),
    'bumppubspec': BumpPubspecExecutor(),
    'compiler': CompilerExecutor(),
    'runner': RunnerExecutor(),
    'cleanup': CleanupExecutor(),
    'dependencies': DependenciesExecutor(),
    'publisher': PublisherExecutor(),
    'status': StatusExecutor(),
    'buildsorter': BuildSorterExecutor(),
    'execute': ExecuteExecutor(),

    // Pub commands (have their own non-ToolBase API)
    'pubget': PubGetExecutor(),
    'pubgetall': PubGetAllExecutor(),
    'pubupdate': PubUpdateExecutor(),
    'pubupdateall': PubUpdateAllExecutor(),

    // Git tools
    'git': GitPassthroughExecutor(),
    'gitstatus': GitStatusExecutor(),
    'gitcommit': GitCommitExecutor(),
    'gitpull': GitPullExecutor(),
    'gitbranch': GitBranchExecutor(),
    'gittag': GitTagExecutor(),
    'gitcheckout': GitCheckoutExecutor(),
    'gitreset': GitResetExecutor(),
    'gitclean': GitCleanExecutor(),
    'gitsync': GitSyncExecutor(),
    'gitprune': GitPruneExecutor(),
    'gitstash': GitStashExecutor(),
    'gitunstash': GitUnstashExecutor(),
    'gitcompare': GitCompareExecutor(),
    'gitmerge': GitMergeExecutor(),
    'gitsquash': GitSquashExecutor(),
    'gitrebase': GitRebaseExecutor(),

    // Other
    'findproject': FindProjectExecutor(),
    'dcli': DcliExecutor(),
  };
}
