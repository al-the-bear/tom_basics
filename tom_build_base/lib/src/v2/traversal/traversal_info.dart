/// Git traversal order mode.
enum GitTraversalMode {
  /// Process inner git repos first (submodules before parent).
  innerFirst,

  /// Process outer git repos first (parent before submodules).
  outerFirst,
}

/// Base class for traversal configuration.
///
/// Contains options common to both project and git traversal modes.
abstract class BaseTraversalInfo {
  /// Workspace root path (execution root).
  final String executionRoot;

  /// Path patterns to exclude (glob patterns).
  final List<String> excludePatterns;

  /// Include zom_* test projects in results.
  final bool includeTestProjects;

  /// ONLY process zom_* test projects.
  final bool testProjectsOnly;

  const BaseTraversalInfo({
    required this.executionRoot,
    this.excludePatterns = const [],
    this.includeTestProjects = false,
    this.testProjectsOnly = false,
  });

  /// Create a copy with modified fields.
  BaseTraversalInfo copyWith({
    String? executionRoot,
    List<String>? excludePatterns,
    bool? includeTestProjects,
    bool? testProjectsOnly,
  });
}

/// Configuration for project-based traversal.
///
/// Used when traversing by project markers (pubspec.yaml, buildkit.yaml, etc.).
class ProjectTraversalInfo extends BaseTraversalInfo {
  /// Starting path for scan (default: '.').
  final String scan;

  /// Recurse into subdirectories.
  final bool recursive;

  /// Patterns to skip during recursive descent (e.g., 'node_modules').
  final List<String> recursionExclude;

  /// Project names/IDs to include (glob patterns, empty = all).
  final List<String> projectPatterns;

  /// Project names to exclude.
  final List<String> excludeProjects;

  /// Sort by dependency order (based on pubspec.yaml dependencies).
  final bool buildOrder;

  /// When true, ignore workspace boundaries and *_skip.yaml markers.
  /// Activated by `--no-skip`.
  final bool ignoreSkipMarkers;

  const ProjectTraversalInfo({
    required super.executionRoot,
    super.excludePatterns,
    super.includeTestProjects,
    super.testProjectsOnly,
    this.scan = '.',
    this.recursive = false,
    this.recursionExclude = const [],
    this.projectPatterns = const [],
    this.excludeProjects = const [],
    this.buildOrder = true,
    this.ignoreSkipMarkers = false,
  });

  @override
  ProjectTraversalInfo copyWith({
    String? executionRoot,
    List<String>? excludePatterns,
    bool? includeTestProjects,
    bool? testProjectsOnly,
    String? scan,
    bool? recursive,
    List<String>? recursionExclude,
    List<String>? projectPatterns,
    List<String>? excludeProjects,
    bool? buildOrder,
    bool? ignoreSkipMarkers,
  }) {
    return ProjectTraversalInfo(
      executionRoot: executionRoot ?? this.executionRoot,
      excludePatterns: excludePatterns ?? this.excludePatterns,
      includeTestProjects: includeTestProjects ?? this.includeTestProjects,
      testProjectsOnly: testProjectsOnly ?? this.testProjectsOnly,
      scan: scan ?? this.scan,
      recursive: recursive ?? this.recursive,
      recursionExclude: recursionExclude ?? this.recursionExclude,
      projectPatterns: projectPatterns ?? this.projectPatterns,
      excludeProjects: excludeProjects ?? this.excludeProjects,
      buildOrder: buildOrder ?? this.buildOrder,
      ignoreSkipMarkers: ignoreSkipMarkers ?? this.ignoreSkipMarkers,
    );
  }

  @override
  String toString() =>
      'ProjectTraversalInfo(scan: $scan, recursive: $recursive)';
}

/// Configuration for git repository traversal.
///
/// Used when traversing git repositories (finds all .git/ folders).
class GitTraversalInfo extends BaseTraversalInfo {
  /// Git submodules to include (by name, empty = all).
  final List<String> modules;

  /// Git submodules to exclude (by name).
  final List<String> skipModules;

  /// Traversal order (innerFirst or outerFirst).
  final GitTraversalMode gitMode;

  const GitTraversalInfo({
    required super.executionRoot,
    super.excludePatterns,
    super.includeTestProjects,
    super.testProjectsOnly,
    this.modules = const [],
    this.skipModules = const [],
    required this.gitMode,
  });

  @override
  GitTraversalInfo copyWith({
    String? executionRoot,
    List<String>? excludePatterns,
    bool? includeTestProjects,
    bool? testProjectsOnly,
    List<String>? modules,
    List<String>? skipModules,
    GitTraversalMode? gitMode,
  }) {
    return GitTraversalInfo(
      executionRoot: executionRoot ?? this.executionRoot,
      excludePatterns: excludePatterns ?? this.excludePatterns,
      includeTestProjects: includeTestProjects ?? this.includeTestProjects,
      testProjectsOnly: testProjectsOnly ?? this.testProjectsOnly,
      modules: modules ?? this.modules,
      skipModules: skipModules ?? this.skipModules,
      gitMode: gitMode ?? this.gitMode,
    );
  }

  @override
  String toString() => 'GitTraversalInfo(mode: $gitMode)';
}
