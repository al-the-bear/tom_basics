import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../folder/fs_folder.dart';
import '../folder/natures/buildkit_folder.dart';
import '../folder/natures/dart_project_folder.dart';
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
                _matchesFullPath(f.path, info.projectPatterns) ||
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
                !_matchesFullPath(f.path, info.excludeProjects) &&
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
      result = _applyModulesFilter(
        result,
        info.modules,
        executionRoot: info.executionRoot,
      );
    }

    // 3. Skip modules filter (--skip-modules)
    if (info.skipModules.isNotEmpty) {
      result = _applySkipModulesFilter(
        result,
        info.skipModules,
        executionRoot: info.executionRoot,
      );
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
    // Absolute path patterns (e.g. `versioner --project <abs path>`): compare
    // the folder's own path, separator-agnostically.
    if (_matchesFullPath(folder.path, patterns)) return true;
    // Try path-based matching for relative patterns containing a separator.
    if (executionRoot != null) {
      final relativePath = p.relative(folder.path, from: executionRoot);
      if (_matchesRelativePath(relativePath, patterns)) return true;
    }
    return false;
  }

  /// Whether a pattern is path-based (contains directory separators).
  ///
  /// Path patterns like `core/*`, `devops/**`, `**/tom_core_*` must be
  /// matched against relative paths, not just the folder basename. Both POSIX
  /// (`/`) and Windows (`\`) separators are recognised so that absolute paths
  /// passed on Windows (e.g. `C:\repo\_build`) are still treated as paths.
  static bool _isPathPattern(String pattern) =>
      pattern.contains('/') || pattern.contains(r'\');

  /// Normalise a path to use forward slashes and drop a trailing separator,
  /// so comparisons are independent of the platform's separator style.
  static String _normalizeSeparators(String path) {
    var result = path.replaceAll(r'\', '/');
    if (result.length > 1 && result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /// Platform-aware path equality (case-insensitive on Windows).
  static bool _pathEquals(String a, String b) =>
      Platform.isWindows ? a.toLowerCase() == b.toLowerCase() : a == b;

  /// Match a folder's full path against any pattern interpreted as a complete
  /// filesystem path (typically an absolute `--project` argument).
  ///
  /// The comparison is separator-agnostic: both the pattern and the folder
  /// path are normalised to forward slashes first, so a Windows backslash path
  /// and a POSIX-style path both resolve to the same folder.
  bool _matchesFullPath(String folderPath, List<String> patterns) {
    final normalizedFolder = _normalizeSeparators(folderPath);
    for (final pattern in patterns) {
      if (!_isPathPattern(pattern)) continue;
      if (_pathEquals(normalizedFolder, _normalizeSeparators(pattern))) {
        return true;
      }
    }
    return false;
  }

  /// Match a relative path against path-based patterns.
  ///
  /// Only considers patterns that contain a directory separator. Both the path
  /// and the pattern are normalised to forward slashes before [Glob] matching,
  /// so Windows backslash separators behave the same as POSIX ones.
  bool _matchesRelativePath(String relativePath, List<String> patterns) {
    final normalizedPath = _normalizeSeparators(relativePath);
    for (final pattern in patterns) {
      if (!_isPathPattern(pattern)) continue;
      final normalizedPattern = _normalizeSeparators(pattern);
      try {
        final glob = Glob(normalizedPattern);
        if (glob.matches(normalizedPath)) return true;
      } catch (_) {
        // Invalid glob — try simple string prefix match as fallback
        final barePattern = normalizedPattern.replaceAll('*', '');
        if (barePattern.isNotEmpty && normalizedPath.startsWith(barePattern)) {
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
      // Check DartProjectFolder (pubspec.yaml name)
      if (nature is DartProjectFolder && nature.projectName.isNotEmpty) {
        final name = nature.projectName.toLowerCase();
        for (final pattern in patterns) {
          if (name == pattern.toLowerCase()) {
            return true;
          }
        }
      }
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
    {required String executionRoot}
  ) {
    // Resolve IDs to names
    final resolvedModules = modules
        .map((x) => RepositoryIdLookup.resolveToName(
              x,
              executionRoot: executionRoot,
            ))
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
    {required String executionRoot}
  ) {
    // Resolve IDs to names
    final resolvedModules = skipModules
        .map((x) => RepositoryIdLookup.resolveToName(
              x,
              executionRoot: executionRoot,
            ))
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
      final depthA = _pathDepth(getPath(a));
      final depthB = _pathDepth(getPath(b));
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
      final depthA = _pathDepth(getPath(a));
      final depthB = _pathDepth(getPath(b));
      return depthA.compareTo(depthB); // Shallower first
    });
    return sorted;
  }

  /// Counts the nesting depth of a path, independent of the host platform's
  /// path separator.
  ///
  /// Why: ordering must be correct for both POSIX (`/a/b`) and Windows
  /// (`C:\a\b`) style paths regardless of where the tool runs. Splitting on
  /// only [p.separator] would yield depth 1 for foreign-separator paths on
  /// Windows, collapsing the ordering. Empty segments (leading separators,
  /// doubled separators) are ignored so equivalent paths compare equally.
  static int _pathDepth(String path) =>
      path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).length;
}
