import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../folder/fs_folder.dart';
import '../folder/natures/buildkit_folder.dart';
import '../folder/natures/git_folder.dart';
import 'traversal_info.dart';
import 'repository_id_lookup.dart';

/// Applies filters to folder lists based on TraversalInfo configuration.
class FilterPipeline {
  /// Apply filters for project traversal mode.
  List<FsFolder> applyProjectFilters(
    List<FsFolder> folders,
    ProjectTraversalInfo info,
  ) {
    var result = folders;

    // 1. Path exclude (--exclude, -x) - matches against full path with substring matching
    if (info.excludePatterns.isNotEmpty) {
      result = result
          .where((f) => !_matchesPathPattern(f.path, info.excludePatterns))
          .toList();
    }

    // 2. Project include (--project, -p)
    // Resolution order: project ID → project name → folder name pattern (glob)
    //                    → relative path pattern (for patterns with '/')
    if (info.projectPatterns.isNotEmpty) {
      result = result
          .where(
            (f) =>
                _matchesProjectId(f, info.projectPatterns) ||
                _matchesProjectName(f, info.projectPatterns) ||
                _matchesNamePattern(f.name, info.projectPatterns) ||
                _matchesRelativePath(
                  p.relative(f.path, from: info.executionRoot),
                  info.projectPatterns,
                ),
          )
          .toList();
    }

    // 3. Project name exclude (--exclude-projects)
    // Resolution order: project ID → project name → folder name
    //                    → relative path pattern (for patterns with '/')
    if (info.excludeProjects.isNotEmpty) {
      result = result
          .where(
            (f) =>
                !_matchesProjectId(f, info.excludeProjects) &&
                !_matchesProjectName(f, info.excludeProjects) &&
                !_matchesNamePattern(f.name, info.excludeProjects) &&
                !_matchesRelativePath(
                  p.relative(f.path, from: info.executionRoot),
                  info.excludeProjects,
                ),
          )
          .toList();
    }

    // 4. Test project filter
    result = _applyTestFilter(result, info);

    return result;
  }

  /// Apply filters for git traversal mode.
  List<FsFolder> applyGitFilters(
    List<FsFolder> folders,
    GitTraversalInfo info,
  ) {
    var result = folders;

    // 1. Path exclude (--exclude, -x)
    if (info.excludePatterns.isNotEmpty) {
      result = result
          .where((f) => !_matchesPathPattern(f.path, info.excludePatterns))
          .toList();
    }

    // 2. Module filter (--modules, -m)
    if (info.modules.isNotEmpty) {
      result = _applyModulesFilter(result, info.modules);
    }

    // 3. Skip modules filter (--skip-modules)
    if (info.skipModules.isNotEmpty) {
      result = _applySkipModulesFilter(result, info.skipModules);
    }

    // 4. Test project filter
    result = _applyTestFilter(result, info);

    return result;
  }

  /// Apply test project filters based on traversal info.
  List<FsFolder> _applyTestFilter(
    List<FsFolder> folders,
    BaseTraversalInfo info,
  ) {
    if (info.testProjectsOnly) {
      // Only include zom_* test projects
      return folders.where((f) => f.name.startsWith('zom_')).toList();
    } else if (!info.includeTestProjects) {
      // Exclude zom_* by default
      return folders.where((f) => !f.name.startsWith('zom_')).toList();
    }
    return folders;
  }

  /// Check if path matches any of the patterns (for exclude filters).
  /// Uses substring matching - *flutter* matches any path containing 'flutter'.
  bool _matchesPathPattern(String path, List<String> patterns) {
    for (final pattern in patterns) {
      // Extract the core pattern by removing wildcards
      final barePattern = pattern.replaceAll('*', '');
      if (barePattern.isNotEmpty && path.contains(barePattern)) {
        return true;
      }
      // Also try glob match for full path patterns like **/node_modules/**
      try {
        final glob = Glob(pattern);
        if (glob.matches(path)) return true;
      } catch (_) {
        // Invalid glob pattern - already handled by substring match
      }
    }
    return false;
  }

  /// Check if a folder matches any project pattern by ID, name, or folder name glob.
  ///
  /// This is the unified matching method used for `--project` / `-p` filtering.
  /// Resolution order: project ID → project name → folder name (glob)
  ///                    → relative path pattern (for patterns with '/').
  ///
  /// When [executionRoot] is provided, patterns containing '/' are matched
  /// against the folder's path relative to the execution root.
  bool matchesProjectPattern(
    FsFolder folder,
    List<String> patterns, {
    String? executionRoot,
  }) {
    if (_matchesProjectId(folder, patterns) ||
        _matchesProjectName(folder, patterns) ||
        _matchesNamePattern(folder.name, patterns)) {
      return true;
    }
    // Try path-based matching for patterns containing '/'
    if (executionRoot != null) {
      final relativePath = p.relative(folder.path, from: executionRoot);
      if (_matchesRelativePath(relativePath, patterns)) return true;
    }
    return false;
  }

  /// Whether a pattern is path-based (contains directory separators).
  ///
  /// Path patterns like `core/*`, `devops/**`, `**/tom_core_*` must be
  /// matched against relative paths, not just the folder basename.
  static bool _isPathPattern(String pattern) => pattern.contains('/');

  /// Match a relative path against path-based patterns.
  ///
  /// Only considers patterns that contain '/' (directory separators).
  /// Uses [Glob] matching for pattern evaluation.
  bool _matchesRelativePath(String relativePath, List<String> patterns) {
    for (final pattern in patterns) {
      if (!_isPathPattern(pattern)) continue;
      try {
        final glob = Glob(pattern);
        if (glob.matches(relativePath)) return true;
      } catch (_) {
        // Invalid glob — try simple string prefix match as fallback
        final barePattern = pattern.replaceAll('*', '');
        if (barePattern.isNotEmpty && relativePath.startsWith(barePattern)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Check if name matches any of the patterns (for include/project filters).
  /// Uses glob pattern matching on folder name.
  bool _matchesNamePattern(String name, List<String> patterns) {
    for (final pattern in patterns) {
      try {
        // Convert simple wildcard to regex for name matching
        if (pattern.contains('*')) {
          final regexStr = pattern.replaceAll('.', r'\.').replaceAll('*', '.*');
          final regex = RegExp('^$regexStr\$', caseSensitive: false);
          if (regex.hasMatch(name)) return true;
        } else {
          // Exact match
          if (name == pattern) return true;
        }
      } catch (_) {
        // Try exact match as fallback
        if (name == pattern) return true;
      }
    }
    return false;
  }

  /// Check if folder has a matching project ID in buildkit.yaml.
  bool _matchesProjectId(FsFolder folder, List<String> patterns) {
    // First check TomBuildFolder for short-id
    for (final nature in folder.natures) {
      if (nature is TomBuildFolder && nature.shortId != null) {
        final id = nature.shortId!.toLowerCase();
        for (final pattern in patterns) {
          if (id == pattern.toLowerCase()) {
            return true;
          }
        }
      }
    }
    // Fallback: check BuildkitFolder for project-id
    for (final nature in folder.natures) {
      if (nature is BuildkitFolder && nature.projectId != null) {
        final id = nature.projectId!.toLowerCase();
        for (final pattern in patterns) {
          if (id == pattern.toLowerCase()) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Check if folder has a matching project name in tom_project.yaml or buildkit.yaml.
  bool _matchesProjectName(FsFolder folder, List<String> patterns) {
    for (final nature in folder.natures) {
      // Check TomBuildFolder (tom_project.yaml)
      if (nature is TomBuildFolder && nature.projectName != null) {
        final name = nature.projectName!.toLowerCase();
        for (final pattern in patterns) {
          if (name == pattern.toLowerCase()) {
            return true;
          }
        }
      }
      // Check BuildkitFolder (buildkit.yaml)
      if (nature is BuildkitFolder && nature.projectName != null) {
        final name = nature.projectName!.toLowerCase();
        for (final pattern in patterns) {
          if (name == pattern.toLowerCase()) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Filter to keep only folders within specified git submodules.
  ///
  /// Accepts repository IDs (e.g., "BSC", "D4"), repository names (e.g., "tom_module_basics"),
  /// or path substrings.
  List<FsFolder> _applyModulesFilter(
    List<FsFolder> folders,
    List<String> modules,
  ) {
    // Resolve IDs to names
    final resolvedModules = modules
        .map(RepositoryIdLookup.resolveToName)
        .toList();

    return folders.where((f) {
      // Check if this folder is within any of the specified modules
      for (final module in resolvedModules) {
        if (f.path.contains(module)) return true;
        // Also check natures for submodule name
        for (final nature in f.natures) {
          if (nature is GitFolder && nature.submoduleName != null) {
            final submoduleName = nature.submoduleName!.toLowerCase();
            if (resolvedModules.any(
              (m) =>
                  submoduleName.contains(m.toLowerCase()) ||
                  submoduleName == m.toLowerCase(),
            )) {
              return true;
            }
          }
        }
      }
      return false;
    }).toList();
  }

  /// Filter to exclude folders within specified git submodules.
  ///
  /// Accepts repository IDs (e.g., "BSC", "D4"), repository names (e.g., "tom_module_basics"),
  /// or path substrings.
  List<FsFolder> _applySkipModulesFilter(
    List<FsFolder> folders,
    List<String> skipModules,
  ) {
    // Resolve IDs to names
    final resolvedModules = skipModules
        .map(RepositoryIdLookup.resolveToName)
        .toList();

    return folders.where((f) {
      // Exclude if this folder is within any of the specified modules
      for (final module in resolvedModules) {
        if (f.path.contains(module)) return false;
        for (final nature in f.natures) {
          if (nature is GitFolder && nature.submoduleName != null) {
            final submoduleName = nature.submoduleName!.toLowerCase();
            if (resolvedModules.any(
              (m) =>
                  submoduleName.contains(m.toLowerCase()) ||
                  submoduleName == m.toLowerCase(),
            )) {
              return false;
            }
          }
        }
      }
      return true;
    }).toList();
  }
}

/// Sorts folders based on traversal configuration.
class FolderSorter {
  /// Sort folders by dependency order (for project traversal).
  ///
  /// Uses a pre-computed global build order to sort the filtered contexts.
  /// [globalOrder] contains all project paths in dependency-first order,
  /// computed from the full unfiltered scan.
  ///
  /// Folders present in [globalOrder] appear first (in dependency order),
  /// followed by folders not in the order (e.g., non-Dart projects).
  List<T> sortByBuildOrder<T>(
    List<T> folders,
    String Function(T) getPath,
    List<String> globalOrder,
  ) {
    if (globalOrder.isEmpty) return folders;

    // Build position map for O(1) lookup
    final positionMap = <String, int>{};
    for (var i = 0; i < globalOrder.length; i++) {
      positionMap[globalOrder[i]] = i;
    }

    final sorted = List<T>.from(folders);
    sorted.sort((a, b) {
      final posA = positionMap[getPath(a)];
      final posB = positionMap[getPath(b)];

      // Both in order → sort by position
      if (posA != null && posB != null) return posA.compareTo(posB);
      // Only one in order → it comes first
      if (posA != null) return -1;
      if (posB != null) return 1;
      // Neither in order → preserve relative order (stable sort)
      return 0;
    });

    return sorted;
  }

  /// Sort git repos by inner-first order.
  ///
  /// Deeper nested repos (submodules) come before outer repos.
  List<T> sortByInnerFirst<T>(List<T> folders, String Function(T) getPath) {
    final sorted = List<T>.from(folders);
    sorted.sort((a, b) {
      final depthA = getPath(a).split(p.separator).length;
      final depthB = getPath(b).split(p.separator).length;
      return depthB.compareTo(depthA); // Deeper first
    });
    return sorted;
  }

  /// Sort git repos by outer-first order.
  ///
  /// Parent repos come before nested repos (submodules).
  List<T> sortByOuterFirst<T>(List<T> folders, String Function(T) getPath) {
    final sorted = List<T>.from(folders);
    sorted.sort((a, b) {
      final depthA = getPath(a).split(p.separator).length;
      final depthB = getPath(b).split(p.separator).length;
      return depthA.compareTo(depthB); // Shallower first
    });
    return sorted;
  }
}
