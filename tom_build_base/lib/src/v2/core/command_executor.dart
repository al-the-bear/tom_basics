import 'dart:io';

import 'cli_arg_parser.dart';
import 'tool_runner.dart';
import '../traversal/command_context.dart';

/// Base class for command executors.
///
/// Implement this to create custom command logic that integrates
/// with the ToolRunner traversal system.
abstract class CommandExecutor {
  /// Execute command on a single folder.
  ///
  /// Called by ToolRunner for each folder during traversal.
  /// Returns an [ItemResult] describing the outcome.
  Future<ItemResult> execute(CommandContext context, CliArgs args);

  /// Execute command without traversal.
  ///
  /// Called for commands that don't require folder traversal
  /// (e.g., --help, --version, or commands that operate globally).
  /// Default implementation returns success.
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    return const ToolResult.success();
  }
}

/// Callback-based command executor.
///
/// Convenient way to create executors from function callbacks
/// without creating a full class.
class CallbackExecutor extends CommandExecutor {
  /// Callback executed for each folder.
  final Future<ItemResult> Function(CommandContext context, CliArgs args)
      onExecute;

  /// Callback for non-traversal execution.
  final Future<ToolResult> Function(CliArgs args)? onExecuteWithoutTraversal;

  CallbackExecutor({
    required this.onExecute,
    this.onExecuteWithoutTraversal,
  });

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) {
    return onExecute(context, args);
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) {
    if (onExecuteWithoutTraversal != null) {
      return onExecuteWithoutTraversal!(args);
    }
    return super.executeWithoutTraversal(args);
  }
}

/// Synchronous callback-based executor.
///
/// For simple commands that don't need async operations.
class SyncExecutor extends CommandExecutor {
  /// Synchronous callback.
  final ItemResult Function(CommandContext context, CliArgs args) onExecute;

  SyncExecutor({required this.onExecute});

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    return onExecute(context, args);
  }
}

/// No-op executor that just lists folders.
///
/// Useful for --list mode or debugging traversal.
class ListExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    return ItemResult.success(
      path: context.path,
      name: context.name,
      message: 'Listed',
    );
  }
}

/// Executor that runs a shell command in each folder.
class ShellExecutor extends CommandExecutor {
  /// Shell command to execute.
  final String shellCommand;

  /// Whether to print command output.
  final bool printOutput;

  /// Working directory override (null = use context.path).
  final String? workingDirectory;

  ShellExecutor({
    required this.shellCommand,
    this.printOutput = true,
    this.workingDirectory,
  });

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    try {
      final dir = workingDirectory ?? context.path;
      final result = await Process.run(
        'sh',
        ['-c', shellCommand],
        workingDirectory: dir,
      );

      if (result.exitCode != 0) {
        return ItemResult.failure(
          path: context.path,
          name: context.name,
          error: result.stderr.toString(),
        );
      }

      return ItemResult.success(
        path: context.path,
        name: context.name,
        message: printOutput ? result.stdout.toString() : null,
      );
    } catch (e) {
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error: e.toString(),
      );
    }
  }
}

/// Executor that invokes a Dart function for each project.
class DartExecutor extends CommandExecutor {
  /// Dart function to execute.
  final Future<bool> Function(CommandContext context) dartFunction;

  /// Success message generator.
  final String Function(CommandContext context)? successMessage;

  DartExecutor({
    required this.dartFunction,
    this.successMessage,
  });

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    try {
      final success = await dartFunction(context);
      if (success) {
        return ItemResult.success(
          path: context.path,
          name: context.name,
          message: successMessage?.call(context),
        );
      } else {
        return ItemResult.failure(
          path: context.path,
          name: context.name,
          error: 'Dart function returned false',
        );
      }
    } catch (e) {
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error: e.toString(),
      );
    }
  }
}
