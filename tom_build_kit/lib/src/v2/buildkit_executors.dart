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

import 'executors/project_action_executor.dart';
import 'executors/apidoc_executor.dart';
import 'executors/apireference_executor.dart';
import 'executors/apisummary_executor.dart';
import 'executors/boundaries_executor.dart';
import 'executors/doccheck_executor.dart';
import 'executors/textresources_executor.dart';
import 'executors/docsite_executor.dart';
import 'executors/buildsorter_executor.dart';
import 'executors/bumppubspec_executor.dart';
import 'executors/bumpversion_executor.dart';
import 'executors/cleanup_executor.dart';
import 'executors/compiler_executor.dart';
import 'executors/dependencies_executor.dart';
import 'executors/execute_executor.dart';
import 'executors/git_executors.dart';
import 'ws/ws_push.dart';
import 'binaries/binaries_executors.dart';
import 'skill/skill_dirty_scan.dart';
import 'skill/skill_reconcile_code.dart';
import 'skill/skill_status.dart';
import 'ws/ws_repo_cleanup.dart';
import 'ws/ws_update.dart';
import 'executors/findproject_executor.dart';
import '../wssetup/wssetup_tool.dart' show WssetupExecutor;
import 'executors/publisher_executor.dart';
import 'executors/runner_executor.dart';
import 'executors/projects_executor.dart';
import 'executors/status_executor.dart';
import 'executors/unreferenced_executor.dart';
import 'executors/versioner_executor.dart';
import 'incremental/step_inputs.dart';
import 'pub_get_runner.dart';

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

    return _pubGetItem(context, executable);
  }
}

/// Executor for :pubgetall - alias for :pubget with full recursive.
///
/// Deprecated: Use `:pubget` which now defaults to recursive.
/// Kept for backwards compatibility.
class PubGetAllExecutor extends PubGetExecutor {}

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

    // Printed, not streamed: under --jobs the projects run at once, and
    // ToolRunner keeps each project's printed output together.
    final run = await ProcessRunner.run(
      executable,
      ['pub', 'upgrade'],
      workingDirectory: projectPath,
      runInShell: Platform.isWindows,
    );
    _printProcessOutput(run.stdout, run.stderr);
    final exitCode = run.exitCode;

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

    // Printed, not streamed: under --jobs the projects run at once, and
    // ToolRunner keeps each project's printed output together.
    final run = await ProcessRunner.run(
      executable,
      ['pub', 'upgrade'],
      workingDirectory: projectPath,
      runInShell: Platform.isWindows,
    );
    _printProcessOutput(run.stdout, run.stderr);
    final exitCode = run.exitCode;

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
/// in `git_executors.dart`. Project tool executors are in individual files
/// under `executors/`.
///
Map<String, CommandExecutor> createBuildkitExecutors() {
  return {
    // Build tools
    'build': ProjectActionExecutor(ProjectAction.build),
    'test': ProjectActionExecutor(ProjectAction.test),
    'clean': ProjectActionExecutor(ProjectAction.clean),
    'versioner': IncrementalStep(VersionerExecutor()),
    'bumpversion': BumpVersionExecutor(),
    'bumppubspec': BumpPubspecExecutor(),
    'compiler': IncrementalStep(CompilerExecutor()),
    'runner': IncrementalStep(RunnerExecutor()),
    'cleanup': CleanupExecutor(),
    'dependencies': DependenciesExecutor(),
    'boundaries': BoundariesExecutor(),
    'apidoc': ApidocExecutor(),
    'apisummary': ApisummaryExecutor(),
    'apireference': ApireferenceExecutor(),
    'doccheck': DoccheckExecutor(),
    'textresources': TextresourcesExecutor(),
    'docsite': DocsiteExecutor(),
    'publisher': PublisherExecutor(),
    'projects': ProjectsExecutor(),
    'status': StatusExecutor(),
    'buildsorter': BuildSorterExecutor(),
    'unreferenced': UnreferencedExecutor(),
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
    'gitpush': GitPushExecutor(),
    'ws-push': WsPushExecutor(),
    'ws-update': WsUpdateExecutor(),
    'ws-repo-cleanup': WsRepoCleanupExecutor(),
    'skill-reconcile-code': SkillReconcileExecutor(),
    'skill-status': SkillStatusExecutor(),
    'skill-dirty-scan': SkillDirtyScanExecutor(),
    'skill-build-binaries': SkillBuildBinariesExecutor(all: false),
    'skill-build-all-binaries': SkillBuildBinariesExecutor(all: true),
    'skill-push-binaries': SkillPushBinariesExecutor(),
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
    'wssetup': WssetupExecutor(),
    'dcli': DcliExecutor(),
  };
}

/// Prints a finished process's output, stdout then stderr, without the
/// trailing blank line.
/// `pub get` in [context]'s project through [runPubGet] (which retries once
/// with `pub upgrade` for a stale git ref in an untracked lock), as an item
/// result.
Future<ItemResult> _pubGetItem(
  CommandContext context,
  String executable,
) async {
  final outcome = await runPubGet(context.path, executable);
  if (outcome.exitCode != 0) {
    final command = outcome.upgraded.isEmpty ? 'pub get' : 'pub upgrade';
    return ItemResult.failure(
      path: context.path,
      name: context.name,
      error: '$executable $command failed (exit ${outcome.exitCode})',
    );
  }
  return ItemResult.success(
    path: context.path,
    name: context.name,
    message: outcome.upgraded.isEmpty
        ? 'pub get OK'
        : 'pub get OK after pub upgrade ${outcome.upgraded.join(' ')}',
  );
}

void _printProcessOutput(String out, String err) {
  for (final text in [out, err]) {
    final trimmed = text.trimRight();
    if (trimmed.isNotEmpty) print(trimmed);
  }
}
