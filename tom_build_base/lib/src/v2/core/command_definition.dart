import 'option_definition.dart';

/// Git traversal order when both inner-first and outer-first are valid.
enum GitTraversalOrder {
  /// Submodules processed before parent repos.
  innerFirst,

  /// Parent repos processed before submodules.
  outerFirst,
}

/// Definition of a command within a multi-command tool.
///
/// Used to declare commands for tools like buildkit, enabling automatic
/// help generation, nature-based filtering, and traversal configuration.
class CommandDefinition {
  /// Command name (without : prefix, e.g., 'cleanup', 'compile').
  final String name;

  /// Human-readable description for help text.
  final String description;

  /// Alternative names for the command (e.g., 'ls' for 'list').
  final List<String> aliases;

  /// Command-specific options.
  final List<OptionDefinition> options;

  // Nature Requirements

  /// Folder MUST have ALL of these natures to run this command.
  /// null means command can run on any folder.
  final Set<Type>? requiredNatures;

  /// Natures this command can meaningfully work with.
  /// Used for documentation and filtering guidance.
  final Set<Type> worksWithNatures;

  // Traversal Support

  /// Whether command supports project traversal (--project, --exclude-projects, etc.).
  final bool supportsProjectTraversal;

  /// Whether command supports git traversal (--modules, --skip-modules, etc.).
  /// When true, allows git traversal if user specifies -i or -o.
  /// When false, errors if user attempts git traversal.
  final bool supportsGitTraversal;

  /// Whether command requires git traversal mode.
  /// When true, errors if user doesn't specify -i or -o.
  final bool requiresGitTraversal;

  /// Default git traversal order when command supports git traversal.
  /// null means user must explicitly specify.
  final GitTraversalOrder? defaultGitOrder;

  /// Whether command supports per-command --project/--exclude filters.
  final bool supportsPerCommandFilter;

  // Execution

  /// Whether command requires workspace traversal to run.
  /// false for commands like --help, --version.
  final bool requiresTraversal;

  /// Usage examples for help text.
  final List<String> examples;

  /// Whether this command can run as a standalone binary.
  final bool canRunStandalone;

  /// Whether command is hidden from help.
  final bool hidden;

  const CommandDefinition({
    required this.name,
    required this.description,
    this.aliases = const [],
    this.options = const [],
    this.requiredNatures,
    this.worksWithNatures = const {},
    this.supportsProjectTraversal = true,
    this.supportsGitTraversal = false,
    this.requiresGitTraversal = false,
    this.defaultGitOrder,
    this.supportsPerCommandFilter = false,
    this.requiresTraversal = true,
    this.examples = const [],
    this.canRunStandalone = false,
    this.hidden = false,
  });

  /// Get all options including traversal options if supported.
  List<OptionDefinition> get allOptions {
    final result = <OptionDefinition>[...options];
    if (supportsProjectTraversal) {
      result.addAll(projectTraversalOptions);
    }
    if (supportsGitTraversal) {
      result.addAll(gitTraversalOptions);
    }
    return result;
  }

  /// Format for help text (e.g., ':cleanup, :clean').
  String get usage {
    final buf = StringBuffer(':$name');
    for (final alias in aliases) {
      buf.write(', :$alias');
    }
    return buf.toString();
  }

  @override
  String toString() => 'CommandDefinition($name)';
}
