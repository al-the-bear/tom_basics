import 'dart:io';

import 'package:yaml/yaml.dart';

import 'cli_arg_parser.dart';
import 'command_definition.dart';
import 'console_markdown_zone.dart';
import 'help_generator.dart';
import 'macro_expansion.dart';
import 'nested_tool_executor.dart';
import 'binary_helpers.dart';
import 'pipeline_config.dart';
import 'pipeline_executor.dart';
import 'tool_definition.dart';
import 'tool_definition_serializer.dart';
import 'command_executor.dart';
import 'wiring_loader.dart';
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

class _RequirementCheckResult {
  final List<String> warnings;
  final List<String> errors;
  final String? setupInstructions;

  const _RequirementCheckResult({
    this.warnings = const [],
    this.errors = const [],
    this.setupInstructions,
  });

  bool get hasErrors => errors.isNotEmpty;

  bool get hasIssues => warnings.isNotEmpty || errors.isNotEmpty;
}

/// Runs tools based on their definitions.
///
/// Handles argument parsing, help display, command routing,
/// traversal execution, and nested tool wiring.
class ToolRunner {
  /// Tool definition.
  final ToolDefinition tool;

  /// Command executors by name.
  final Map<String, CommandExecutor> executors;

  /// Mutable copy of tool definition (updated during wiring).
  late ToolDefinition _effectiveTool;

  /// Whether to print output.
  final bool verbose;

  /// Output writer (default: stdout).
  final StringSink output;

  /// Runtime-only macros (`$macro`) for this invocation session.
  ///
  /// These are persisted to `{workspace_root}/{tool_name}_macros.yaml` so that
  /// macros defined in one invocation are visible in subsequent ones.
  final Map<String, String> _runtimeMacros = <String, String>{};

  /// Whether the persisted macros have been loaded into [_runtimeMacros].
  bool _macrosLoaded = false;

  ToolRunner({
    required this.tool,
    this.executors = const {},
    this.verbose = true,
    StringSink? output,
  }) : output = _resolveOutput(output) {
    _effectiveTool = tool;
  }

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
    // Expand macros before parsing (loads persisted macros if needed)
    _loadPersistedMacros();
    final expandedArgs = expandMacros(args, _runtimeMacros);

    // Parse arguments
    final parser = CliArgParser(toolDefinition: tool);
    final cliArgs = parser.parse(expandedArgs);

    // --dump-definitions: serialize tool definition and exit immediately.
    // Intercepted before any wiring or traversal.
    if (cliArgs.dumpDefinitions) {
      final yaml = ToolDefinitionSerializer.toYaml(tool);
      output.write(yaml);
      return const ToolResult.success();
    }

    final doctorRequested = _isDoctorRequested(cliArgs);
    final shouldValidateEnvironment =
        doctorRequested ||
        cliArgs.help ||
        (!cliArgs.version && !cliArgs.positionalArgs.contains('version'));

    if (shouldValidateEnvironment) {
      final checks = _runRequiredEnvironmentChecks();
      if (checks.hasIssues) {
        _printRequirementIssues(checks);
      }
      if (doctorRequested) {
        if (checks.hasErrors) {
          return const ToolResult.failure('Installation requirements not met');
        }
        output.writeln('Doctor check passed.');
        return const ToolResult.success();
      }
      if (checks.hasErrors) {
        return const ToolResult.failure('Installation requirements not met');
      }
    }

    // --nested: skip wiring, skip traversal, run single-project in cwd.
    if (cliArgs.nested) {
      return _runNestedMode(cliArgs);
    }

    // Lazy wiring: merge code + YAML defaults, query only needed tools.
    if (tool.hasWiring) {
      final wiringOk = await _lazyWireNestedTools(cliArgs);
      if (!wiringOk) {
        return const ToolResult.failure('Missing nested tool binaries');
      }
    }

    // Handle help (uses _effectiveTool which now includes wired commands)
    if (cliArgs.help) {
      return _handleHelp(cliArgs);
    }

    // Handle bare 'help' positional (e.g., 'buildkit help pipelines')
    if (cliArgs.positionalArgs.firstOrNull == 'help') {
      final topic = cliArgs.positionalArgs.skip(1).firstOrNull;
      if (topic != null) {
        final builtInHelp =
            _tryHandleBuiltInMacroDefineHelp(topic) ??
            _tryHandleBuiltInPipelinesHelp(topic);
        if (builtInHelp != null) {
          output.writeln(builtInHelp);
          return const ToolResult.success();
        }
        final topicDef = _effectiveTool.findHelpTopic(topic);
        if (topicDef != null) {
          output.writeln(
            HelpGenerator.generateTopicHelp(topicDef, tool: _effectiveTool),
          );
          return const ToolResult.success();
        }
        output.writeln('Unknown help topic: $topic');
        return const ToolResult.failure('Unknown help topic');
      }
      // 'help' alone — show full tool help
      final baseHelp = HelpGenerator.generateToolHelp(
        _effectiveTool,
        nestedCommandNames: _wiredExecutors.keys.toSet(),
      );
      output.write(baseHelp);
      final appendix = _builtInMacroDefineHelpAppendix();
      if (appendix != null) {
        output.writeln();
        output.writeln(appendix);
      }
      return const ToolResult.success();
    }

    // Handle version (--version flag or bare 'version' positional arg)
    if (cliArgs.version || cliArgs.positionalArgs.contains('version')) {
      final versionOutput =
          _effectiveTool.versionString ??
          '${_effectiveTool.name} v${_effectiveTool.version}';
      output.writeln(versionOutput);
      return const ToolResult.success();
    }

    // Handle multi-command mode
    if (_effectiveTool.mode == ToolMode.multiCommand) {
      final pipelineAttempt = await _tryRunPipelineInvocation(cliArgs);
      if (pipelineAttempt != null) {
        return pipelineAttempt;
      }

      if (cliArgs.commands.isEmpty) {
        if (_effectiveTool.defaultCommand != null) {
          return _runCommand(_effectiveTool.defaultCommand!, cliArgs);
        }
        output.writeln('No command specified.\n');
        output.writeln(HelpGenerator.generateUsageSummary(_effectiveTool));
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

  Future<ToolResult?> _tryRunPipelineInvocation(CliArgs cliArgs) async {
    if (cliArgs.commands.isNotEmpty) return null;
    if (cliArgs.positionalArgs.isEmpty) return null;

    final candidateName = cliArgs.positionalArgs.first;
    if (candidateName.startsWith('-') || candidateName == 'help') return null;

    final loaded = ToolPipelineConfigLoader.load(tool: _effectiveTool);
    if (loaded == null || !loaded.hasPipelines) return null;

    final definition = loaded.pipelines[candidateName];
    if (definition == null) return null;

    final executor = ToolPipelineExecutor(
      tool: _effectiveTool,
      output: output,
      verbose: verbose,
    );

    final ok = await executor.executeInvocation(
      pipelineName: candidateName,
      config: loaded,
      cliArgs: cliArgs,
    );

    if (!ok) {
      return const ToolResult.failure('Pipeline execution failed');
    }
    return const ToolResult.success();
  }

  /// Run a specific command.
  Future<ToolResult> _runCommand(String cmdName, CliArgs cliArgs) async {
    final builtIn = _tryHandleBuiltInMacroDefineCommand(cmdName, cliArgs);
    if (builtIn != null) {
      return builtIn;
    }

    final cmd = _effectiveTool.findCommand(cmdName);
    if (cmd == null) {
      // Check if it's an ambiguous prefix
      final matches = _effectiveTool.findCommandsWithPrefix(cmdName);
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
      output.writeln(
        HelpGenerator.generateCommandHelp(cmd, tool: _effectiveTool),
      );
      return const ToolResult.success();
    }

    // Look up executor by actual command name (native or wired)
    final executor = _findExecutor(actualCmdName);
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
    final reqNatures = cmd?.requiredNatures ?? _effectiveTool.requiredNatures;
    final workNatures =
        cmd?.worksWithNatures ??
        (cmd == null ? _effectiveTool.worksWithNatures : const <Type>{});
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

    // Load master defines once before traversal.
    // Merges default defines with mode-specific defines based on --modes.
    final masterDefines = _loadMasterDefines(cliArgs.modes);

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

        // Resolve %{...} placeholders in CLI args per folder.
        // Uses skipUnknown: true so command-specific placeholders (e.g.,
        // compiler's ${file}) are left for the executor's own resolver.
        final placeholderCtx = ExecutePlaceholderContext.fromCommandContext(
          context,
          executionRoot,
        );
        final placeholderResolvedArgs = cliArgs.withResolvedStrings(
          (s) => ExecutePlaceholderResolver.resolveCommand(
            s,
            placeholderCtx,
            skipUnknown: true,
          ),
        );

        // Resolve @[name] define placeholders per folder.
        // Merges master defines with per-project buildkit.yaml defines
        // (project overrides master).
        final projectDefines = _loadProjectDefines(
          context.fsFolder.path,
          masterDefines,
          cliArgs.modes,
        );
        final resolvedArgs = placeholderResolvedArgs.withResolvedStrings(
          (s) => _resolveDefineString(s, projectDefines),
        );

        final result = await executor.execute(context, resolvedArgs);
        results.add(result);
        return true; // Continue to next
      },
    );

    return ToolResult.fromItems(results);
  }

  /// Run in nested mode: skip wiring, skip traversal, execute in cwd.
  ///
  /// Used when a host tool invokes this tool with `--nested`. The tool
  /// runs its command directly in the current working directory without
  /// any project traversal or nested tool wiring.
  Future<ToolResult> _runNestedMode(CliArgs cliArgs) async {
    // Handle help in nested mode
    if (cliArgs.help) {
      if (cliArgs.commands.isNotEmpty) {
        final cmdName = cliArgs.commands.first;
        final cmd = tool.findCommand(cmdName);
        if (cmd != null) {
          output.writeln(HelpGenerator.generateCommandHelp(cmd, tool: tool));
          return const ToolResult.success();
        }
      }
      output.writeln(HelpGenerator.generateToolHelp(tool));
      return const ToolResult.success();
    }

    // Handle version
    if (cliArgs.version) {
      output.writeln('${tool.name} v${tool.version}');
      return const ToolResult.success();
    }

    // Multi-command: route to single command
    if (tool.mode == ToolMode.multiCommand) {
      if (cliArgs.commands.isEmpty) {
        if (tool.defaultCommand != null) {
          return _runNestedCommand(tool.defaultCommand!, cliArgs);
        }
        return const ToolResult.failure('No command specified in nested mode');
      }
      // In nested mode, only one command at a time
      return _runNestedCommand(cliArgs.commands.first, cliArgs);
    }

    // Single command: run default executor directly
    final executor = executors['default'];
    if (executor == null) {
      return const ToolResult.failure('No default executor configured');
    }
    return executor.executeWithoutTraversal(cliArgs);
  }

  /// Run a single command in nested mode (no traversal).
  Future<ToolResult> _runNestedCommand(String cmdName, CliArgs cliArgs) async {
    final cmd = tool.findCommand(cmdName);
    if (cmd == null) {
      return ToolResult.failure('Unknown command in nested mode: $cmdName');
    }

    final executor = executors[cmd.name];
    if (executor == null) {
      return ToolResult.failure('No executor for command: ${cmd.name}');
    }
    return executor.executeWithoutTraversal(cliArgs);
  }

  /// Lazy wire nested tools into the effective tool definition.
  ///
  /// Merges code-level [ToolDefinition.defaultIncludes] with YAML
  /// `nested_tools:` entries, then queries only the needed tools.
  /// Updates [_effectiveTool] and [executors] with wired commands.
  ///
  /// Returns `true` if wiring succeeded, `false` if a required binary
  /// was missing and execution should be aborted.
  Future<bool> _lazyWireNestedTools(CliArgs cliArgs) async {
    final workspaceRoot = findWorkspaceRoot(Directory.current.path);
    final loader = WiringLoader(tool: tool);

    // Determine which commands are requested
    final Set<String>? requestedCommands;
    if (cliArgs.isHelpMode) {
      // Help mode: wire all tools, tolerate missing binaries
      requestedCommands = null;
    } else if (cliArgs.commands.isNotEmpty) {
      requestedCommands = cliArgs.commands.toSet();
    } else {
      // No commands specified — no nested tools needed
      return true;
    }

    final result = await loader.resolve(
      requestedCommands: requestedCommands,
      workspaceRoot: workspaceRoot,
      tolerateMissing: cliArgs.isHelpMode,
    );

    // Handle errors — abort if any requested nested tool binary is missing.
    // Since we only query binaries for commands the user actually requested,
    // any error here means the user's intended command cannot run.
    if (result.hasErrors) {
      output.writeln('Error: Missing required tool binaries:');
      for (final msg in result.errors) {
        output.writeln('  - $msg');
      }
      return false;
    }

    // Print warnings
    for (final warning in result.warnings) {
      if (verbose) {
        output.writeln('Warning: $warning');
      }
    }

    // Merge wired commands into the effective tool
    if (result.commands.isNotEmpty) {
      _effectiveTool = _effectiveTool.copyWith(
        commands: [..._effectiveTool.commands, ...result.commands],
      );
    }

    // Merge wired executors (mutable map)
    if (result.executors.isNotEmpty) {
      final mutableExecutors = Map<String, CommandExecutor>.from(executors);
      mutableExecutors.addAll(result.executors);
      // We can't reassign final executors, so we update _effectiveTool
      // and use a separate lookup. Actually, executors is final const.
      // Instead, we store the wired executors and check both maps.
      _wiredExecutors.addAll(result.executors);
    }

    return true;
  }

  /// Wired executors merged during lazy wiring.
  final Map<String, CommandExecutor> _wiredExecutors = {};

  /// Look up an executor by command name (checks both native and wired).
  CommandExecutor? _findExecutor(String cmdName) {
    return executors[cmdName] ?? _wiredExecutors[cmdName];
  }

  /// Handle help display with wired commands included.
  Future<ToolResult> _handleHelp(CliArgs cliArgs) async {
    if (cliArgs.commands.isNotEmpty) {
      final cmdName = cliArgs.commands.first;
      final builtInHelp =
          _tryHandleBuiltInMacroDefineHelp(cmdName) ??
          _tryHandleBuiltInPipelinesHelp(cmdName);
      if (builtInHelp != null) {
        output.writeln(builtInHelp);
        return const ToolResult.success();
      }

      final cmd = _effectiveTool.findCommand(cmdName);
      if (cmd != null) {
        // Check if this is a wired command — delegate help to nested tool
        final wiredExec = _wiredExecutors[cmd.name];
        if (wiredExec is NestedToolExecutor) {
          return _delegateNestedHelp(wiredExec, cliArgs);
        }
        output.writeln(
          HelpGenerator.generateCommandHelp(cmd, tool: _effectiveTool),
        );
        return const ToolResult.success();
      }
      // Check if it's an ambiguous prefix
      final matches = _effectiveTool.findCommandsWithPrefix(cmdName);
      if (matches.length > 1) {
        output.writeln('Ambiguous command prefix ":$cmdName" matches:');
        for (final match in matches) {
          output.writeln('  :${match.name}');
        }
        return const ToolResult.failure('Ambiguous command prefix');
      }
      // Check help topics before giving up
      final topic = _effectiveTool.findHelpTopic(cmdName);
      if (topic != null) {
        output.writeln(
          HelpGenerator.generateTopicHelp(topic, tool: _effectiveTool),
        );
        return const ToolResult.success();
      }
      output.writeln('Unknown command: :$cmdName');
      return const ToolResult.failure('Unknown command');
    }
    final baseHelp = HelpGenerator.generateToolHelp(
      _effectiveTool,
      nestedCommandNames: _wiredExecutors.keys.toSet(),
    );
    output.write(baseHelp);
    final appendix = _builtInMacroDefineHelpAppendix();
    if (appendix != null) {
      output.writeln();
      output.writeln(appendix);
    }
    return const ToolResult.success();
  }

  /// Known built-in macro/define command names.
  static const _macroDefineCommands = {
    'macro', 'macros', 'unmacro', 'define', 'defines', 'undefine',
  };

  ToolResult? _tryHandleBuiltInMacroDefineCommand(
    String cmdName,
    CliArgs cliArgs,
  ) {
    if (!_macroDefineCommands.contains(cmdName)) return null;
    if (_effectiveTool.mode != ToolMode.multiCommand) return null;

    // Command matches but master yaml may be missing.
    final masterMissing = _checkMasterYamlMissing();
    if (masterMissing != null) return masterMissing;

    switch (cmdName) {
      case 'macro':
        return _handleRuntimeMacroDefine(cliArgs);
      case 'macros':
        return _handleRuntimeMacroList();
      case 'unmacro':
        return _handleRuntimeMacroRemove(cliArgs);
      case 'define':
        return _handlePersistentDefineAdd(cliArgs);
      case 'defines':
        return _handlePersistentDefineList();
      case 'undefine':
        return _handlePersistentDefineRemove(cliArgs);
      default:
        return null;
    }
  }

  String? _tryHandleBuiltInMacroDefineHelp(String cmdName) {
    if (!_macroDefineCommands.contains(cmdName)) return null;
    if (_effectiveTool.mode != ToolMode.multiCommand) return null;
    // Show help text even if master file is missing — the user may need
    // the help to understand how to set things up.

    switch (cmdName) {
      case 'macro':
        return 'Command: :macro\nDefine a runtime macro for this tool run.\nUsage: ${tool.name} :macro name=value';
      case 'macros':
        return 'Command: :macros\nList runtime macros for this tool run.\nUsage: ${tool.name} :macros';
      case 'unmacro':
        return 'Command: :unmacro\nRemove a runtime macro.\nUsage: ${tool.name} :unmacro name';
      case 'define':
        return '''Command: :define
Persist a define in ${tool.name}_master.yaml under the ${tool.name}: section.
Usage: ${tool.name} :define [-m MODE] name=value
Options:
  -m MODE  Store as mode-specific define (e.g., DEV-defines:)''';
      case 'defines':
        return '''Command: :defines
List all persisted defines from ${tool.name}_master.yaml.
Shows both default defines and mode-specific defines (DEV-defines:, CI-defines:, etc.)
Usage: ${tool.name} :defines''';
      case 'undefine':
        return '''Command: :undefine
Remove a persisted define from ${tool.name}_master.yaml.
Usage: ${tool.name} :undefine [-m MODE] name
Options:
  -m MODE  Remove from mode-specific defines (e.g., DEV-defines:)''';
      default:
        return null;
    }
  }

  String? _builtInMacroDefineHelpAppendix() {
    if (_effectiveTool.mode != ToolMode.multiCommand) return null;
    return '''<magenta>**Runtime Macros**</magenta>
  :macro <name>=<value>      Add runtime macro
  :macros                    List runtime macros
  :unmacro <name>            Remove runtime macro

<magenta>**Persistent Defines**</magenta>
  :define [-m MODE] <name>=<value>  Add define (use -m for mode-specific)
  :defines                          List all defines (default and mode-specific)
  :undefine [-m MODE] <name>        Remove define (use -m for mode-specific)

<cyan>**Pipeline Help**</cyan>
  Run `${tool.name} help pipelines` for pipeline configuration reference.
''';
  }

  bool _isMacroDefineFeatureEligible() {
    return ToolPipelineConfigLoader.isEligible(
      tool: _effectiveTool,
      fromDirectory: Directory.current.path,
    );
  }

  /// Returns an error [ToolResult] when the master yaml cannot be found,
  /// or `null` when the file exists and everything is fine.
  ToolResult? _checkMasterYamlMissing() {
    if (_isMacroDefineFeatureEligible()) return null;
    final wsRoot = findWorkspaceRoot(Directory.current.path);
    final expected = '${_effectiveTool.name}_master.yaml';
    output.writeln(
      'Cannot find $expected in workspace root ($wsRoot).\n'
      'Make sure you are running ${_effectiveTool.name} from inside the '
      'workspace that contains $expected.',
    );
    return ToolResult.failure('$expected not found');
  }

  String? _tryHandleBuiltInPipelinesHelp(String cmdName) {
    if (_effectiveTool.mode != ToolMode.multiCommand) return null;
    if (cmdName != 'pipelines') return null;
    return '''<cyan>**${tool.name} Pipeline Configuration**</cyan>

Pipelines are defined in <yellow>${tool.name}_master.yaml</yellow> under a <yellow>pipelines:</yellow> key.
Each pipeline has a name and a set of steps divided into three phases.

<green>**Pipeline Structure**</green>

  my-pipeline:
    executable: true          # whether this pipeline can be invoked directly
    runBefore: [other-pipe]   # pipelines to run before this one
    runAfter:  [other-pipe]   # pipelines to run after this one
    global-options:           # default option values for this pipeline
      output: build/
    precore:                  # steps run before core (setup/validation)
      - commands:
          - "shell echo Starting..."
    core:                     # main steps
      - commands:
          - "shell dart pub get"
          - "${tool.name} :build"
    postcore:                 # steps run after core (cleanup/reporting)
      - commands:
          - "shell echo Done."

<green>**Command Prefixes**</green>

  shell <cmd>          Run a shell command via /bin/bash -lc
  shell-scan <cmd>     Run a shell command in each scanned project folder
                       (supports placeholders: {project}, {path}, {name})
  ${tool.name} <cmd>   Run a ${tool.name} command (e.g. "${tool.name} :build")
  stdin <cmd>          Run a shell command with multi-line stdin input:
                         stdin cat -n
                         line one
                         line two

<green>**Placeholders (shell-scan)**</green>

  {project}   Relative path to the project folder
  {path}      Absolute path to the project folder
  {name}      Project/folder name

<green>**Invocation**</green>

  ${tool.name} <pipeline-name>             Run a named pipeline
  ${tool.name} <pipeline-name> --dry-run   Show commands without executing
  ${tool.name} --list                      List available pipelines
  ${tool.name} help pipelines             Show this help
''';
  }

  ToolResult _handleRuntimeMacroDefine(CliArgs cliArgs) {
    final parsed = _parseNameValueArg(cliArgs);
    if (parsed == null) {
      return const ToolResult.failure('Missing argument: name=value');
    }

    final (name, value) = parsed;
    _loadPersistedMacros();
    _runtimeMacros[name] = value;
    _savePersistedMacros();
    output.writeln('Added macro: $name: $value');
    return const ToolResult.success(processedCount: 1);
  }

  ToolResult _handleRuntimeMacroList() {
    _loadPersistedMacros();
    if (_runtimeMacros.isEmpty) {
      output.writeln('No macros defined.');
      return const ToolResult.success();
    }

    final keys = _runtimeMacros.keys.toList()..sort();
    for (final key in keys) {
      output.writeln('$key=${_runtimeMacros[key]}');
    }
    return const ToolResult.success(processedCount: 1);
  }

  ToolResult _handleRuntimeMacroRemove(CliArgs cliArgs) {
    final name = cliArgs.positionalArgs.isEmpty
        ? ''
        : cliArgs.positionalArgs.first.trim();
    if (name.isEmpty) {
      return const ToolResult.failure('Missing argument: macro name');
    }

    _loadPersistedMacros();
    final removed = _runtimeMacros.remove(name);
    if (removed == null) {
      return ToolResult.failure('Macro not found: $name');
    }

    _savePersistedMacros();
    output.writeln('Removed macro: $name : $removed');
    return const ToolResult.success(processedCount: 1);
  }

  /// Loads persisted macros from the `macros:` section of master.yaml into
  /// [_runtimeMacros]. A no-op if already loaded this invocation or if the
  /// section does not exist.
  ///
  /// Also performs one-time migration from legacy `{tool}_macros.yaml` file:
  /// if found, its contents are merged into master.yaml and the file is deleted.
  void _loadPersistedMacros() {
    if (_macrosLoaded) return;
    _macrosLoaded = true;

    try {
      final doc = _readMasterYaml();
      if (doc == null) return;
      final macros = doc['macros'];
      if (macros is! Map) return;
      for (final entry in macros.entries) {
        final k = entry.key?.toString();
        final v = entry.value?.toString();
        if (k != null && k.isNotEmpty && v != null) {
          _runtimeMacros[k] = v;
        }
      }
    } catch (_) {
      // Corrupt file — silently ignore; macros start empty this invocation.
    }
  }

  /// Writes [_runtimeMacros] to the `macros:` section of master.yaml.
  ///
  /// If [_runtimeMacros] is empty the `macros:` section is removed.
  void _savePersistedMacros() {
    _withMasterYaml((doc) {
      if (_runtimeMacros.isEmpty) {
        doc.remove('macros');
        return;
      }

      // Sort entries for deterministic output.
      final sorted = Map<String, String>.fromEntries(
        _runtimeMacros.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
      doc['macros'] = sorted;
    });
  }

  /// Parse mode flag from CLI args.
  ///
  /// Supports `-m MODE` or `--mode MODE` flags.
  /// Returns (mode, remaining args) or (null, original args).
  (String?, List<String>) _parseModeFlag(List<String> args) {
    final result = <String>[];
    String? mode;
    var i = 0;
    while (i < args.length) {
      final arg = args[i];
      if ((arg == '-m' || arg == '--mode') && i + 1 < args.length) {
        mode = args[i + 1];
        i += 2;
      } else {
        result.add(arg);
        i++;
      }
    }
    return (mode, result);
  }

  ToolResult _handlePersistentDefineAdd(CliArgs cliArgs) {
    // Parse optional -m MODE flag
    final (mode, remainingArgs) = _parseModeFlag(cliArgs.positionalArgs);

    // Parse name=value from remaining args
    final parsed = _parseNameValueFromList(remainingArgs);
    if (parsed == null) {
      return const ToolResult.failure('Missing argument: name=value');
    }
    final (name, value) = parsed;

    final result = _withMasterYaml((doc) {
      // Ensure tool section exists
      final toolSection = _ensureToolSection(doc);

      // Determine the key: 'defines' or '{MODE}-defines'
      final definesKey = mode != null ? '$mode-defines' : 'defines';

      // Read or create defines map
      final defines = _readToolDefines(toolSection, definesKey);
      defines[name] = value;

      // Sort and store
      final sorted = Map<String, String>.fromEntries(
        defines.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
      toolSection[definesKey] = sorted;
    });
    if (result != null) return result;

    final modePrefix = mode != null ? ' ($mode mode)' : '';
    output.writeln('Added define$modePrefix: $name: $value');
    return const ToolResult.success(processedCount: 1);
  }

  ToolResult _handlePersistentDefineList() {
    final doc = _readMasterYaml();
    if (doc == null) {
      output.writeln('No defines found.');
      return const ToolResult.success();
    }

    final toolSection = doc[tool.name] as Map<String, dynamic>? ?? {};
    final allDefines = <String, Map<String, String>>{};

    // Collect default defines
    final defaultDefines = _readToolDefines(toolSection, 'defines');
    if (defaultDefines.isNotEmpty) {
      allDefines['defines'] = defaultDefines;
    }

    // Collect mode-specific defines (keys ending with '-defines')
    for (final key in toolSection.keys) {
      final keyStr = key.toString();
      if (keyStr.endsWith('-defines') && keyStr != 'defines') {
        final modeDefines = _readToolDefines(toolSection, keyStr);
        if (modeDefines.isNotEmpty) {
          allDefines[keyStr] = modeDefines;
        }
      }
    }

    if (allDefines.isEmpty) {
      output.writeln('No defines found.');
      return const ToolResult.success();
    }

    // Print default defines first
    if (allDefines.containsKey('defines')) {
      output.writeln('defines:');
      final keys = allDefines['defines']!.keys.toList()..sort();
      for (final key in keys) {
        output.writeln('  $key=${allDefines['defines']![key]}');
      }
    }

    // Print mode-specific defines sorted by key
    final modeKeys = allDefines.keys.where((k) => k != 'defines').toList()
      ..sort();
    for (final modeKey in modeKeys) {
      output.writeln('$modeKey:');
      final keys = allDefines[modeKey]!.keys.toList()..sort();
      for (final key in keys) {
        output.writeln('  $key=${allDefines[modeKey]![key]}');
      }
    }

    return const ToolResult.success(processedCount: 1);
  }

  ToolResult _handlePersistentDefineRemove(CliArgs cliArgs) {
    // Parse optional -m MODE flag
    final (mode, remainingArgs) = _parseModeFlag(cliArgs.positionalArgs);

    final name = remainingArgs.isEmpty ? '' : remainingArgs.first.trim();
    if (name.isEmpty) {
      return const ToolResult.failure('Missing argument: define name');
    }

    String? removedValue;
    final result = _withMasterYaml((doc) {
      final toolSection = doc[tool.name] as Map<String, dynamic>?;
      if (toolSection == null) return;

      // Determine the key: 'defines' or '{MODE}-defines'
      final definesKey = mode != null ? '$mode-defines' : 'defines';

      final defines = _readToolDefines(toolSection, definesKey);
      removedValue = defines.remove(name);

      if (removedValue == null) return;

      final sorted = Map<String, String>.fromEntries(
        defines.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
      if (sorted.isEmpty) {
        toolSection.remove(definesKey);
        // Clean up empty tool section
        if (toolSection.isEmpty) {
          doc.remove(tool.name);
        }
      } else {
        toolSection[definesKey] = sorted;
      }
    });
    if (result != null) return result;

    if (removedValue == null) {
      final modePrefix = mode != null ? ' in $mode mode' : '';
      return ToolResult.failure('Define not found$modePrefix: $name');
    }

    final modePrefix = mode != null ? ' ($mode mode)' : '';
    output.writeln('Removed define$modePrefix: $name : $removedValue');
    return const ToolResult.success(processedCount: 1);
  }

  (String, String)? _parseNameValueArg(CliArgs cliArgs) {
    return _parseNameValueFromList(cliArgs.positionalArgs);
  }

  /// Parses a name=value pair from a list of arguments.
  ///
  /// The first argument should contain `name=value`, with subsequent
  /// arguments being concatenated as part of the value.
  (String, String)? _parseNameValueFromList(List<String> args) {
    if (args.isEmpty) return null;
    final first = args.first;
    final eqIndex = first.indexOf('=');
    if (eqIndex <= 0) return null;
    final name = first.substring(0, eqIndex).trim();
    final tail = <String>[first.substring(eqIndex + 1), ...args.skip(1)];
    final value = tail.join(' ').trim();
    if (name.isEmpty || value.isEmpty) return null;
    return (name, value);
  }

  Map<String, dynamic>? _readMasterYaml() {
    final wsRoot = findWorkspaceRoot(Directory.current.path);
    final path = '$wsRoot/${tool.name}_master.yaml';
    final file = File(path);
    if (!file.existsSync()) return null;

    final parsed = loadYaml(file.readAsStringSync());
    if (parsed is! YamlMap) return null;
    return _deepToDart(parsed) as Map<String, dynamic>;
  }

  ToolResult? _withMasterYaml(void Function(Map<String, dynamic> doc) mutate) {
    final wsRoot = findWorkspaceRoot(Directory.current.path);
    final path = '$wsRoot/${tool.name}_master.yaml';
    final file = File(path);
    if (!file.existsSync()) {
      return const ToolResult.failure('Tool master yaml not found');
    }

    final doc = _readMasterYaml();
    if (doc == null) {
      return const ToolResult.failure('Unable to parse tool master yaml');
    }

    mutate(doc);
    file.writeAsStringSync(_toYaml(doc));
    return null;
  }

  /// Ensures the tool-specific section exists in the document.
  ///
  /// Returns the existing or newly created section.
  Map<String, dynamic> _ensureToolSection(Map<String, dynamic> doc) {
    final existing = doc[tool.name];
    if (existing is Map<String, dynamic>) return existing;
    if (existing is Map) {
      final converted = Map<String, dynamic>.from(existing);
      doc[tool.name] = converted;
      return converted;
    }
    final newSection = <String, dynamic>{};
    doc[tool.name] = newSection;
    return newSection;
  }

  /// Reads defines from a specific key within the tool section.
  ///
  /// The key can be 'defines' or '{MODE}-defines'.
  Map<String, String> _readToolDefines(
    Map<String, dynamic> toolSection,
    String key,
  ) {
    final raw = toolSection[key];
    if (raw is! Map) return <String, String>{};
    final result = <String, String>{};
    for (final entry in raw.entries) {
      result[entry.key.toString()] = entry.value.toString();
    }
    return result;
  }

  /// Regex for `@[name]` define placeholders.
  static final _definePlaceholderPattern =
      RegExp(r'@\[([a-zA-Z_][a-zA-Z0-9_-]*)\]');

  /// Load defines from the master yaml, merging default + mode-specific.
  ///
  /// Reads the tool section's `defines:` key, then overlays any
  /// `{MODE}-defines:` sections for the given [modes].
  /// Returns an empty map if no master yaml or no defines exist.
  Map<String, String> _loadMasterDefines(List<String> modes) {
    final doc = _readMasterYaml();
    if (doc == null) return const {};

    final toolSection = doc[tool.name] as Map<String, dynamic>? ?? {};
    final defines = _readToolDefines(toolSection, 'defines');

    // Overlay mode-specific defines (later modes override earlier ones)
    for (final mode in modes) {
      final modeDefines = _readToolDefines(
        toolSection,
        '$mode-defines',
      );
      defines.addAll(modeDefines);
    }

    return _resolveDefineChain(defines);
  }

  /// Load defines for a specific project folder, merged with master defines.
  ///
  /// Reads `buildkit.yaml` (or `{tool.name}.yaml`) in [projectPath],
  /// extracts `defines:` and `{tool.name}: defines:`, and overlays
  /// mode-specific sections. Project defines override [masterDefines].
  Map<String, String> _loadProjectDefines(
    String projectPath,
    Map<String, String> masterDefines,
    List<String> modes,
  ) {
    final merged = Map<String, String>.from(masterDefines);

    final projectFile = File('$projectPath/buildkit.yaml');
    if (!projectFile.existsSync()) return merged;

    try {
      final parsed = loadYaml(projectFile.readAsStringSync());
      if (parsed is! YamlMap) return merged;
      final projectDoc = _deepToDart(parsed) as Map<String, dynamic>;

      // Extract from top-level defines:
      _mergeDefineSection(merged, projectDoc['defines']);
      // Extract from tool-specific section, e.g. buildkit: defines:
      final toolSection =
          projectDoc[tool.name] as Map<String, dynamic>? ?? {};
      _mergeDefineSection(merged, toolSection['defines']);

      // Overlay mode-specific defines from project
      for (final mode in modes) {
        _mergeDefineSection(merged, projectDoc['$mode-defines']);
        _mergeDefineSection(merged, toolSection['$mode-defines']);
      }
    } catch (_) {
      // Corrupt project yaml — silently use master defines only.
    }

    return _resolveDefineChain(merged);
  }

  /// Merge a defines section into [target].
  void _mergeDefineSection(Map<String, String> target, dynamic section) {
    if (section is! Map) return;
    for (final entry in section.entries) {
      target[entry.key.toString()] = entry.value.toString();
    }
  }

  /// Resolve `@[name]` define placeholders in a string.
  ///
  /// Unresolved placeholders are left as-is.
  String _resolveDefineString(String input, Map<String, String> defines) {
    if (defines.isEmpty) return input;
    return input.replaceAllMapped(_definePlaceholderPattern, (match) {
      final name = match.group(1)!;
      return defines[name] ?? match.group(0)!;
    });
  }

  /// Resolve defines that reference other defines.
  ///
  /// Supports chained references like `@[buildPath]/@[subdir]`
  /// with a maximum depth of 10.
  Map<String, String> _resolveDefineChain(Map<String, String> defines) {
    final resolved = <String, String>{};
    const maxDepth = 10;

    String resolveValue(String value, int depth) {
      if (depth > maxDepth) return value;
      return value.replaceAllMapped(_definePlaceholderPattern, (match) {
        final name = match.group(1)!;
        final replacement = defines[name];
        if (replacement != null) {
          return resolveValue(replacement, depth + 1);
        }
        return match.group(0)!;
      });
    }

    for (final entry in defines.entries) {
      resolved[entry.key] = resolveValue(entry.value, 0);
    }
    return resolved;
  }

  dynamic _deepToDart(dynamic value) {
    if (value is YamlMap) {
      final map = <String, dynamic>{};
      for (final entry in value.entries) {
        map[entry.key.toString()] = _deepToDart(entry.value);
      }
      return map;
    }
    if (value is YamlList) {
      return value.map(_deepToDart).toList();
    }
    return value;
  }

  String _toYaml(dynamic value, {int indent = 0}) {
    final pad = ' ' * indent;
    if (value is Map) {
      final lines = <String>[];
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final v = entry.value;
        if (v is Map || v is List) {
          lines.add('$pad$key:');
          lines.add(_toYaml(v, indent: indent + 2));
        } else {
          lines.add('$pad$key: ${_yamlScalar(v)}');
        }
      }
      return lines.join('\n');
    }
    if (value is List) {
      final lines = <String>[];
      for (final item in value) {
        if (item is Map || item is List) {
          lines.add('$pad-');
          lines.add(_toYaml(item, indent: indent + 2));
        } else {
          lines.add('$pad- ${_yamlScalar(item)}');
        }
      }
      return lines.join('\n');
    }
    return '$pad${_yamlScalar(value)}';
  }

  String _yamlScalar(dynamic value) {
    if (value == null) return 'null';
    if (value is num || value is bool) return '$value';
    final text = value.toString();
    final needsQuote =
        text.isEmpty ||
        text.contains(':') ||
        text.contains('#') ||
        text.contains('\n') ||
        text.startsWith(' ') ||
        text.endsWith(' ');
    if (!needsQuote) return text;
    final escaped = text.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    return '"$escaped"';
  }

  /// Delegate help for a wired command to the nested tool.
  ///
  /// Calls the nested tool's help system for detailed command help.
  Future<ToolResult> _delegateNestedHelp(
    NestedToolExecutor executor,
    CliArgs cliArgs,
  ) async {
    final args = <String>['--nested'];
    if (executor.isStandalone) {
      args.add('--help');
    } else {
      args.addAll(['help', executor.nestedCommand ?? '']);
    }

    try {
      final result = await runBinary(
        executor.binary,
        args,
        Directory.current.path,
      );
      final stdout = result.stdout.toString().trim();
      if (stdout.isNotEmpty) {
        output.writeln(stdout);
      }
      final stderr = result.stderr.toString().trim();
      if (stderr.isNotEmpty) {
        output.writeln(stderr);
      }
      return const ToolResult.success();
    } catch (_) {
      output.writeln(
        'Command :${executor.hostCommandName} — '
        'binary ${executor.binary} not found.',
      );
      return const ToolResult.failure('Nested help unavailable');
    }
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

  bool _isDoctorRequested(CliArgs cliArgs) {
    String normalize(String value) {
      final trimmed = value.trim();
      if (trimmed.startsWith(':')) return trimmed.substring(1);
      return trimmed;
    }

    if (cliArgs.commands.any((c) => normalize(c) == 'doctor')) return true;
    if (cliArgs.positionalArgs.any((p) => normalize(p) == 'doctor')) {
      return true;
    }
    return false;
  }

  void _printRequirementIssues(_RequirementCheckResult result) {
    if (result.warnings.isNotEmpty) {
      output.writeln('Environment warnings:');
      for (final warning in result.warnings) {
        output.writeln('  - $warning');
      }
    }
    if (result.errors.isNotEmpty) {
      output.writeln('Installation requirements not met:');
      for (final error in result.errors) {
        output.writeln('  - $error');
      }
    }
    final setupInstructions = result.setupInstructions?.trim();
    if (result.hasIssues &&
        setupInstructions != null &&
        setupInstructions.isNotEmpty) {
      output.writeln('Setup instructions:');
      output.writeln('  $setupInstructions');
    }
  }

  _RequirementCheckResult _runRequiredEnvironmentChecks() {
    final wsRoot = findWorkspaceRoot(Directory.current.path);
    final requiredMap = _loadRequiredEnvironmentSection(wsRoot);
    if (requiredMap == null) {
      return const _RequirementCheckResult();
    }

    final warnings = <String>[];
    final errors = <String>[];
    String? setupInstructions;

    final setup = requiredMap['setup'];
    if (setup is YamlMap) {
      setupInstructions = setup['instructions']?.toString();
    }

    final envVars = requiredMap['env-variables'];
    if (envVars is List) {
      for (final item in envVars) {
        if (item is! YamlMap) continue;
        final name = item['name']?.toString();
        if (name == null || name.isEmpty) continue;
        final value = Platform.environment[name];
        if (value != null && value.isNotEmpty) continue;
        final err = item['error']?.toString();
        final warn = item['warning']?.toString();
        if (err != null && err.isNotEmpty) {
          errors.add(err);
        } else if (warn != null && warn.isNotEmpty) {
          warnings.add(warn);
        }
      }
    }

    final folders = requiredMap['folders'];
    if (folders is List) {
      for (final item in folders) {
        if (item is! YamlMap) continue;
        final pathRaw = item['path']?.toString();
        if (pathRaw == null || pathRaw.isEmpty) continue;
        final path = _resolveEnvVars(pathRaw);
        if (Directory(path).existsSync()) continue;
        final err = item['error']?.toString();
        final warn = item['warning']?.toString();
        final name = item['name']?.toString() ?? pathRaw;
        if (err != null && err.isNotEmpty) {
          errors.add(err);
        } else if (warn != null && warn.isNotEmpty) {
          warnings.add(warn);
        } else {
          warnings.add('$name folder missing: $path');
        }
      }
    }

    final binaries = requiredMap['binaries'];
    if (binaries is List) {
      for (final item in binaries) {
        if (item is! YamlMap) continue;
        final binary = item['binary']?.toString();
        if (binary == null || binary.isEmpty) continue;

        if (!_isBinaryOnPath(binary)) {
          final err = item['error']?.toString();
          final warn = item['warning']?.toString();
          if (err != null && err.isNotEmpty) {
            errors.add(err);
          } else if (warn != null && warn.isNotEmpty) {
            warnings.add(warn);
          } else {
            warnings.add('$binary is not installed or not in PATH');
          }
          continue;
        }

        final versionTest = item['version-test']?.toString();
        final versionConstraint = item['version-constraint']?.toString();
        if (versionTest == null || versionConstraint == null) continue;

        final detectedVersion = _runVersionCommand(versionTest);
        if (detectedVersion == null) continue;

        final ok = _satisfiesCaretConstraint(
          detectedVersion,
          versionConstraint,
        );
        if (!ok) {
          final versionError = item['version-error']?.toString();
          if (versionError != null && versionError.isNotEmpty) {
            errors.add(
              versionError.replaceAll(
                '%{version-constraint}',
                versionConstraint,
              ),
            );
          } else {
            errors.add(
              '$binary version $detectedVersion does not satisfy '
              '$versionConstraint',
            );
          }
        }
      }
    }

    return _RequirementCheckResult(
      warnings: warnings,
      errors: errors,
      setupInstructions: setupInstructions,
    );
  }

  YamlMap? _loadRequiredEnvironmentSection(String wsRoot) {
    final candidates = <String>['${tool.name}_master.yaml'];
    if (tool.name == 'buildkit' && !candidates.contains(kBuildkitMasterYaml)) {
      candidates.add(kBuildkitMasterYaml);
    }

    for (final fileName in candidates) {
      final file = File('$wsRoot/$fileName');
      if (!file.existsSync()) continue;
      try {
        final parsed = loadYaml(file.readAsStringSync());
        if (parsed is! YamlMap) continue;
        final required = parsed['required-environment'];
        if (required is YamlMap) return required;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String _resolveEnvVars(String input) {
    return input.replaceAllMapped(RegExp(r'\$\[?(\w+)\]?'), (m) {
      final name = m.group(1)!;
      return Platform.environment[name] ?? m.group(0)!;
    });
  }

  bool _isBinaryOnPath(String binary) {
    final checker = Platform.isWindows ? 'where' : 'which';
    final result = Process.runSync(checker, [binary], runInShell: true);
    return result.exitCode == 0;
  }

  String? _runVersionCommand(String command) {
    try {
      final result = Platform.isWindows
          ? Process.runSync('cmd', ['/c', command], runInShell: true)
          : Process.runSync('/bin/bash', ['-lc', command], runInShell: true);
      final output = '${result.stdout ?? ''}\n${result.stderr ?? ''}'.trim();
      final match = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(output);
      if (match == null) return null;
      final major = match.group(1)!;
      final minor = match.group(2)!;
      final patch = match.group(3) ?? '0';
      return '$major.$minor.$patch';
    } catch (_) {
      return null;
    }
  }

  bool _satisfiesCaretConstraint(String version, String constraint) {
    if (!constraint.startsWith('^')) return true;
    final minV = _parseVersionInts(constraint.substring(1));
    final curV = _parseVersionInts(version);
    if (minV == null || curV == null) return true;

    if (curV[0] != minV[0]) return false;
    if (curV[1] < minV[1]) return false;
    if (curV[1] == minV[1] && curV[2] < minV[2]) return false;
    return true;
  }

  List<int>? _parseVersionInts(String input) {
    final m = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(input);
    if (m == null) return null;
    return [
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3) ?? '0'),
    ];
  }
}
