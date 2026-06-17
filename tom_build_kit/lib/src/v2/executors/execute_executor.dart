/// Native v2 executor for the execute command.
///
/// Executes shell commands in traversed directories with placeholder resolution.
/// Supports filtering based on boolean conditions and ternary syntax for
/// conditional command construction.
library;

import 'dart:io' show Directory;

import 'package:tom_build_base/tom_build_base.dart';

// =============================================================================
// Execute Executor
// =============================================================================

/// Native v2 executor for the `:execute` command.
///
/// Uses `requiresTraversal: true` — ToolRunner traverses projects and calls
/// [execute] for each project folder. The command takes a single positional
/// argument which is the shell command to execute.
///
/// Supports:
/// - Path placeholders: `%{root}`, `%{folder}`, `%{folder.name}`, `%{folder.relative}`
/// - Nature existence: `%{dart.exists}`, `%{flutter.exists}`, etc.
/// - Nature attributes: `%{dart.name}`, `%{git.branch}`, etc.
/// - Ternary expressions: `%{condition?(true):(false)}`
/// - `--condition` filter to skip folders not matching a boolean placeholder
class ExecuteExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final verbose = args.verbose;
    final dryRun = args.dryRun;
    final rootPath = args.root ?? args.scan ?? Directory.current.path;

    // Get the command from positional args (command line after :execute)
    String? commandTemplate;
    String? condition;

    // Get condition from per-command options or extraOptions
    final cmdName = args.commands.firstWhere(
      (c) => c == 'execute',
      orElse: () => 'execute',
    );
    final perCmd = args.commandArgs[cmdName];
    if (perCmd != null) {
      condition = perCmd.options['condition'] as String?;
    }
    condition ??= args.extraOptions['condition'] as String?;

    // Get command template from positional args
    if (args.positionalArgs.isNotEmpty) {
      commandTemplate = args.positionalArgs.join(' ');
    }

    if (commandTemplate == null || commandTemplate.isEmpty) {
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error: 'No command provided. Usage: buildkit :execute "command"',
      );
    }

    // Create placeholder context from CommandContext
    final folder = context.fsFolder;
    // Copy natures to FsFolder for ExecutePlaceholderContext
    folder.natures.clear();
    folder.natures.addAll(context.natures);

    final placeholderCtx = ExecutePlaceholderContext(
      rootPath: rootPath,
      folder: folder,
    );

    // Check condition if specified
    if (condition != null && condition.isNotEmpty) {
      try {
        final conditionMet = ExecutePlaceholderResolver.checkCondition(
          condition,
          placeholderCtx,
        );
        if (!conditionMet) {
          if (verbose) {
            print('  [SKIP] ${context.name}: condition "$condition" not met');
          }
          return ItemResult.success(
            path: context.path,
            name: context.name,
            message: 'skipped: condition not met',
          );
        }
      } on UnresolvedPlaceholderException catch (e) {
        return ItemResult.failure(
          path: context.path,
          name: context.name,
          error: e.toString(),
        );
      }
    }

    // Resolve placeholders in command
    String resolvedCommand;
    try {
      resolvedCommand = ExecutePlaceholderResolver.resolveCommand(
        commandTemplate,
        placeholderCtx,
      );
    } on UnresolvedPlaceholderException catch (e) {
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error: e.toString(),
      );
    }

    // Skip empty commands (e.g., from empty ternary branch)
    if (resolvedCommand.trim().isEmpty) {
      if (verbose) {
        print('  [SKIP] ${context.name}: command resolved to empty');
      }
      return ItemResult.success(
        path: context.path,
        name: context.name,
        message: 'skipped: command resolved to empty',
      );
    }

    // Execute the command
    if (dryRun) {
      print('[DRY-RUN] ${context.name}: $resolvedCommand');
      return ItemResult.success(
        path: context.path,
        name: context.name,
        message: 'dry-run: $resolvedCommand',
      );
    }

    print('${context.name}: $resolvedCommand');

    try {
      final result = await ProcessRunner.runShell(
        resolvedCommand,
        workingDirectory: context.path,
      );

      final stdout = result.stdout.trim();
      final stderr = result.stderr.trim();

      if (stdout.isNotEmpty) {
        for (final line in stdout.split('\n')) {
          print('  $line');
        }
      }

      if (result.exitCode != 0) {
        if (stderr.isNotEmpty) {
          for (final line in stderr.split('\n')) {
            print('  [ERR] $line');
          }
        }
        return ItemResult.failure(
          path: context.path,
          name: context.name,
          error: 'Command failed with exit code ${result.exitCode}',
        );
      }

      return ItemResult.success(
        path: context.path,
        name: context.name,
        message: 'executed: $resolvedCommand',
      );
    } catch (e) {
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error: 'Failed to execute command: $e',
      );
    }
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    return const ToolResult.failure(
      'execute command requires traversal. Use with --scan or from a project directory.',
    );
  }
}
