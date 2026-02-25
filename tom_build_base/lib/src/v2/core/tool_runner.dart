import 'dart:io';

import 'package:yaml/yaml.dart';

import 'cli_arg_parser.dart';
import 'command_definition.dart';
import 'console_markdown_zone.dart';
import 'help_generator.dart';
import 'tool_definition.dart';
import 'command_executor.dart';
import '../execute_placeholder.dart';
import '../traversal/traversal_info.dart';
import '../traversal/build_base.dart';
import '../traversal/filter_pipeline.dart';
import '../workspace_utils.dart';

/// Result of running a tool or command.
class ToolResult {
  /// Whether the execution was successful.
  final bool success;

  /// Number of items processed.
  final int processedCount;

  /// Number of items that failed.
  final int failedCount;

  /// Error message if failed.
  final String? errorMessage;

  /// Detailed results per item.
  final List<ItemResult> itemResults;

  const ToolResult({
    this.success = true,
    this.processedCount = 0,
    this.failedCount = 0,
    this.errorMessage,
    this.itemResults = const [],
  });

  /// Create a success result.
  const ToolResult.success({
    this.processedCount = 0,
    this.itemResults = const [],
  }) : success = true,
       failedCount = 0,
       errorMessage = null;

  /// Create a failure result.
  const ToolResult.failure(this.errorMessage)
    : success = false,
      processedCount = 0,
      failedCount = 0,
      itemResults = const [];

  /// Create from aggregated item results.
  factory ToolResult.fromItems(List<ItemResult> items) {
    final failed = items.where((i) => !i.success).length;
    return ToolResult(
      success: failed == 0,
      processedCount: items.length,
      failedCount: failed,
      itemResults: items,
    );
  }
}

/// Result for a single processed item (folder/project).
class ItemResult {
  /// Item path.
  final String path;

  /// Item name.
  final String name;

  /// Whether processing succeeded.
  final bool success;

  /// Result message.
  final String? message;

  /// Error message if failed.
  final String? error;

  const ItemResult({
    required this.path,
    required this.name,
    this.success = true,
    this.message,
    this.error,
  });

  const ItemResult.success({
    required this.path,
    required this.name,
    this.message,
  }) : success = true,
       error = null;

  const ItemResult.failure({
    required this.path,
    required this.name,
    required this.error,
  }) : success = false,
       message = null;
}

/// Runs tools based on their definitions.
///
/// Handles argument parsing, help display, command routing,
/// and traversal execution.
class ToolRunner {
  /// Tool definition.
  final ToolDefinition tool;

  /// Command executors by name.
  final Map<String, CommandExecutor> executors;

  /// Whether to print output.
  final bool verbose;

  /// Output writer (default: stdout).
  final StringSink output;

  ToolRunner({
    required this.tool,
    this.executors = const {},
    this.verbose = true,
    StringSink? output,
  }) : output = _resolveOutput(output);

  /// Resolve the output sink.
  ///
  /// When running inside a console_markdown zone and no explicit sink is
  /// provided, wraps [stdout] in a [ConsoleMarkdownSink] so that
  /// `output.writeln()` calls also render markdown.  When an explicit sink
  /// is provided (e.g. a test buffer), it is used as-is.
  static StringSink _resolveOutput(StringSink? explicit) {
    if (explicit != null) return explicit;
    if (isConsoleMarkdownActive) return ConsoleMarkdownSink(stdout);
    return stdout;
  }

  /// Run the tool with command-line arguments.
  Future<ToolResult> run(List<String> args) async {
    // Parse arguments
    final parser = CliArgParser(toolDefinition: tool);
    final cliArgs = parser.parse(args);

    // Handle help
    if (cliArgs.help) {
      if (cliArgs.commands.isNotEmpty) {
        final cmdName = cliArgs.commands.first;
        final cmd = tool.findCommand(cmdName);
        if (cmd != null) {
          output.writeln(HelpGenerator.generateCommandHelp(cmd, tool: tool));
          return const ToolResult.success();
        }
        // Check if it's an ambiguous prefix
        final matches = tool.findCommandsWithPrefix(cmdName);
        if (matches.length > 1) {
          output.writeln('Ambiguous command prefix ":$cmdName" matches:');
          for (final match in matches) {
            output.writeln('  :${match.name}');
          }
          return const ToolResult.failure('Ambiguous command prefix');
        }
        // Check help topics before giving up
        final topic = tool.findHelpTopic(cmdName);
        if (topic != null) {
          output.writeln(HelpGenerator.generateTopicHelp(topic, tool: tool));
          return const ToolResult.success();
        }
        output.writeln('Unknown command: :$cmdName');
        return const ToolResult.failure('Unknown command');
      }
      output.writeln(HelpGenerator.generateToolHelp(tool));
      return const ToolResult.success();
    }

    // Handle version (--version flag or bare 'version' positional arg)
    if (cliArgs.version || cliArgs.positionalArgs.contains('version')) {
      output.writeln('${tool.name} v${tool.version}');
      return const ToolResult.success();
    }

    // Handle multi-command mode
    if (tool.mode == ToolMode.multiCommand) {
      if (cliArgs.commands.isEmpty) {
        if (tool.defaultCommand != null) {
          return _runCommand(tool.defaultCommand!, cliArgs);
        }
        output.writeln('No command specified.\n');
        output.writeln(HelpGenerator.generateUsageSummary(tool));
        return const ToolResult.failure('No command specified');
      }

      // Run each command in sequence
      final results = <ItemResult>[];
      for (final cmdName in cliArgs.commands) {
        final result = await _runCommand(cmdName, cliArgs);
        results.addAll(result.itemResults);
        if (!result.success) {
          return result; // Stop on first failure
        }
      }
      return ToolResult.fromItems(results);
    }

    // Single command mode - run default executor
    final executor = executors['default'];
    if (executor == null) {
      return const ToolResult.failure('No default executor configured');
    }

    return _runWithTraversal(executor, null, cliArgs);
  }

  /// Run a specific command.
  Future<ToolResult> _runCommand(String cmdName, CliArgs cliArgs) async {
    final cmd = tool.findCommand(cmdName);
    if (cmd == null) {
      // Check if it's an ambiguous prefix
      final matches = tool.findCommandsWithPrefix(cmdName);
      if (matches.length > 1) {
        output.writeln('Ambiguous command prefix ":$cmdName" matches:');
        for (final match in matches) {
          output.writeln('  :${match.name}');
        }
        return const ToolResult.failure('Ambiguous command prefix');
      }
      output.writeln('Unknown command: :$cmdName');
      return ToolResult.failure('Unknown command: $cmdName');
    }

    // Use the actual command name for executor lookup and help
    final actualCmdName = cmd.name;

    // Check for per-command --help (check both original and resolved names)
    final cmdArgs =
        cliArgs.commandArgs[cmdName] ?? cliArgs.commandArgs[actualCmdName];
    if (cmdArgs != null && cmdArgs.options['help'] == true) {
      output.writeln(HelpGenerator.generateCommandHelp(cmd, tool: tool));
      return const ToolResult.success();
    }

    // Look up executor by actual command name
    final executor = executors[actualCmdName];
    if (executor == null) {
      return ToolResult.failure('No executor for command: $actualCmdName');
    }

    return _runWithTraversal(executor, cmd, cliArgs);
  }

  /// Run executor with traversal.
  Future<ToolResult> _runWithTraversal(
    CommandExecutor executor,
    CommandDefinition? cmd,
    CliArgs cliArgs,
  ) async {
    // Get execution root: explicit path > workspace root (default)
    // Default behavior is --scan . -R --not-recursive (workspace mode)
    final String executionRoot;
    if (cliArgs.root != null) {
      // Explicit -R <path> was provided
      executionRoot = cliArgs.root!;
    } else {
      // Default: use workspace root (as if bare -R was passed)
      executionRoot = findWorkspaceRoot(Directory.current.path);
    }

    // Load config defaults from buildkit_master.yaml navigation section
    final configDefaults = _loadTraversalDefaults(executionRoot);

    // Build traversal info
    final supportsGit = cmd?.supportsGitTraversal ?? false;
    final requiresGit = cmd?.requiresGitTraversal ?? false;
    final gitModeSpecified = cliArgs.gitModeExplicitlySet;
    final defaultGitOrder = cmd?.defaultGitOrder;
    final BaseTraversalInfo traversalInfo;

    // Validate: user requested git but command doesn't support it
    if (!supportsGit && gitModeSpecified) {
      output.writeln('Error: This command does not support git traversal.');
      output.writeln('Remove -i/--inner-first-git or -o/--outer-first-git.');
      return const ToolResult.failure(
        'Git traversal not supported by this command',
      );
    }

    // Determine if we should use git traversal
    final useGitTraversal = requiresGit || (gitModeSpecified && supportsGit);

    if (useGitTraversal) {
      // Try git traversal (uses defaultGitOrder if -i/-o not specified)
      final gitInfo = cliArgs.toGitTraversalInfo(
        executionRoot: executionRoot,
        commandDefaultGitOrder: defaultGitOrder,
      );
      if (gitInfo == null) {
        // No -i/-o specified and no defaultGitOrder available
        output.writeln('Error: Git traversal mode required for this command.');
        output.writeln('Use --inner-first-git (-i) or --outer-first-git (-o).');
        return const ToolResult.failure(
          'Git traversal mode required but not specified',
        );
      }
      traversalInfo = gitInfo;
    } else {
      // Use project traversal (default)
      traversalInfo = cliArgs.toProjectTraversalInfo(
        executionRoot: executionRoot,
        configDefaults: configDefaults,
      );
    }

    // Check if command requires traversal
    if (cmd != null && !cmd.requiresTraversal) {
      // Execute without traversal
      return executor.executeWithoutTraversal(cliArgs);
    }

    // Validate nature configuration — every traversal command must declare
    // its nature requirements. Use FsFolder to traverse all folders.
    // For singleCommand tools (cmd == null), fall back to tool-level natures.
    final reqNatures = cmd?.requiredNatures ?? tool.requiredNatures;
    final workNatures =
        cmd?.worksWithNatures ??
        (cmd == null ? tool.worksWithNatures : const <Type>{});
    final hasRequired = reqNatures != null && reqNatures.isNotEmpty;
    final hasWorksWith = workNatures.isNotEmpty;
    if (!hasRequired && !hasWorksWith) {
      final cmdLabel = cmd != null ? ' "${cmd.name}"' : '';
      output.writeln('Error: Command$cmdLabel has no nature configuration.');
      output.writeln(
        'Set requiredNatures or worksWithNatures '
        '(use FsFolder for all folders).',
      );
      return ToolResult.failure('Command$cmdLabel has no nature configuration');
    }

    // Execute with traversal
    final results = <ItemResult>[];

    await BuildBase.traverse(
      info: traversalInfo,
      verbose: verbose,
      requiredNatures: reqNatures,
      worksWithNatures: workNatures,
      run: (context) async {
        // Apply per-command filters for project traversal
        if (traversalInfo is ProjectTraversalInfo) {
          final cmdArgs = cliArgs.commandArgs[cmd?.name];
          if (cmdArgs != null) {
            // Check project patterns (ID → name → folder name glob → path)
            if (cmdArgs.projectPatterns.isNotEmpty) {
              final filter = FilterPipeline();
              final matches = filter.matchesProjectPattern(
                context.fsFolder,
                cmdArgs.projectPatterns,
                executionRoot: traversalInfo.executionRoot,
              );
              if (!matches) return true; // Skip, continue
            }
            // Check exclude patterns (ID → name → folder name glob → path)
            if (cmdArgs.excludePatterns.isNotEmpty) {
              final filter = FilterPipeline();
              final excluded = filter.matchesProjectPattern(
                context.fsFolder,
                cmdArgs.excludePatterns,
                executionRoot: traversalInfo.executionRoot,
              );
              if (excluded) return true; // Skip, continue
            }
          }
        }

        // Resolve placeholders in CLI args per folder.
        // Uses skipUnknown: true so command-specific placeholders (e.g.,
        // compiler's ${file}) are left for the executor's own resolver.
        final placeholderCtx = ExecutePlaceholderContext.fromCommandContext(
          context,
          executionRoot,
        );
        final resolvedArgs = cliArgs.withResolvedStrings(
          (s) => ExecutePlaceholderResolver.resolveCommand(
            s,
            placeholderCtx,
            skipUnknown: true,
          ),
        );

        final result = await executor.execute(context, resolvedArgs);
        results.add(result);
        return true; // Continue to next
      },
    );

    return ToolResult.fromItems(results);
  }

  /// Load traversal defaults from buildkit_master.yaml navigation section.
  TraversalDefaults? _loadTraversalDefaults(String basePath) {
    final wsRoot = findWorkspaceRoot(basePath);
    final masterFile = File('$wsRoot/$kBuildkitMasterYaml');
    if (!masterFile.existsSync()) return null;

    try {
      final content = masterFile.readAsStringSync();
      final yaml = loadYaml(content);
      if (yaml is! YamlMap) return null;

      final nav = yaml['navigation'] as YamlMap?;
      if (nav == null) return null;

      return TraversalDefaults.fromMap(Map<String, dynamic>.from(nav));
    } catch (e) {
      return null;
    }
  }
}
