/// Type of option value.
enum OptionType {
  /// Boolean flag (--verbose, --no-verbose).
  flag,

  /// Single value option (--config=path).
  option,

  /// Multiple value option, can be repeated (--exclude=a --exclude=b).
  multiOption,
}

/// Definition of a CLI option.
///
/// Used to declare options for tools and commands, enabling automatic
/// help generation, argument parsing, and shell completion.
class OptionDefinition {
  /// Option name (without dashes, e.g., 'verbose', 'config').
  final String name;

  /// Short abbreviation (single character, e.g., 'v', 'c').
  final String? abbr;

  /// Human-readable description for help text.
  final String description;

  /// Type of option (flag, option, multiOption).
  final OptionType type;

  /// Default value (as string, null if no default).
  final String? defaultValue;

  /// Allowed values (for validation and completion).
  final List<String>? allowedValues;

  /// Whether this option is mandatory.
  final bool mandatory;

  /// Whether flag can be negated (--no-X).
  final bool negatable;

  /// Value name for help text (e.g., 'path', 'pattern').
  final String? valueName;

  /// Whether this option is hidden from help.
  final bool hidden;

  const OptionDefinition({
    required this.name,
    this.abbr,
    required this.description,
    this.type = OptionType.flag,
    this.defaultValue,
    this.allowedValues,
    this.mandatory = false,
    this.negatable = false,
    this.valueName,
    this.hidden = false,
  });

  /// Create a flag option.
  const OptionDefinition.flag({
    required this.name,
    this.abbr,
    required this.description,
    this.defaultValue,
    this.negatable = false,
    this.hidden = false,
  }) : type = OptionType.flag,
       allowedValues = null,
       mandatory = false,
       valueName = null;

  /// Create a single-value option.
  const OptionDefinition.option({
    required this.name,
    this.abbr,
    required this.description,
    this.defaultValue,
    this.allowedValues,
    this.mandatory = false,
    this.valueName,
    this.hidden = false,
  }) : type = OptionType.option,
       negatable = false;

  /// Create a multi-value option.
  const OptionDefinition.multi({
    required this.name,
    this.abbr,
    required this.description,
    this.allowedValues,
    this.mandatory = false,
    this.valueName,
    this.hidden = false,
  }) : type = OptionType.multiOption,
       defaultValue = null,
       negatable = false;

  /// Format for help text (e.g., '-v, --verbose').
  String get usage {
    final buf = StringBuffer();
    if (abbr != null) {
      buf.write('-$abbr, ');
    } else {
      buf.write('    ');
    }
    buf.write('--$name');
    if (type != OptionType.flag && valueName != null) {
      buf.write('=<$valueName>');
    }
    return buf.toString();
  }

  @override
  String toString() => 'OptionDefinition($name)';
}

// ============================================================================
// Standard option definitions used across tools
// ============================================================================

/// Standard options for project traversal.
const List<OptionDefinition> projectTraversalOptions = [
  OptionDefinition.option(
    name: 'scan',
    abbr: 's',
    description: 'Starting path for scan',
    valueName: 'path',
  ),
  OptionDefinition.flag(
    name: 'recursive',
    abbr: 'r',
    description: 'Recurse into subdirectories',
  ),
  OptionDefinition.flag(
    name: 'not-recursive',
    description: 'Do not recurse (overrides -r)',
  ),
  OptionDefinition.multi(
    name: 'recursion-exclude',
    description: 'Patterns to skip during descent',
    valueName: 'pattern',
  ),
  OptionDefinition.multi(
    name: 'project',
    abbr: 'p',
    description: 'Project names/IDs to include',
    valueName: 'pattern',
  ),
  OptionDefinition.multi(
    name: 'exclude-projects',
    description: 'Project names to exclude',
    valueName: 'name',
  ),
  OptionDefinition.flag(
    name: 'build-order',
    abbr: 'b',
    description: 'Sort by dependency order (default)',
  ),
  OptionDefinition.flag(
    name: 'no-skip',
    description: 'Ignore skip markers (tom_skip.yaml, *_skip.yaml)',
  ),
];

/// Standard options for git traversal.
const List<OptionDefinition> gitTraversalOptions = [
  OptionDefinition.multi(
    name: 'modules',
    abbr: 'm',
    description: 'Git submodules to include',
    valueName: 'name',
  ),
  OptionDefinition.multi(
    name: 'skip-modules',
    description: 'Git submodules to exclude',
    valueName: 'name',
  ),
  OptionDefinition.flag(
    name: 'inner-first-git',
    abbr: 'i',
    description: 'Process inner repos (submodules) first',
  ),
  OptionDefinition.flag(
    name: 'outer-first-git',
    abbr: 'o',
    description: 'Process outer repos first',
  ),
  OptionDefinition.flag(
    name: 'top-repo',
    abbr: 'T',
    description: 'Find topmost git repo and use as root (requires -i or -o)',
  ),
];

/// Common options for all tools.
const List<OptionDefinition> commonOptions = [
  OptionDefinition.multi(
    name: 'exclude',
    abbr: 'x',
    description: 'Path patterns to exclude',
    valueName: 'pattern',
  ),
  OptionDefinition.flag(
    name: 'test',
    description: 'Include zom_* test projects',
  ),
  OptionDefinition.flag(
    name: 'test-only',
    description: 'ONLY process zom_* test projects',
  ),
  OptionDefinition.option(
    name: 'execution-root',
    abbr: 'R',
    description: 'Workspace root path',
    valueName: 'path',
  ),
  OptionDefinition.flag(
    name: 'verbose',
    abbr: 'v',
    description: 'Enable verbose output',
  ),
  OptionDefinition.flag(
    name: 'dry-run',
    abbr: 'n',
    description: 'Show what would be done without doing it',
  ),
  OptionDefinition.flag(
    name: 'help',
    abbr: 'h',
    description: 'Show help message',
  ),
  OptionDefinition.flag(name: 'version', description: 'Show version'),
];
