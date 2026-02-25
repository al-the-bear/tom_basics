import 'command_definition.dart';
import 'help_topic.dart';
import 'option_definition.dart';

/// Mode in which a tool can operate.
enum ToolMode {
  /// Multi-command tool like buildkit (supports :command syntax).
  multiCommand,

  /// Single-command tool.
  singleCommand,

  /// Tool that can operate in both modes.
  hybrid,
}

/// Navigation features supported by a tool.
class NavigationFeatures {
  /// Whether tool supports project traversal.
  final bool projectTraversal;

  /// Whether tool supports git traversal.
  final bool gitTraversal;

  /// Whether tool supports recursive folder scanning.
  final bool recursiveScan;

  /// Whether tool supports interactive mode.
  final bool interactiveMode;

  /// Whether tool supports dry-run mode.
  final bool dryRun;

  /// Whether tool supports JSON output.
  final bool jsonOutput;

  /// Whether tool supports verbose output.
  final bool verbose;

  const NavigationFeatures({
    this.projectTraversal = true,
    this.gitTraversal = false,
    this.recursiveScan = true,
    this.interactiveMode = false,
    this.dryRun = false,
    this.jsonOutput = false,
    this.verbose = true,
  });

  /// All navigation features enabled.
  static const all = NavigationFeatures(
    projectTraversal: true,
    gitTraversal: true,
    recursiveScan: true,
    interactiveMode: true,
    dryRun: true,
    jsonOutput: true,
    verbose: true,
  );

  /// Minimal features (only verbose).
  static const minimal = NavigationFeatures(
    projectTraversal: false,
    gitTraversal: false,
    recursiveScan: false,
    interactiveMode: false,
    dryRun: false,
    jsonOutput: false,
    verbose: true,
  );

  /// Default project tool features.
  static const projectTool = NavigationFeatures(
    projectTraversal: true,
    gitTraversal: false,
    recursiveScan: true,
    interactiveMode: false,
    dryRun: false,
    jsonOutput: false,
    verbose: true,
  );

  /// Default git tool features.
  static const gitTool = NavigationFeatures(
    projectTraversal: false,
    gitTraversal: true,
    recursiveScan: true,
    interactiveMode: false,
    dryRun: false,
    jsonOutput: false,
    verbose: true,
  );

  @override
  String toString() {
    final enabled = <String>[];
    if (projectTraversal) enabled.add('projectTraversal');
    if (gitTraversal) enabled.add('gitTraversal');
    if (recursiveScan) enabled.add('recursiveScan');
    if (interactiveMode) enabled.add('interactiveMode');
    if (dryRun) enabled.add('dryRun');
    if (jsonOutput) enabled.add('jsonOutput');
    if (verbose) enabled.add('verbose');
    return 'NavigationFeatures(${enabled.join(', ')})';
  }
}

/// Definition of a CLI tool for buildkit and similar applications.
///
/// Provides metadata for automatic help generation, argument parsing,
/// and traversal configuration.
class ToolDefinition {
  /// Tool name (e.g., 'buildkit', 'ws_tools').
  final String name;

  /// Human-readable description for help text.
  final String description;

  /// Version string (e.g., '2.0.0').
  final String version;

  /// Tool mode (multi-command, single-command, hybrid).
  final ToolMode mode;

  /// Navigation features supported by this tool.
  final NavigationFeatures features;

  /// Tool-level options (applied before command).
  final List<OptionDefinition> globalOptions;

  /// Available commands (empty for single-command tools).
  final List<CommandDefinition> commands;

  /// Default command when none specified (multi-command tools).
  final String? defaultCommand;

  /// Footer text for help output.
  final String? helpFooter;

  /// Help topics available via `tool help <topic>`.
  ///
  /// Topics provide documentation sections that are separate from commands.
  /// Use [defaultHelpTopics] from `builtin_help_topics.dart` for built-in topics.
  final List<HelpTopic> helpTopics;

  /// Nature types that ALL must be present on a folder for the tool to run.
  ///
  /// Used for singleCommand tools where there is no [CommandDefinition].
  /// If non-empty, [worksWithNatures] is ignored.
  final Set<Type>? requiredNatures;

  /// Nature types where at least ONE must be present on a folder.
  ///
  /// Used for singleCommand tools where there is no [CommandDefinition].
  /// Only used when [requiredNatures] is null or empty.
  final Set<Type> worksWithNatures;

  const ToolDefinition({
    required this.name,
    required this.description,
    this.version = '1.0.0',
    this.mode = ToolMode.multiCommand,
    this.features = const NavigationFeatures(),
    this.globalOptions = const [],
    this.commands = const [],
    this.defaultCommand,
    this.helpFooter,
    this.helpTopics = const [],
    this.requiredNatures,
    this.worksWithNatures = const {},
  });

  /// Find a help topic by name.
  ///
  /// Returns null if no topic matches.
  HelpTopic? findHelpTopic(String name) {
    for (final topic in helpTopics) {
      if (topic.name == name) return topic;
    }
    return null;
  }

  /// Find command by name, alias, or unambiguous prefix.
  ///
  /// Search order:
  /// 1. Exact match on name
  /// 2. Exact match on alias
  /// 3. Unambiguous prefix match on name (e.g., 'vers' → 'versioner')
  /// 4. Unambiguous prefix match on alias
  ///
  /// Returns null if no match or multiple commands match the prefix.
  CommandDefinition? findCommand(String nameOrAlias) {
    // 1. Exact match on name
    for (final cmd in commands) {
      if (cmd.name == nameOrAlias) {
        return cmd;
      }
    }

    // 2. Exact match on alias
    for (final cmd in commands) {
      if (cmd.aliases.contains(nameOrAlias)) {
        return cmd;
      }
    }

    // 3. Prefix match on name
    final nameMatches = <CommandDefinition>[];
    for (final cmd in commands) {
      if (cmd.name.startsWith(nameOrAlias)) {
        nameMatches.add(cmd);
      }
    }
    if (nameMatches.length == 1) {
      return nameMatches.first;
    }

    // 4. Prefix match on aliases (only if no name prefix matches)
    if (nameMatches.isEmpty) {
      final aliasMatches = <CommandDefinition>[];
      for (final cmd in commands) {
        if (cmd.aliases.any((alias) => alias.startsWith(nameOrAlias))) {
          aliasMatches.add(cmd);
        }
      }
      if (aliasMatches.length == 1) {
        return aliasMatches.first;
      }
    }

    return null;
  }

  /// Find all commands matching a prefix.
  ///
  /// Useful for error messages when a prefix is ambiguous.
  List<CommandDefinition> findCommandsWithPrefix(String prefix) {
    final matches = <CommandDefinition>[];
    for (final cmd in commands) {
      if (cmd.name.startsWith(prefix) ||
          cmd.aliases.any((alias) => alias.startsWith(prefix))) {
        matches.add(cmd);
      }
    }
    return matches;
  }

  /// Get all visible commands (not hidden).
  List<CommandDefinition> get visibleCommands {
    return commands.where((c) => !c.hidden).toList();
  }

  /// Get all global options including feature-based options.
  List<OptionDefinition> get allGlobalOptions {
    final result = <OptionDefinition>[...globalOptions];

    if (features.projectTraversal) {
      result.addAll(projectTraversalOptions);
    }
    if (features.gitTraversal) {
      result.addAll(gitTraversalOptions);
    }

    // Add common options (includes standard options like --help, --version, --dry-run)
    result.addAll(commonOptions);

    // Add feature-specific options (not in commonOptions)
    if (features.jsonOutput) {
      result.add(
        const OptionDefinition.flag(
          name: 'json',
          description: 'Output results in JSON format',
        ),
      );
    }
    if (features.interactiveMode) {
      result.add(
        const OptionDefinition.flag(
          name: 'interactive',
          abbr: 'i',
          description: 'Run in interactive mode',
        ),
      );
    }

    // Deduplicate by name, keeping first occurrence so user-defined
    // globalOptions take precedence over commonOptions defaults.
    final deduped = <String, OptionDefinition>{};
    for (final option in result) {
      deduped.putIfAbsent(option.name, () => option);
    }

    return deduped.values.toList();
  }

  @override
  String toString() => 'ToolDefinition($name v$version)';
}
