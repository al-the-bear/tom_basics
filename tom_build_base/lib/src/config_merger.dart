/// Configuration merge utilities for Tom build tools.
///
/// Provides three merge strategies for combining workspace-level and
/// project-level configuration:
///
/// - **Section lists** (Category 1): Project replaces workspace if non-empty.
///   These are "what to do" definitions (e.g., compile targets, cleanup globs).
///
/// - **Additive lists** (Category 2): Union of workspace + project.
///   Guard/filter lists where both levels contribute (e.g., excludes).
///
/// - **Scalar values** (Category 3): Project overrides workspace if explicitly set.
///   Standard cascading defaults (e.g., output paths, flags).
library;

/// Utility for merging workspace and project configuration values.
///
/// Three merge categories:
///
/// | Category | Behavior | Example Fields |
/// |----------|----------|----------------|
/// | Section lists | Project replaces workspace | compiles, cleanup globs, modules |
/// | Additive lists | Union of both | excludes, protected-folders |
/// | Scalar values | Project overrides if set | output, variablePrefix |
class ConfigMerger {
  /// Merge section lists: project replaces workspace if non-empty.
  ///
  /// Used for "what to do" definitions where the project has a complete
  /// replacement for the workspace default.
  ///
  /// Examples:
  /// - `compiler.compiles` — project defines its own compile targets
  /// - `cleanup` — project defines its own cleanup globs
  /// - `d4rtgen.modules` — project defines its own bridge modules
  /// - `astgen.convert` — project defines its own conversion entries
  static List<T> mergeSections<T>(
    List<T> workspace,
    List<T> project,
  ) {
    return project.isNotEmpty ? project : workspace;
  }

  /// Merge additive lists: union of workspace + project (deduplicated).
  ///
  /// Used for guard/filter lists where both levels should contribute.
  ///
  /// Examples:
  /// - `cleanup.excludes` — both workspace and project excludes apply
  /// - `cleanup.protected-folders` — both levels protect folders
  /// - `navigation.exclude` — both levels exclude patterns
  /// - `navigation.recursion-exclude` — both levels exclude from recursion
  /// - `runner.include-builders` — both levels include builders
  static List<T> mergeAdditive<T>(
    List<T> workspace,
    List<T> project,
  ) {
    if (workspace.isEmpty) return project;
    if (project.isEmpty) return workspace;

    // Union with deduplication (preserves order, project items after workspace)
    final result = List<T>.of(workspace);
    for (final item in project) {
      if (!result.contains(item)) {
        result.add(item);
      }
    }
    return result;
  }

  /// Merge scalar values: project overrides workspace if explicitly set.
  ///
  /// The [isExplicit] callback determines whether the project value was
  /// explicitly set (vs using a default). If not provided, any non-null
  /// project value overrides the workspace value.
  ///
  /// Examples:
  /// - `versioner.output` — project can override output path
  /// - `versioner.variablePrefix` — project overrides prefix
  /// - `runner.delete-conflicting` — project overrides flag
  /// - `navigation.recursive` — project overrides via scan-subfolders
  static T mergeScalar<T>(
    T workspace,
    T project, {
    bool Function(T value)? isExplicit,
  }) {
    if (isExplicit != null) {
      return isExplicit(project) ? project : workspace;
    }
    // Default: project overrides if non-null
    return project ?? workspace;
  }

  /// Merge scalar with null check: project overrides if non-null.
  ///
  /// Convenience for nullable types where null means "not set".
  static T? mergeNullable<T>(T? workspace, T? project) {
    return project ?? workspace;
  }

  /// Merge maps: project entries override workspace entries.
  ///
  /// Used for key-value configuration where project can override
  /// specific keys while inheriting others from workspace.
  static Map<K, V> mergeMaps<K, V>(
    Map<K, V> workspace,
    Map<K, V> project,
  ) {
    if (workspace.isEmpty) return project;
    if (project.isEmpty) return workspace;
    return {...workspace, ...project};
  }
}
