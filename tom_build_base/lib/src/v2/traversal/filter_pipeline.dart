import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../folder/fs_folder.dart';
import '../folder/natures/buildkit_folder.dart';
import '../folder/natures/dart_project_folder.dart';
import '../folder/natures/git_folder.dart';
import 'project_groups.dart';
import 'repository_id_lookup.dart';
import 'traversal_info.dart';

/// Applies filters to folder lists based on TraversalInfo configuration.
class FilterPipeline {
  /// [pathContext] computes relative paths; the platform's by default. Tests
  /// pass `p.windows` to run the matchers on Windows paths on any host.
  FilterPipeline({p.Context? pathContext}) : _path = pathContext ?? p.context;

  final p.Context _path;

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
            (f) => matchesProjectPattern(
              f,
              info.projectPatterns,
              executionRoot: info.executionRoot,
            ),
          )
          .toList();
    }

    // 2b. Group include (--group): projects in one of the named groups.
    if (info.groups.isNotEmpty) {
      final wanted = info.groups.toSet();
      result = result
          .where(
            (f) => projectGroupsOf(
              f.path,
              info.executionRoot,
            ).any(wanted.contains),
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
                  _path.relative(f.path, from: info.executionRoot),
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
  ///
  /// Path and pattern are compared with `/` separators: a pattern is written
  /// with `/` (`xternal/**`), and on Windows the folder path has `\`, so
  /// without it no `navigation: exclude` matched there (build_completion29).
  bool _matchesPathPattern(String path, List<String> patterns) {
    final normalizedPath = _normalizeSeparators(path);
    for (final rawPattern in patterns) {
      final pattern = _normalizeSeparators(rawPattern);
      // Extract the core pattern by removing wildcards
      final barePattern = pattern.replaceAll('*', '');
      if (barePattern.isNotEmpty && normalizedPath.contains(barePattern)) {
        return true;
      }
      // Also try glob match for full path patterns like **/node_modules/**
      try {
        final glob = Glob(pattern, context: p.posix);
        if (glob.matches(normalizedPath)) return true;
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
      final relativePath = _path.relative(folder.path, from: executionRoot);
      if (_matchesRelativePath(relativePath, patterns)) return true;
    }
    return false;
  }

  /// The subset of [patterns] that matches none of [folders].
  ///
  /// A `--project` pattern may be an id, a name, a folder-name glob, or a path,
  /// and only the last of those names a directory that can be existence-checked
  /// up front. For every other form — and for glob paths, which are exempt from
  /// the existence check because they *may* legitimately match zero — the only
  /// way to tell a real selector from a typo is to try it against the projects
  /// that were actually scanned. A pattern that matches nothing selected
  /// nothing, and a selection of nothing is a mistake worth reporting rather
  /// than a no-op worth performing.
  ///
  /// [folders] must be the **scanned** folders with their natures already
  /// detected, before the exclude filters run: matching is by id and name as
  /// well as by path, and "select A then exclude A" is a coherent request in
  /// which A is not mistyped. Order follows [patterns], and each pattern
  /// appears at most once.
  List<String> unmatchedProjectPatterns(
    List<FsFolder> folders,
    List<String> patterns, {
    required String executionRoot,
  }) {
    final unmatched = <String>[];
    for (final pattern in patterns) {
      if (unmatched.contains(pattern)) continue;
      final matched = folders.any(
        (f) =>
            matchesProjectPattern(f, [pattern], executionRoot: executionRoot),
      );
      if (!matched) unmatched.add(pattern);
    }
    return unmatched;
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
  /// and a POSIX-style path both resolve to the same folder. When an absolute
  /// pattern does not match literally, both are compared again with symbolic
  /// links resolved: a tool scans from its cwd, which is the resolved path,
  /// while the caller passes the path it was given (on macOS `/var/...` for
  /// `/private/var/...`).
  bool _matchesFullPath(String folderPath, List<String> patterns) {
    final normalizedFolder = _normalizeSeparators(folderPath);
    String? canonicalFolder;
    for (final pattern in patterns) {
      if (!_isPathPattern(pattern)) continue;
      if (_pathEquals(normalizedFolder, _normalizeSeparators(pattern))) {
        return true;
      }
      if (!_path.isAbsolute(pattern)) continue;
      canonicalFolder ??= _normalizeSeparators(_resolveLinks(folderPath));
      if (_pathEquals(
        canonicalFolder,
        _normalizeSeparators(_resolveLinks(pattern)),
      )) {
        return true;
      }
    }
    return false;
  }

  /// [path] with symbolic links resolved, or [path] itself when it does not
  /// exist or cannot be resolved.
  static String _resolveLinks(String path) {
    try {
      return Directory(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      return path;
    }
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
        // POSIX context: both sides use `/`, whatever the host's style.
        final glob = Glob(normalizedPattern, context: p.posix);
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

  /// Check if folder has a matching `project_id` in buildkit.yaml.
  bool _matchesProjectId(FsFolder folder, List<String> patterns) {
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

  /// Check if folder has a matching project name in pubspec.yaml or
  /// buildkit.yaml.
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

  /// `--modules`: keep the folders in one of the [modules] repositories.
  List<FsFolder> _applyModulesFilter(
    List<FsFolder> folders,
    List<String> modules, {
    required String executionRoot,
  }) {
    final selectors = _ModuleSelector.all(modules, executionRoot, _path);
    return folders.where((f) => selectors.any((s) => s.matches(f))).toList();
  }

  /// `--skip-modules`: drop the folders in one of the [skipModules]
  /// repositories.
  List<FsFolder> _applySkipModulesFilter(
    List<FsFolder> folders,
    List<String> skipModules, {
    required String executionRoot,
  }) {
    final selectors = _ModuleSelector.all(skipModules, executionRoot, _path);
    return folders.where((f) => !selectors.any((s) => s.matches(f))).toList();
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

/// One value of `--modules` / `--skip-modules` and the folders it selects.
///
/// Repositories are selected by path, so independent clones (a `.git`
/// directory) are selected like submodule checkouts:
/// - a repository ID or configured `name:` from `tom_repository.yaml`
///   (case-insensitive) selects the folder holding that file and everything
///   below it;
/// - a name or path (an ID's configured `name:` included) selects a folder
///   whose path holds it as whole segments, case-insensitive: `basics`
///   selects `tom_ai/basics/...`, `xternal/tom_dcli` that run of segments,
///   and `tom_basics` does not select `tom_basics_console`;
/// - a submodule checkout's [GitFolder.submoduleName] is compared the same
///   way, as an extra match while submodules exist.
class _ModuleSelector {
  _ModuleSelector(String value, String executionRoot, this._path)
    : _folder = RepositoryIdLookup.resolveToFolder(
        value,
        executionRoot: executionRoot,
      ),
      _segments = _segmentsOf(
        RepositoryIdLookup.resolveToName(value, executionRoot: executionRoot),
      );

  static List<_ModuleSelector> all(
    List<String> values,
    String executionRoot,
    p.Context path,
  ) => [for (final v in values) _ModuleSelector(v, executionRoot, path)];

  final p.Context _path;

  /// The repository folder of an ID or configured name, else null.
  final String? _folder;

  /// The name or path, as lower-case segments.
  final List<String> _segments;

  bool matches(FsFolder folder) {
    final folderPath = _path.normalize(_path.absolute(folder.path));
    final repository = _folder;
    if (repository != null &&
        (folderPath == repository || _path.isWithin(repository, folderPath))) {
      return true;
    }
    if (_holdsSegments(_segmentsOf(folderPath))) return true;
    for (final nature in folder.natures) {
      final submoduleName = nature is GitFolder ? nature.submoduleName : null;
      if (submoduleName != null && _holdsSegments(_segmentsOf(submoduleName))) {
        return true;
      }
    }
    return false;
  }

  /// Whether [segments] hold [_segments] as a contiguous run.
  bool _holdsSegments(List<String> segments) {
    if (_segments.isEmpty) return false;
    for (var start = 0; start + _segments.length <= segments.length; start++) {
      var all = true;
      for (var i = 0; i < _segments.length && all; i++) {
        all = segments[start + i] == _segments[i];
      }
      if (all) return true;
    }
    return false;
  }

  static List<String> _segmentsOf(String path) => path
      .replaceAll('\\', '/')
      .split('/')
      .where((s) => s.isNotEmpty && s != '.')
      .map((s) => s.toLowerCase())
      .toList();
}
