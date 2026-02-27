import 'binary_helpers.dart';
import 'cli_arg_parser.dart';
import 'command_executor.dart';
import 'tool_runner.dart';
import '../traversal/command_context.dart';

/// Executor that delegates to an external tool binary.
///
/// Created dynamically at startup from wiring configuration +
/// `--dump-definitions` output. When the host tool invokes a wired
/// command, this executor shells out to the nested tool with
/// appropriate flags.
///
/// ```dart
/// final executor = NestedToolExecutor(
///   binary: 'testkit',
///   hostCommandName: 'buildkittest',
///   nestedCommand: 'test',
/// );
///
/// // For standalone tools:
/// final astgenExec = NestedToolExecutor(
///   binary: 'astgen',
///   hostCommandName: 'astgen',
///   isStandalone: true,
/// );
/// ```
class NestedToolExecutor extends CommandExecutor {
  /// Name of the external binary (must be on PATH).
  final String binary;

  /// Command name in the external tool (e.g., 'test').
  /// Null for standalone tools.
  final String? nestedCommand;

  /// Whether this is a standalone (single-command) tool.
  final bool isStandalone;

  /// The host command name (may differ from nestedCommand due to renames).
  final String hostCommandName;

  NestedToolExecutor({
    required this.binary,
    required this.hostCommandName,
    this.nestedCommand,
    this.isStandalone = false,
  });

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final cmdArgs = buildNestedArgs(
      hostArgs: args,
      hostCommandName: hostCommandName,
      nestedCommand: nestedCommand ?? '',
      isStandalone: isStandalone,
    );

    final result = await runBinary(binary, cmdArgs, context.path);

    final stdout = result.stdout.toString().trim();
    final stderr = result.stderr.toString().trim();

    if (stdout.isNotEmpty) {
      // ignore: avoid_print
      print(stdout);
    }
    if (stderr.isNotEmpty) {
      // ignore: avoid_print
      print(stderr);
    }

    if (result.exitCode == 0) {
      return ItemResult.success(path: context.path, name: context.name);
    } else {
      final resolved = resolveBinary(binary);
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error: '$resolved exited with code ${result.exitCode}',
      );
    }
  }

  /// Build CLI args for the nested tool invocation.
  ///
  /// Forwards:
  /// - `--nested` (always)
  /// - `--verbose` and `--dry-run` (behavioral globals)
  /// - The nested command name (for multi-command tools)
  /// - Command-specific options from the host invocation
  ///
  /// Does NOT forward:
  /// - Traversal options (`-s`, `-r`, `-R`, etc.)
  /// - Host-specific global options (`--list`, `--workspace-recursion`)
  static List<String> buildNestedArgs({
    required CliArgs hostArgs,
    required String hostCommandName,
    required String nestedCommand,
    required bool isStandalone,
  }) {
    final args = <String>['--nested'];

    // Forward behavioral globals
    if (hostArgs.verbose) args.add('--verbose');
    if (hostArgs.dryRun) args.add('--dry-run');

    // For multi-command tools, add the nested command
    if (!isStandalone) {
      args.add(':$nestedCommand');
    }

    // Forward command-specific options
    final perCmd = hostArgs.commandArgs[hostCommandName];
    if (perCmd != null) {
      for (final entry in perCmd.options.entries) {
        final name = entry.key;
        final value = entry.value;
        if (value == true) {
          args.add('--$name');
        } else if (value == false) {
          // Skip false flags
          continue;
        } else if (value is String && value.isNotEmpty) {
          args.addAll(['--$name', value]);
        } else if (value is List) {
          for (final v in value) {
            args.addAll(['--$name', v.toString()]);
          }
        }
      }
    }

    return args;
  }

  @override
  String toString() =>
      'NestedToolExecutor($binary'
      '${isStandalone ? ', standalone' : ', :$nestedCommand'}'
      ' → host :$hostCommandName)';
}
