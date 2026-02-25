/// Bridge between `package:args` ArgParser and v2 traversal system.
///
/// Provides [WorkspaceNavigationArgs] for tools that use the `args` package
/// `ArgParser` for global option parsing. This bridges the parsed results
/// into a structured form that the v2 traversal engine understands.
///
/// ## Usage
///
/// ```dart
/// final parser = ArgParser();
/// addNavigationOptions(parser);
/// final results = parser.parse(args);
/// final (processedArgs, bareRoot) = preprocessRootFlag(args);
/// final navArgs = parseNavigationArgs(results, bareRoot: bareRoot);
/// ```
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../v2/traversal/folder_scanner.dart' show GitRepoFinder;
import '../v2/workspace_utils.dart';

/// Represents the execution mode for a tool.
enum ExecutionMode {
  /// Default mode: operates on current directory with auto-applied defaults.
  project,

  /// Workspace mode: triggered by navigation options like `-R`, `-s <path>`,
  /// `-i`, `-o`.
  workspace,
}

/// Parsed navigation options for workspace traversal.
///
/// Used to configure project discovery behavior across all Tom build tools.
class WorkspaceNavigationArgs {
  /// Scan directory for projects.
  final String? scan;

  /// Scan directories recursively.
  final bool recursive;

  /// True if recursive flag was explicitly set by user
  /// (--recursive or --no-recursive).
  ///
  /// Used to determine if defaults should be applied or user's explicit
  /// choice honored.
  final bool recursiveExplicitlySet;

  /// Sort projects in dependency build order.
  final bool buildOrder;

  /// Specific project(s) to run on.
  final String? project;

  /// Workspace root path (from `-R <path>`).
  ///
  /// If [bareRoot] is true and this is null, use detected workspace root.
  final String? root;

  /// True if bare -R was used (without path argument).
  final bool bareRoot;

  /// Shell out to sub-workspaces instead of skipping.
  final bool workspaceRecursion;

  /// Scan git repos, process innermost (deepest) first.
  final bool innerFirstGit;

  /// Scan git repos, process outermost (shallowest) first.
  final bool outerFirstGit;

  /// Find topmost git repo by traversing up from current directory.
  ///
  /// When set, traverses up the directory tree to find the outermost
  /// git repository and uses that as the root for subsequent traversal.
  /// Can be combined with [innerFirstGit] or [outerFirstGit].
  final bool topRepo;

  /// Exclude patterns (path-based globs).
  final List<String> exclude;

  /// Exclude projects by name or path.
  final List<String> excludeProjects;

  /// Exclude patterns during recursive scan.
  final List<String> recursionExclude;

  /// Include only projects within specified git modules (comma-separated).
  ///
  /// Module names are git repository folder names
  /// (e.g., "tom_module_d4rt").
  /// Use "root" or "tom" to reference the main repository.
  final List<String> modules;

  /// Ignore skip markers (tom_skip.yaml, *_skip.yaml).
  ///
  /// When true, projects that contain skip files are processed anyway.
  /// Corresponds to the `--no-skip` CLI flag.
  final bool noSkip;

  /// Active modes for configuration processing.
  ///
  /// Modes are workspace-wide configuration dimensions
  /// (e.g., DEV, CI, PROD).
  /// They affect how MODE-prefixed keys in config files are processed.
  final List<String> modes;

  WorkspaceNavigationArgs({
    this.scan,
    this.recursive = false,
    this.recursiveExplicitlySet = false,
    this.buildOrder = false,
    this.project,
    this.root,
    this.bareRoot = false,
    this.workspaceRecursion = false,
    this.innerFirstGit = false,
    this.outerFirstGit = false,
    this.topRepo = false,
    this.exclude = const [],
    this.excludeProjects = const [],
    this.recursionExclude = const [],
    this.modules = const [],
    this.noSkip = false,
    this.modes = const [],
  });

  /// Determines the execution mode based on parsed arguments.
  ///
  /// Returns [ExecutionMode.workspace] if any workspace traversal option
  /// is used:
  /// - Bare `-R` or `-R <path>`
  /// - `-s <path>` where path is not "."
  /// - `-i` (inner-first-git)
  /// - `-o` (outer-first-git)
  /// - `-T` (top-repo)
  ExecutionMode get executionMode {
    if (bareRoot) return ExecutionMode.workspace;
    if (root != null) return ExecutionMode.workspace;
    if (scan != null && scan != '.') return ExecutionMode.workspace;
    if (innerFirstGit) return ExecutionMode.workspace;
    if (outerFirstGit) return ExecutionMode.workspace;
    if (topRepo) return ExecutionMode.workspace;
    return ExecutionMode.project;
  }

  /// Returns true if in workspace mode.
  bool get isWorkspaceMode => executionMode == ExecutionMode.workspace;

  /// Returns true if in project mode.
  bool get isProjectMode => executionMode == ExecutionMode.project;

  /// Apply default scanning behavior.
  ///
  /// Returns a new [WorkspaceNavigationArgs] with defaults applied:
  /// - `--scan .` (if no scan was specified)
  /// - `--recursive` (enabled unless explicitly disabled)
  /// - `--build-order` (enabled unless explicitly disabled)
  WorkspaceNavigationArgs withDefaults() {
    final needsScanDefault = scan == null && project == null;
    final effectiveRecursive = recursiveExplicitlySet
        ? recursive
        : (needsScanDefault || recursive);

    return WorkspaceNavigationArgs(
      scan: needsScanDefault ? '.' : scan,
      recursive: effectiveRecursive,
      recursiveExplicitlySet: recursiveExplicitlySet,
      buildOrder: needsScanDefault || buildOrder,
      project: project,
      root: root,
      bareRoot: bareRoot,
      workspaceRecursion: workspaceRecursion,
      innerFirstGit: innerFirstGit,
      outerFirstGit: outerFirstGit,
      topRepo: topRepo,
      exclude: exclude,
      excludeProjects: excludeProjects,
      recursionExclude: recursionExclude,
      modules: modules,
      noSkip: noSkip,
      modes: modes,
    );
  }

  /// Create a copy with modified values.
  WorkspaceNavigationArgs copyWith({
    String? scan,
    bool? recursive,
    bool? recursiveExplicitlySet,
    bool? buildOrder,
    String? project,
    String? root,
    bool? bareRoot,
    bool? workspaceRecursion,
    bool? innerFirstGit,
    bool? outerFirstGit,
    bool? topRepo,
    List<String>? exclude,
    List<String>? excludeProjects,
    List<String>? recursionExclude,
    List<String>? modules,
    bool? noSkip,
    List<String>? modes,
  }) {
    return WorkspaceNavigationArgs(
      scan: scan ?? this.scan,
      recursive: recursive ?? this.recursive,
      recursiveExplicitlySet:
          recursiveExplicitlySet ?? this.recursiveExplicitlySet,
      buildOrder: buildOrder ?? this.buildOrder,
      project: project ?? this.project,
      root: root ?? this.root,
      bareRoot: bareRoot ?? this.bareRoot,
      workspaceRecursion: workspaceRecursion ?? this.workspaceRecursion,
      innerFirstGit: innerFirstGit ?? this.innerFirstGit,
      outerFirstGit: outerFirstGit ?? this.outerFirstGit,
      topRepo: topRepo ?? this.topRepo,
      exclude: exclude ?? this.exclude,
      excludeProjects: excludeProjects ?? this.excludeProjects,
      recursionExclude: recursionExclude ?? this.recursionExclude,
      modules: modules ?? this.modules,
      noSkip: noSkip ?? this.noSkip,
      modes: modes ?? this.modes,
    );
  }

  @override
  String toString() =>
      'WorkspaceNavigationArgs(mode=${executionMode.name}, scan=$scan, '
      'recursive=$recursive${recursiveExplicitlySet ? '(explicit)' : ''}, '
      'buildOrder=$buildOrder, project=$project, '
      'root=$root, bareRoot=$bareRoot, '
      'workspaceRecursion=$workspaceRecursion, '
      'innerFirstGit=$innerFirstGit, outerFirstGit=$outerFirstGit, '
      'topRepo=$topRepo, noSkip=$noSkip)';

  /// Convert navigation args back to command-line arguments.
  ///
  /// This allows buildkit to pass navigation options to underlying commands
  /// without duplicating option definitions.
  List<String> toArgs({String? rootPath, Set<String> suppress = const {}}) {
    final args = <String>[];

    if (rootPath != null && !suppress.contains('R')) {
      args.addAll(['--root', rootPath]);
    }
    if (scan != null && !suppress.contains('s')) {
      args.addAll(['--scan', scan!]);
    }
    if (recursive && !suppress.contains('r')) {
      args.add('--recursive');
    }
    if (buildOrder && !suppress.contains('b')) {
      args.add('--build-order');
    }
    if (project != null && !suppress.contains('p')) {
      args.addAll(['--project', project!]);
    }
    if (innerFirstGit && !suppress.contains('i')) {
      args.add('--inner-first-git');
    }
    if (outerFirstGit && !suppress.contains('o')) {
      args.add('--outer-first-git');
    }
    if (topRepo && !suppress.contains('T')) {
      args.add('--top-repo');
    }
    if (workspaceRecursion && !suppress.contains('w')) {
      args.add('--workspace-recursion');
    }
    for (final x in exclude) {
      args.addAll(['--exclude', x]);
    }
    for (final x in excludeProjects) {
      args.addAll(['--exclude-projects', x]);
    }
    for (final x in recursionExclude) {
      args.addAll(['--recursion-exclude', x]);
    }
    if (noSkip) {
      args.add('--no-skip');
    }
    if (modules.isNotEmpty && !suppress.contains('m')) {
      args.addAll(['--modules', modules.join(',')]);
    }
    if (modes.isNotEmpty) {
      args.addAll(['--modes', modes.join(',')]);
    }
    return args;
  }
}

// ---------------------------------------------------------------------------
// ArgParser integration
// ---------------------------------------------------------------------------

/// Add standard navigation options to an [ArgParser].
///
/// Adds: `-s`, `-r`, `-b`, `-p`, `-R`, `-w`, `-i`, `-o`, `-T`, `-x`,
/// `--exclude-projects`, `--recursion-exclude`, `-m`, `--no-skip`, `--modes`.
void addNavigationOptions(ArgParser parser) {
  parser.addOption('scan', abbr: 's', help: 'Scan directory for projects');
  parser.addFlag(
    'recursive',
    abbr: 'r',
    negatable: true,
    defaultsTo: false,
    help: 'Scan directories recursively (use --no-recursive to disable)',
  );
  parser.addFlag(
    'build-order',
    abbr: 'b',
    negatable: true,
    defaultsTo: false,
    help:
        'Sort projects in dependency build order '
        '(use --no-build-order to disable)',
  );
  parser.addOption(
    'project',
    abbr: 'p',
    help: 'Project(s) to run (comma-separated, globs supported)',
  );
  parser.addOption(
    'root',
    abbr: 'R',
    help: 'Workspace root (bare: detected, path: specified workspace)',
  );
  parser.addFlag(
    'workspace-recursion',
    abbr: 'w',
    negatable: false,
    help: 'Shell out to sub-workspaces instead of skipping',
  );
  parser.addFlag(
    'inner-first-git',
    abbr: 'i',
    negatable: false,
    help: 'Scan git repos, process innermost (deepest) first',
  );
  parser.addFlag(
    'outer-first-git',
    abbr: 'o',
    negatable: false,
    help: 'Scan git repos, process outermost (shallowest) first',
  );
  parser.addFlag(
    'top-repo',
    abbr: 'T',
    negatable: false,
    help: 'Find topmost git repo by traversing up from current directory',
  );
  parser.addMultiOption(
    'exclude',
    abbr: 'x',
    help: 'Exclude patterns (path-based globs)',
  );
  parser.addMultiOption(
    'exclude-projects',
    help:
        'Exclude projects by name or path '
        '(e.g. zom_*, xternal/tom_module_basics/*)',
  );
  parser.addMultiOption(
    'recursion-exclude',
    help: 'Exclude patterns during recursive scan',
  );
  parser.addOption(
    'modules',
    abbr: 'm',
    help:
        'Include only projects within specified git modules '
        '(comma-separated, e.g. tom_module_d4rt,tom_module_basics)',
  );
  parser.addFlag(
    'no-skip',
    negatable: false,
    help: 'Ignore skip markers (tom_skip.yaml, *_skip.yaml)',
  );
  parser.addOption(
    'modes',
    help:
        'Active modes for config processing '
        '(comma-separated, e.g. DEV,CI). '
        'Overrides tom_workspace.yaml default.',
  );
}

/// Preprocess command-line arguments to handle special -R behavior.
///
/// The -R/--root flag can be used in two ways:
/// 1. Bare `-R` - Use detected workspace root
/// 2. `-R <path>` - Use specified path as workspace root
///
/// Returns a record with:
/// - `processedArgs`: The args with bare -R converted to marker
/// - `bareRoot`: Whether bare -R was detected
(List<String> processedArgs, bool bareRoot) preprocessRootFlag(
  List<String> args,
) {
  final processedArgs = <String>[];
  var bareRoot = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];

    if (arg == '-R' || arg == '--root') {
      final hasNextArg = i + 1 < args.length;
      final nextArg = hasNextArg ? args[i + 1] : null;

      if (!hasNextArg ||
          (nextArg != null &&
              (nextArg.startsWith('-') ||
                  nextArg.startsWith(':') ||
                  _isPipelineOrCommandName(nextArg)))) {
        bareRoot = true;
        processedArgs.add('--root=__BARE_ROOT__');
      } else {
        processedArgs.add(arg);
      }
    } else if (arg.startsWith('-R=') || arg.startsWith('--root=')) {
      processedArgs.add(arg);
    } else {
      processedArgs.add(arg);
    }
  }

  return (processedArgs, bareRoot);
}

/// Check if a string looks like a pipeline or command name rather than a path.
bool _isPipelineOrCommandName(String s) {
  if (s.startsWith(':')) return true;

  const commonPipelines = {
    'build',
    'clean',
    'release',
    'test',
    'deploy',
    'publish',
    'run',
    'help',
    'version',
    'defines',
    'define',
    'undefine',
  };
  if (commonPipelines.contains(s.toLowerCase())) return true;

  if (!s.contains('/') && !s.contains('.') && !s.contains(p.separator)) {
    return true;
  }

  return false;
}

/// Parse navigation options from [ArgResults].
///
/// Call this after parsing with an [ArgParser] that has had
/// [addNavigationOptions] called on it.
///
/// The [bareRoot] parameter should come from [preprocessRootFlag].
WorkspaceNavigationArgs parseNavigationArgs(
  ArgResults results, {
  bool bareRoot = false,
}) {
  String? root = results['root'] as String?;
  if (root == '__BARE_ROOT__') {
    root = null;
    bareRoot = true;
  }

  final recursiveExplicitlySet = results.wasParsed('recursive');

  return WorkspaceNavigationArgs(
    scan: results['scan'] as String?,
    recursive: results['recursive'] as bool? ?? false,
    recursiveExplicitlySet: recursiveExplicitlySet,
    buildOrder: results['build-order'] as bool? ?? false,
    project: results['project'] as String?,
    root: root,
    bareRoot: bareRoot,
    workspaceRecursion: results['workspace-recursion'] as bool? ?? false,
    innerFirstGit: results['inner-first-git'] as bool? ?? false,
    outerFirstGit: results['outer-first-git'] as bool? ?? false,
    topRepo: results['top-repo'] as bool? ?? false,
    exclude: results['exclude'] as List<String>? ?? [],
    excludeProjects: results['exclude-projects'] as List<String>? ?? [],
    recursionExclude: results['recursion-exclude'] as List<String>? ?? [],
    modules: _parseCommaSeparated(results['modules'] as String?),
    noSkip: results['no-skip'] as bool? ?? false,
    modes: _parseModesOption(results['modes'] as String?),
  );
}

/// Determine the execution root based on navigation args.
///
/// In workspace mode with bare `-R`, returns the detected workspace root.
/// In workspace mode with `-R <path>`, validates and returns that path.
/// With `-T/--top-repo`, finds topmost git repo (requires `-i` or `-o`).
/// In project mode, returns the current directory.
String resolveExecutionRoot(
  WorkspaceNavigationArgs navArgs, {
  required String currentDir,
}) {
  if (navArgs.topRepo) {
    if (!navArgs.innerFirstGit && !navArgs.outerFirstGit) {
      throw ArgumentError(
        '-T/--top-repo requires git traversal mode '
        '(-i/--inner-first-git or -o/--outer-first-git)',
      );
    }
    final finder = GitRepoFinder();
    final topRepo = finder.findTopRepo(currentDir);
    if (topRepo == null) {
      throw ArgumentError(
        'No git repository found in directory tree above: $currentDir',
      );
    }
    return topRepo;
  }

  if (navArgs.bareRoot) {
    return findWorkspaceRoot(currentDir);
  } else if (navArgs.root != null) {
    final specifiedPath = p.isAbsolute(navArgs.root!)
        ? navArgs.root!
        : p.join(currentDir, navArgs.root!);
    final resolved = p.normalize(p.absolute(specifiedPath));

    if (!Directory(resolved).existsSync()) {
      throw ArgumentError(
        'Specified workspace does not exist: ${navArgs.root}',
      );
    }
    if (!isWorkspaceBoundary(resolved)) {
      throw ArgumentError(
        'Specified path is not a workspace '
        '(no $kBuildkitMasterYaml): ${navArgs.root}',
      );
    }
    return resolved;
  }

  return currentDir;
}

// ---------------------------------------------------------------------------
// CLI command helpers
// ---------------------------------------------------------------------------

/// Check if the first argument is a help command.
bool isHelpCommand(List<String> args) {
  if (args.isEmpty) return false;
  final first = args.first.toLowerCase();
  return first == 'help' ||
      first == '-help' ||
      first == '-h' ||
      first == '--help';
}

/// Check if the first argument is a version command.
bool isVersionCommand(List<String> args) {
  if (args.isEmpty) return false;
  final first = args.first.toLowerCase();
  return first == 'version' ||
      first == '-version' ||
      first == '-v' ||
      first == '--version';
}

// ---------------------------------------------------------------------------
// Help text generators
// ---------------------------------------------------------------------------

/// Returns execution modes explanation lines.
List<String> getExecutionModesHelpLines() {
  return [
    'Execution Modes:',
    '  Project Mode (default):   '
        'Runs from current directory with -s . -r -b defaults',
    '  Workspace Mode:           '
        'Runs from workspace root (triggered by -R, -s <path>, -i, -o)',
    '',
    '  -R alone triggers workspace mode from detected workspace root.',
    '  -R <path> runs in specified workspace '
        '(must have buildkit_master.yaml).',
    '  Sub-workspaces (containing buildkit_master.yaml) '
        'are skipped by default.',
    '  Use -w to shell out and process sub-workspaces recursively.',
  ];
}

/// Prints execution modes explanation to stdout.
void printExecutionModesHelp() {
  for (final line in getExecutionModesHelpLines()) {
    print(line);
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Parse comma-separated modes option into a list (uppercased).
List<String> _parseModesOption(String? value) {
  if (value == null || value.isEmpty) return const [];
  return value
      .split(',')
      .map((s) => s.trim().toUpperCase())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Parse comma-separated option into a list.
List<String> _parseCommaSeparated(String? value) {
  if (value == null || value.isEmpty) return const [];
  return value
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}
