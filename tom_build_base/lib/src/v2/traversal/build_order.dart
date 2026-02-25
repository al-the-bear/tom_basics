/// Build order computation using topological sort (Kahn's algorithm).
///
/// Computes the correct build order for Dart projects based on
/// inter-project dependencies declared in pubspec.yaml files.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Computes build order for Dart projects using topological sort.
///
/// Uses Kahn's algorithm to sort projects so that dependencies are
/// built before their dependents.
class BuildOrderComputer {
  /// Compute build order for the given project paths.
  ///
  /// [allProjectPaths] - All project paths to consider for dependency graph.
  /// [includeDev] - Whether to include dev_dependencies.
  ///
  /// Returns ordered list of paths (dependencies first), or null if
  /// a circular dependency is detected.
  static List<String>? computeBuildOrder(
    List<String> allProjectPaths, {
    bool includeDev = false,
  }) {
    // Build name → path mapping
    final nameToPath = <String, String>{};
    final pathToName = <String, String>{};
    final pathToDeps = <String, Set<String>>{};

    for (final path in allProjectPaths) {
      final name = getProjectName(path);
      nameToPath[name] = path;
      pathToName[path] = name;
      pathToDeps[path] = {};
    }

    // Build dependency graph (only intra-workspace deps)
    final workspaceNames = nameToPath.keys.toSet();
    for (final path in allProjectPaths) {
      final pubspecFile = File('$path/pubspec.yaml');
      if (!pubspecFile.existsSync()) continue;

      try {
        final yaml = loadYaml(pubspecFile.readAsStringSync()) as YamlMap?;
        if (yaml == null) continue;

        final deps = yaml['dependencies'] as YamlMap?;
        if (deps != null) {
          for (final depName in deps.keys.cast<String>()) {
            if (workspaceNames.contains(depName)) {
              pathToDeps[path]!.add(nameToPath[depName]!);
            }
          }
        }

        if (includeDev) {
          final devDeps = yaml['dev_dependencies'] as YamlMap?;
          if (devDeps != null) {
            for (final depName in devDeps.keys.cast<String>()) {
              if (workspaceNames.contains(depName)) {
                pathToDeps[path]!.add(nameToPath[depName]!);
              }
            }
          }
        }
      } catch (_) {}
    }

    // Kahn's algorithm - topological sort
    final inDegree = <String, int>{};
    for (final path in allProjectPaths) {
      inDegree[path] = 0;
    }
    for (final entry in pathToDeps.entries) {
      inDegree[entry.key] = entry.value.length;
    }

    // Queue with alphabetic tie-breaking for deterministic output
    final queue = <String>[];
    for (final path in allProjectPaths) {
      if (inDegree[path] == 0) queue.add(path);
    }
    queue.sort(
      (a, b) => (pathToName[a] ?? a).compareTo(pathToName[b] ?? b),
    );

    final result = <String>[];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      result.add(current);

      // Reduce in-degree for dependents
      for (final entry in pathToDeps.entries) {
        if (entry.value.contains(current)) {
          inDegree[entry.key] = inDegree[entry.key]! - 1;
          if (inDegree[entry.key] == 0) {
            queue.add(entry.key);
            queue.sort(
              (a, b) => (pathToName[a] ?? a).compareTo(pathToName[b] ?? b),
            );
          }
        }
      }
    }

    if (result.length != allProjectPaths.length) {
      // Circular dependency detected
      return null;
    }

    return result;
  }

  /// Get project name from pubspec.yaml, or folder basename as fallback.
  static String getProjectName(String projectPath) {
    try {
      final pubspec = File('$projectPath/pubspec.yaml');
      if (pubspec.existsSync()) {
        final yaml = loadYaml(pubspec.readAsStringSync()) as YamlMap?;
        return yaml?['name']?.toString() ?? p.basename(projectPath);
      }
    } catch (_) {}
    return p.basename(projectPath);
  }
}
