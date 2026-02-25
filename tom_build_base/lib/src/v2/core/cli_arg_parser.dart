import 'command_definition.dart';
import 'option_definition.dart';
import 'tool_definition.dart';
import '../traversal/traversal_info.dart';

/// Traversal defaults loaded from buildkit_master.yaml navigation section.
///
/// Used as fallback when CLI options are not explicitly provided.
/// Priority cascade: CLI > config defaults > hardcoded defaults.
class TraversalDefaults {
  /// Starting scan path (default: '.').
  final String? scan;

  /// Whether to scan recursively (default: true).
  final bool? recursive;

  /// Exclude patterns for paths.
  final List<String>? exclude;

  /// Exclude patterns for project names.
  final List<String>? excludeProjects;

  /// Patterns to skip during recursive descent.
  final List<String>? recursionExclude;

  const TraversalDefaults({
    this.scan,
    this.recursive,
    this.exclude,
    this.excludeProjects,
    this.recursionExclude,
  });

  /// Create from a navigation defaults map (from buildkit_master.yaml).
  factory TraversalDefaults.fromMap(Map<String, dynamic>? navMap) {
    if (navMap == null) return const TraversalDefaults();
    return TraversalDefaults(
      scan: navMap['scan'] as String?,
      recursive: navMap['recursive'] as bool?,
      exclude: _toStringList(navMap['exclude']),
      excludeProjects: _toStringList(
        navMap['exclude-projects'] ?? navMap['excludeProjects'],
      ),
      recursionExclude: _toStringList(
        navMap['recursion-exclude'] ?? navMap['recursionExclude'],
      ),
    );
  }

  static List<String>? _toStringList(dynamic value) {
    if (value == null) return null;
    if (value is List) return value.map((e) => e.toString()).toList();
    return null;
  }
}

/// Parsed command-line arguments.
///
/// Provides the raw parsed values from command-line arguments before
/// conversion to TraversalInfo objects.
class CliArgs {
  // Scan/traversal options
  final String? scan;
  final bool recursive;
  final bool notRecursive;
  final String? root;
  final bool bareRoot;

  // Track whether options were explicitly set via CLI
  // (used for defaults cascade: CLI > config > hardcoded)
  final bool scanExplicitlySet;
  final bool recursiveExplicitlySet;

  // Exclude/include patterns
  final List<String> excludePatterns;
  final List<String> excludeProjects;
  final List<String> recursionExclude;
  final List<String> projectPatterns;

  // Git options
  final List<String> modules;
  final List<String> skipModules;
  final bool innerFirstGit;
  final bool outerFirstGit;
  final bool topRepo;

  // Build options
  final bool buildOrder;
  final bool workspaceRecursion;

  // Common options
  final bool verbose;
  final bool dryRun;
  final bool listOnly;
  final bool force;
  final bool guide;
  final bool dumpConfig;
  final String? configPath;
  final bool help;
  final bool version;
  final bool noSkip;

  // Test project options
  final bool includeTestProjects;
  final bool testProjectsOnly;

  // Positional args and commands
  final List<String> positionalArgs;
  final List<String> commands;
  final Map<String, PerCommandArgs> commandArgs;

  // Extra options captured as key-value pairs
  final Map<String, dynamic> extraOptions;

  const CliArgs({
    this.scan,
    this.recursive = false,
    this.notRecursive = false,
    this.root,
    this.bareRoot = false,
    this.scanExplicitlySet = false,
    this.recursiveExplicitlySet = false,
    this.excludePatterns = const [],
    this.excludeProjects = const [],
    this.recursionExclude = const [],
    this.projectPatterns = const [],
    this.modules = const [],
    this.skipModules = const [],
    this.innerFirstGit = false,
    this.outerFirstGit = false,
    this.topRepo = false,
    this.buildOrder = true,
    this.workspaceRecursion = false,
    this.verbose = false,
    this.dryRun = false,
    this.listOnly = false,
    this.force = false,
    this.guide = false,
    this.dumpConfig = false,
    this.configPath,
    this.help = false,
    this.version = false,
    this.noSkip = false,
    this.includeTestProjects = false,
    this.testProjectsOnly = false,
    this.positionalArgs = const [],
    this.commands = const [],
    this.commandArgs = const {},
    this.extraOptions = const {},
  });

  /// Convert to ProjectTraversalInfo.
  ///
  /// Applies defaults cascade: CLI > [configDefaults] > hardcoded defaults.
  /// Hardcoded defaults are `scan: '.'`, `recursive: true`.
  ///
  /// Requires [executionRoot] to be provided if not set in args.
  /// [configDefaults] is optional config from buildkit_master.yaml navigation section.
  ProjectTraversalInfo toProjectTraversalInfo({
    String? executionRoot,
    TraversalDefaults? configDefaults,
  }) {
    final effectiveRoot = root ?? executionRoot ?? '.';

    // Resolve scan: CLI > config > default '.'
    final effectiveScan = scanExplicitlySet
        ? (scan ?? '.')
        : (configDefaults?.scan ?? scan ?? '.');

    // Resolve recursive: CLI > config > default false
    // Default is --not-recursive (scan single dir, not recursively)
    // -r explicitly enables recursion
    final bool effectiveRecursive;
    if (notRecursive) {
      effectiveRecursive = false;
    } else if (recursiveExplicitlySet) {
      effectiveRecursive = recursive;
    } else {
      effectiveRecursive =
          configDefaults?.recursive ?? false; // Default: not recursive
    }

    // Merge exclude patterns: CLI + config
    final mergedExclude = <String>[
      ...excludePatterns,
      ...?configDefaults?.exclude,
    ];
    final mergedExcludeProjects = <String>[
      ...excludeProjects,
      ...?configDefaults?.excludeProjects,
    ];
    final mergedRecursionExclude = <String>[
      ...recursionExclude,
      ...?configDefaults?.recursionExclude,
    ];

    return ProjectTraversalInfo(
      scan: effectiveScan,
      recursive: effectiveRecursive,
      executionRoot: effectiveRoot,
      excludePatterns: mergedExclude,
      excludeProjects: mergedExcludeProjects,
      recursionExclude: mergedRecursionExclude,
      projectPatterns: projectPatterns,
      buildOrder: buildOrder,
      includeTestProjects: includeTestProjects,
      testProjectsOnly: testProjectsOnly,
      ignoreSkipMarkers: noSkip,
    );
  }

  /// Convert to GitTraversalInfo.
  ///
  /// Requires [executionRoot] to be provided if not set in args.
  /// [commandDefaultGitOrder] is the command's default git order if specified.
  ///
  /// Git traversal mode must be determined from one of:
  /// 1. CLI flags (--inner-first-git or --outer-first-git)
  /// 2. Command's default git order
  ///
  /// Returns null if git mode cannot be determined (caller should emit error).
  GitTraversalInfo? toGitTraversalInfo({
    String? executionRoot,
    GitTraversalOrder? commandDefaultGitOrder,
  }) {
    final effectiveRoot = root ?? executionRoot ?? '.';

    // Determine git mode: CLI > command default
    final GitTraversalMode? mode;
    if (innerFirstGit) {
      mode = GitTraversalMode.innerFirst;
    } else if (outerFirstGit) {
      mode = GitTraversalMode.outerFirst;
    } else if (commandDefaultGitOrder != null) {
      mode = commandDefaultGitOrder == GitTraversalOrder.innerFirst
          ? GitTraversalMode.innerFirst
          : GitTraversalMode.outerFirst;
    } else {
      // No git mode specified and no command default - caller must handle error
      return null;
    }

    return GitTraversalInfo(
      executionRoot: effectiveRoot,
      excludePatterns: excludePatterns,
      modules: modules,
      skipModules: skipModules,
      gitMode: mode,
      includeTestProjects: includeTestProjects,
      testProjectsOnly: testProjectsOnly,
    );
  }

  /// Whether git traversal mode is explicitly specified via CLI.
  bool get gitModeExplicitlySet => innerFirstGit || outerFirstGit;

  /// Whether effective recursive mode is on.
  bool get effectiveRecursive => recursive && !notRecursive;

  /// Whether help or version was requested.
  bool get isHelpOrVersion => help || version;

  /// Create a copy with placeholders resolved in user-provided string values.
  ///
  /// Resolves placeholders in [positionalArgs], string values in
  /// [extraOptions], and per-command [PerCommandArgs.options].
  /// Other fields (flags, patterns, traversal config) are copied as-is.
  ///
  /// The [resolver] function is called for each string value.
  /// Typically wraps [ExecutePlaceholderResolver.resolveCommand].
  CliArgs withResolvedStrings(String Function(String) resolver) {
    return CliArgs(
      scan: scan,
      recursive: recursive,
      notRecursive: notRecursive,
      root: root,
      bareRoot: bareRoot,
      scanExplicitlySet: scanExplicitlySet,
      recursiveExplicitlySet: recursiveExplicitlySet,
      excludePatterns: excludePatterns,
      excludeProjects: excludeProjects,
      recursionExclude: recursionExclude,
      projectPatterns: projectPatterns,
      modules: modules,
      skipModules: skipModules,
      innerFirstGit: innerFirstGit,
      outerFirstGit: outerFirstGit,
      topRepo: topRepo,
      buildOrder: buildOrder,
      workspaceRecursion: workspaceRecursion,
      verbose: verbose,
      dryRun: dryRun,
      listOnly: listOnly,
      force: force,
      guide: guide,
      dumpConfig: dumpConfig,
      configPath: configPath,
      help: help,
      version: version,
      noSkip: noSkip,
      includeTestProjects: includeTestProjects,
      testProjectsOnly: testProjectsOnly,
      positionalArgs: positionalArgs.map(resolver).toList(),
      commands: commands,
      commandArgs: commandArgs.map(
        (k, v) => MapEntry(
          k,
          PerCommandArgs(
            commandName: v.commandName,
            projectPatterns: v.projectPatterns,
            excludePatterns: v.excludePatterns,
            options: _resolveMapValues(v.options, resolver),
          ),
        ),
      ),
      extraOptions: _resolveMapValues(extraOptions, resolver),
    );
  }

  /// Resolve string values in a map, leaving non-strings unchanged.
  static Map<String, dynamic> _resolveMapValues(
    Map<String, dynamic> map,
    String Function(String) resolver,
  ) {
    return map.map((k, v) {
      if (v is String) return MapEntry(k, resolver(v));
      if (v is List) {
        return MapEntry(
          k,
          v.map((e) => e is String ? resolver(e) : e).toList(),
        );
      }
      return MapEntry(k, v);
    });
  }
}

/// Per-command arguments for multi-command tools.
class PerCommandArgs {
  /// Command name (without : prefix).
  final String commandName;

  /// Command-specific project patterns.
  final List<String> projectPatterns;

  /// Command-specific exclude patterns.
  final List<String> excludePatterns;

  /// Extra command-specific options.
  final Map<String, dynamic> options;

  const PerCommandArgs({
    required this.commandName,
    this.projectPatterns = const [],
    this.excludePatterns = const [],
    this.options = const {},
  });
}

/// Parser for command-line arguments.
///
/// Parses arguments using the flexible buildkit/Tom CLI conventions:
/// - Short options: -s, -r, -v
/// - Long options: --scan, --recursive, --verbose
/// - Values: -s ., --scan=., --scan .
/// - Multi-value: -p pattern1 -p pattern2, --project=pattern1,pattern2
/// - Commands: :command, :cleanup, :compile
/// - Per-command args: :cmd --project=x (after :cmd until next :cmd)
class CliArgParser {
  final ToolDefinition? toolDefinition;
  final List<OptionDefinition> allowedOptions;

  CliArgParser({this.toolDefinition, this.allowedOptions = const []});

  /// Parse command-line arguments.
  CliArgs parse(List<String> args) {
    final result = _ParseState();

    var i = 0;
    while (i < args.length) {
      final arg = args[i];

      // Check for command (starts with :)
      if (arg.startsWith(':')) {
        final cmdName = arg.substring(1);
        result.commands.add(cmdName);
        result.currentCommand = cmdName;
        result.commandArgs[cmdName] = _PerCommandState();
        i++;
        continue;
      }

      // Check for long option
      if (arg.startsWith('--')) {
        i = _parseLongOption(args, i, result);
        continue;
      }

      // Check for short option
      if (arg.startsWith('-') && arg.length > 1) {
        i = _parseShortOption(args, i, result);
        continue;
      }

      // Positional argument
      result.positionalArgs.add(arg);
      i++;
    }

    return result.toCliArgs();
  }

  int _parseLongOption(List<String> args, int index, _ParseState state) {
    final arg = args[index];
    final withoutPrefix = arg.substring(2);

    // Check for = separator
    final eqIndex = withoutPrefix.indexOf('=');
    String name;
    String? value;

    if (eqIndex >= 0) {
      name = withoutPrefix.substring(0, eqIndex);
      value = withoutPrefix.substring(eqIndex + 1);
    } else {
      name = withoutPrefix;
      // Check if next arg is a value (not an option or command)
      if (index + 1 < args.length &&
          !args[index + 1].startsWith('-') &&
          !args[index + 1].startsWith(':')) {
        // Only consume as value if option expects a value
        if (_optionExpectsValue(name)) {
          value = args[index + 1];
          index++;
        }
      }
    }

    _setOption(state, name, value);
    return index + 1;
  }

  int _parseShortOption(List<String> args, int index, _ParseState state) {
    final arg = args[index];

    // Handle bundled short options like -rv
    if (arg.length > 2 && !_optionExpectsValue(_shortToLong(arg[1]))) {
      // Multiple flags bundled together
      for (var i = 1; i < arg.length; i++) {
        final shortName = arg[i];
        final longName = _shortToLong(shortName);
        _setOption(state, longName, null);
      }
      return index + 1;
    }

    // Single short option
    final shortName = arg.substring(1, 2);
    final longName = _shortToLong(shortName);

    String? value;
    if (arg.length > 2) {
      // Value attached: -svalue
      value = arg.substring(2);
    } else if (index + 1 < args.length &&
        !args[index + 1].startsWith('-') &&
        !args[index + 1].startsWith(':') &&
        _optionExpectsValue(longName)) {
      // Value as next arg
      value = args[index + 1];
      index++;
    }

    _setOption(state, longName, value);
    return index + 1;
  }

  void _setOption(_ParseState state, String name, String? value) {
    // Handle per-command options
    if (state.currentCommand != null) {
      final cmdState = state.commandArgs[state.currentCommand!]!;
      if (name == 'project' || name == 'p') {
        if (value != null) cmdState.projectPatterns.addAll(_splitValue(value));
        return;
      }
      if (name == 'exclude' || name == 'exclude-projects') {
        if (value != null) cmdState.excludePatterns.addAll(_splitValue(value));
        return;
      }
      cmdState.options[name] = value ?? true;
      return;
    }

    // Global options
    switch (name) {
      case 'scan':
      case 's':
        state.scan = value;
        state.scanExplicitlySet = true;
        break;
      case 'recursive':
      case 'r':
        state.recursive = true;
        state.recursiveExplicitlySet = true;
        break;
      case 'not-recursive':
        state.notRecursive = true;
        state.recursiveExplicitlySet = true;
        break;
      case 'root':
      case 'R':
        state.root = value;
        if (value == null) state.bareRoot = true;
        break;
      case 'exclude':
      case 'x':
        if (value != null) state.excludePatterns.addAll(_splitValue(value));
        break;
      case 'exclude-projects':
        if (value != null) state.excludeProjects.addAll(_splitValue(value));
        break;
      case 'recursion-exclude':
        if (value != null) state.recursionExclude.addAll(_splitValue(value));
        break;
      case 'project':
      case 'p':
        if (value != null) state.projectPatterns.addAll(_splitValue(value));
        break;
      case 'modules':
      case 'm':
        if (value != null) state.modules.addAll(_splitValue(value));
        break;
      case 'skip-modules':
        if (value != null) state.skipModules.addAll(_splitValue(value));
        break;
      case 'inner-first-git':
      case 'i':
        state.innerFirstGit = true;
        break;
      case 'outer-first-git':
      case 'o':
        state.outerFirstGit = true;
        break;
      case 'top-repo':
      case 'T':
        state.topRepo = true;
        break;
      case 'build-order':
      case 'b':
        state.buildOrder = true;
        break;
      case 'workspace-recursion':
        state.workspaceRecursion = true;
        break;
      case 'verbose':
      case 'v':
        state.verbose = true;
        break;
      case 'dry-run':
      case 'n':
        state.dryRun = true;
        break;
      case 'list':
      case 'l':
        state.listOnly = true;
        break;
      case 'force':
      case 'f':
        state.force = true;
        break;
      case 'guide':
        state.guide = true;
        break;
      case 'dump-config':
        state.dumpConfig = true;
        break;
      case 'config':
        state.configPath = value;
        break;
      case 'help':
      case 'h':
      case '?':
        state.help = true;
        break;
      case 'version':
      case 'V':
        state.version = true;
        break;
      case 'no-skip':
        state.noSkip = true;
        break;
      case 'include-test-projects':
        state.includeTestProjects = true;
        break;
      case 'test-projects-only':
        state.testProjectsOnly = true;
        break;
      default:
        state.extraOptions[name] = value ?? true;
    }
  }

  bool _optionExpectsValue(String name) {
    // Known global options that expect values
    const valueOptions = {
      'scan',
      's',
      'root',
      'R',
      'exclude',
      'x',
      'exclude-projects',
      'recursion-exclude',
      'project',
      'p',
      'modules',
      'm',
      'skip-modules',
      'config',
    };
    if (valueOptions.contains(name)) return true;

    // Check allowed options
    for (final opt in allowedOptions) {
      if ((opt.name == name || opt.abbr == name) &&
          opt.type != OptionType.flag) {
        return true;
      }
    }

    // Check tool definition global options and command options
    if (toolDefinition != null) {
      for (final opt in toolDefinition!.globalOptions) {
        if ((opt.name == name || opt.abbr == name) &&
            opt.type != OptionType.flag) {
          return true;
        }
      }
      for (final cmd in toolDefinition!.commands) {
        for (final opt in cmd.options) {
          if ((opt.name == name || opt.abbr == name) &&
              opt.type != OptionType.flag) {
            return true;
          }
        }
      }
    }

    return false;
  }

  String _shortToLong(String short) {
    const mapping = {
      's': 'scan',
      'r': 'recursive',
      'R': 'root',
      'x': 'exclude',
      'p': 'project',
      'm': 'modules',
      'i': 'inner-first-git',
      'o': 'outer-first-git',
      'T': 'top-repo',
      'b': 'build-order',
      'v': 'verbose',
      'n': 'dry-run',
      'l': 'list',
      'f': 'force',
      'h': 'help',
      'V': 'version',
    };
    if (mapping.containsKey(short)) return mapping[short]!;

    // Check tool definition for abbreviation mapping
    if (toolDefinition != null) {
      for (final opt in toolDefinition!.globalOptions) {
        if (opt.abbr == short) return opt.name;
      }
      for (final cmd in toolDefinition!.commands) {
        for (final opt in cmd.options) {
          if (opt.abbr == short) return opt.name;
        }
      }
    }

    // Check allowed options
    for (final opt in allowedOptions) {
      if (opt.abbr == short) return opt.name;
    }

    return short;
  }

  List<String> _splitValue(String value) {
    // Split on comma for multi-value options
    return value
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Parse a command-line string (for REPL use).
  ///
  /// Handles shell-like quoting.
  static CliArgs parseCommandLine(
    String commandLine, {
    CommandDefinition? commandDefinition,
    ToolDefinition? toolDefinition,
  }) {
    final args = splitCommandLine(commandLine);
    final parser = CliArgParser(toolDefinition: toolDefinition);
    return parser.parse(args);
  }

  /// Split a command line string into arguments, respecting quotes.
  static List<String> splitCommandLine(String line) {
    final args = <String>[];
    final current = StringBuffer();
    var inSingleQuote = false;
    var inDoubleQuote = false;
    var escaped = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];

      if (escaped) {
        current.write(char);
        escaped = false;
        continue;
      }

      if (char == '\\') {
        escaped = true;
        continue;
      }

      if (char == "'" && !inDoubleQuote) {
        inSingleQuote = !inSingleQuote;
        continue;
      }

      if (char == '"' && !inSingleQuote) {
        inDoubleQuote = !inDoubleQuote;
        continue;
      }

      if (char == ' ' && !inSingleQuote && !inDoubleQuote) {
        if (current.isNotEmpty) {
          args.add(current.toString());
          current.clear();
        }
        continue;
      }

      current.write(char);
    }

    if (current.isNotEmpty) {
      args.add(current.toString());
    }

    return args;
  }
}

// Internal parse state
class _ParseState {
  String? scan;
  bool scanExplicitlySet = false;
  bool recursive = false;
  bool recursiveExplicitlySet = false;
  bool notRecursive = false;
  String? root;
  bool bareRoot = false;
  final List<String> excludePatterns = [];
  final List<String> excludeProjects = [];
  final List<String> recursionExclude = [];
  final List<String> projectPatterns = [];
  final List<String> modules = [];
  final List<String> skipModules = [];
  bool innerFirstGit = false;
  bool outerFirstGit = false;
  bool topRepo = false;
  bool buildOrder = true;
  bool workspaceRecursion = false;
  bool verbose = false;
  bool dryRun = false;
  bool listOnly = false;
  bool force = false;
  bool guide = false;
  bool dumpConfig = false;
  String? configPath;
  bool help = false;
  bool version = false;
  bool noSkip = false;
  bool includeTestProjects = false;
  bool testProjectsOnly = false;
  final List<String> positionalArgs = [];
  final List<String> commands = [];
  final Map<String, _PerCommandState> commandArgs = {};
  final Map<String, dynamic> extraOptions = {};
  String? currentCommand;

  CliArgs toCliArgs() {
    return CliArgs(
      scan: scan,
      scanExplicitlySet: scanExplicitlySet,
      recursive: recursive,
      recursiveExplicitlySet: recursiveExplicitlySet,
      notRecursive: notRecursive,
      root: root,
      bareRoot: bareRoot,
      excludePatterns: excludePatterns,
      excludeProjects: excludeProjects,
      recursionExclude: recursionExclude,
      projectPatterns: projectPatterns,
      modules: modules,
      skipModules: skipModules,
      innerFirstGit: innerFirstGit,
      outerFirstGit: outerFirstGit,
      topRepo: topRepo,
      buildOrder: buildOrder,
      workspaceRecursion: workspaceRecursion,
      verbose: verbose,
      dryRun: dryRun,
      listOnly: listOnly,
      force: force,
      guide: guide,
      dumpConfig: dumpConfig,
      configPath: configPath,
      help: help,
      version: version,
      noSkip: noSkip,
      includeTestProjects: includeTestProjects,
      testProjectsOnly: testProjectsOnly,
      positionalArgs: positionalArgs,
      commands: commands,
      commandArgs: Map.fromEntries(
        commandArgs.entries.map(
          (e) => MapEntry(e.key, e.value.toPerCommandArgs()),
        ),
      ),
      extraOptions: extraOptions,
    );
  }
}

class _PerCommandState {
  final List<String> projectPatterns = [];
  final List<String> excludePatterns = [];
  final Map<String, dynamic> options = {};

  PerCommandArgs toPerCommandArgs() {
    return PerCommandArgs(
      commandName: '', // Will be set by caller
      projectPatterns: projectPatterns,
      excludePatterns: excludePatterns,
      options: options,
    );
  }
}
