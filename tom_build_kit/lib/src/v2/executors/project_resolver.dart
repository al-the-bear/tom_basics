/// Resolves project patterns for the findproject command.
///
/// Extracted from the v1 ProjectDiscovery class. Provides glob-based
/// and name/ID-based project resolution for the findproject executor.
library;

import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart' show TomBuildConfig;
import 'package:tom_build_base/tom_build_base_v2.dart' show findWorkspaceRoot;

import '../../project_scanner.dart' show scanForDartProjects;
import 'package:yaml/yaml.dart';

/// Resolves project patterns (names, paths, and globs) to absolute paths.
class ProjectResolver {
  /// Whether to print verbose output.
  final bool verbose;

  /// Output function for verbose messages.
  final void Function(String) log;

  ProjectResolver({this.verbose = false, void Function(String)? log})
    : log = log ?? ((msg) => stderr.writeln(msg));

  void _log(String message) {
    if (verbose) log(message);
  }

  /// Resolve project patterns to a list of project paths.
  ///
  /// [patterns] - Comma-separated list of project patterns. Supports:
  ///   - Single path: `my_project`
  ///   - Multiple paths: `project1,project2,project3`
  ///   - Glob patterns: `tom_*_builder`, `xternal/tom_module_*/*`
  ///   - Dot prefix for current directory: `./*` (direct children), `./**/*` (recursive)
  /// [basePath] - Base path for relative patterns
  /// [projectFilter] - Optional filter function to validate projects
  ///
  /// Returns a list of absolute project paths.
  Future<List<String>> resolveProjectPatterns(
    String patterns, {
    required String basePath,
    bool Function(String)? projectFilter,
  }) async {
    final results = <String>[];
    final seen = <String>{};

    // Split by comma (but not inside braces for glob patterns like {a,b})
    final patternList = _splitPatterns(patterns);

    for (final pattern in patternList) {
      final trimmed = pattern.trim();
      if (trimmed.isEmpty) continue;

      final resolved = await _resolvePattern(trimmed, basePath, projectFilter);
      for (final path in resolved) {
        if (!seen.contains(path)) {
          seen.add(path);
          results.add(path);
        }
      }
    }

    return results;
  }

  /// Split patterns by comma, respecting brace groups.
  List<String> _splitPatterns(String patterns) {
    final result = <String>[];
    var current = StringBuffer();
    var braceDepth = 0;

    for (var i = 0; i < patterns.length; i++) {
      final char = patterns[i];
      if (char == '{') {
        braceDepth++;
        current.write(char);
      } else if (char == '}') {
        braceDepth--;
        current.write(char);
      } else if (char == ',' && braceDepth == 0) {
        result.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }

    if (current.isNotEmpty) {
      result.add(current.toString());
    }

    return result;
  }

  Future<List<String>> _resolvePattern(
    String pattern,
    String basePath,
    bool Function(String)? projectFilter,
  ) async {
    // Handle dot prefix: ./* means current directory children
    var resolvedPattern = pattern;
    if (pattern.startsWith('./')) {
      resolvedPattern = pattern.substring(2);
    } else if (pattern == '.') {
      // Single dot means current directory
      if (_isProject(basePath) &&
          (projectFilter == null || projectFilter(basePath))) {
        return [basePath];
      }
      return [];
    }

    // Check if pattern contains glob characters
    if (_isGlobPattern(resolvedPattern)) {
      return _resolveGlobPattern(resolvedPattern, basePath, projectFilter);
    }

    // Simple path - check if it's a valid project
    final fullPath = p.normalize(
      p.isAbsolute(resolvedPattern)
          ? resolvedPattern
          : p.join(basePath, resolvedPattern),
    );

    if (_isProject(fullPath) &&
        (projectFilter == null || projectFilter(fullPath))) {
      return [fullPath];
    }

    // If pattern is a simple name (no path separators), search the workspace
    if (!resolvedPattern.contains('/') &&
        !resolvedPattern.contains(p.separator)) {
      final workspaceRoot = findWorkspaceRoot(basePath);
      _log('Searching workspace for project: $resolvedPattern');

      // Search workspace recursively for a project with matching name
      final found = await _findProjectByName(
        workspaceRoot,
        resolvedPattern,
        projectFilter,
      );
      if (found != null) {
        _log('Found project at: $found');
        return [found];
      }
    }

    _log('Warning: Not a valid project: $pattern');
    return [];
  }

  /// Search for a project by name, project ID, or project name.
  ///
  /// Resolution order (first match wins):
  /// 1. Folder basename exact match
  /// 2. Project ID match (from tom_project.yaml or buildkit.yaml)
  /// 3. Project name match (from tom_project.yaml or buildkit.yaml)
  Future<String?> _findProjectByName(
    String rootDir,
    String projectName,
    bool Function(String)? projectFilter,
  ) async {
    if (!Directory(rootDir).existsSync()) return null;

    final lowerSearch = projectName.toLowerCase();
    String? idMatch;
    String? nameMatch;

    // Use workspace-aware scanner instead of raw listSync
    final projectPaths = scanForDartProjects(
      rootDir,
      recursive: true,
      verbose: verbose,
    );

    for (final dirPath in projectPaths) {
      if (projectFilter != null && !projectFilter(dirPath)) continue;

      final dirName = p.basename(dirPath);

      // 1. Folder basename exact match (highest priority)
      if (dirName == projectName) {
        return p.normalize(p.absolute(dirPath));
      }

      // 2 & 3. Check project ID and name from YAML config files
      if (idMatch == null || nameMatch == null) {
        final match = _matchProjectConfig(dirPath, lowerSearch);
        if (match == _ConfigMatch.id && idMatch == null) {
          idMatch = p.normalize(p.absolute(dirPath));
        } else if (match == _ConfigMatch.name && nameMatch == null) {
          nameMatch = p.normalize(p.absolute(dirPath));
        }
      }
    }

    // Return first match by priority: folder name → ID → name
    return idMatch ?? nameMatch;
  }

  /// Check if a directory's project config files match the search term.
  _ConfigMatch? _matchProjectConfig(String dirPath, String lowerSearch) {
    // Check tom_project.yaml
    final tomProjectFile = File(p.join(dirPath, 'tom_project.yaml'));
    if (tomProjectFile.existsSync()) {
      try {
        final content = tomProjectFile.readAsStringSync();
        final yaml = loadYaml(content);
        if (yaml is Map) {
          // Check project_id and short-id
          final projectId =
              yaml['project_id'] as String? ?? yaml['short-id'] as String?;
          if (projectId != null && projectId.toLowerCase() == lowerSearch) {
            return _ConfigMatch.id;
          }
          // Check name
          final name = yaml['name'] as String?;
          if (name != null && name.toLowerCase() == lowerSearch) {
            return _ConfigMatch.name;
          }
        }
      } catch (_) {}
    }

    // Check buildkit.yaml
    final buildkitFile = File(p.join(dirPath, TomBuildConfig.projectFilename));
    if (buildkitFile.existsSync()) {
      try {
        final content = buildkitFile.readAsStringSync();
        final yaml = loadYaml(content);
        if (yaml is Map) {
          // Check project-id
          final projectId = yaml['project-id'] as String?;
          if (projectId != null && projectId.toLowerCase() == lowerSearch) {
            return _ConfigMatch.id;
          }
          // Check name
          final name = yaml['name'] as String?;
          if (name != null && name.toLowerCase() == lowerSearch) {
            return _ConfigMatch.name;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  bool _isGlobPattern(String pattern) {
    return pattern.contains('*') ||
        pattern.contains('?') ||
        pattern.contains('[') ||
        pattern.contains('{');
  }

  Future<List<String>> _resolveGlobPattern(
    String pattern,
    String basePath,
    bool Function(String)? projectFilter,
  ) async {
    final results = <String>[];

    try {
      final glob = Glob(pattern);

      await for (final entity in glob.list(root: basePath)) {
        if (entity is Directory) {
          final path = p.normalize(p.absolute(entity.path));
          if (_isProject(path) &&
              (projectFilter == null || projectFilter(path))) {
            results.add(path);
          }
        }
      }
    } catch (e) {
      _log('Warning: Error resolving glob pattern "$pattern": $e');
    }

    return results;
  }

  /// Check if a directory is a Dart project (has pubspec.yaml).
  bool _isProject(String dirPath) {
    return File(p.join(dirPath, 'pubspec.yaml')).existsSync();
  }
}

/// Type of config match found during project search.
enum _ConfigMatch { id, name }
