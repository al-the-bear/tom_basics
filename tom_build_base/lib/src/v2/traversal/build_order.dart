/// Build order computation using topological sort (Kahn's algorithm).
///
/// Computes the correct build order for Dart projects based on
/// inter-project dependencies declared in pubspec.yaml files.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// A dependency of one project on another, as the build order sees it.
class BuildOrderEdge {
  /// The project that declares the dependency.
  final String from;

  /// The project it depends on.
  final String to;

  /// Whether the dependency is declared only under `dev_dependencies`.
  final bool dev;

  /// Creates an edge [from] → [to].
  const BuildOrderEdge(this.from, this.to, {this.dev = false});

  @override
  String toString() => dev ? '$from -> $to (dev)' : '$from -> $to';
}

/// One dependency cycle: a strongly connected group of projects.
class BuildOrderCycle {
  /// The project names in the cycle, sorted.
  final List<String> members;

  /// The dependencies between [members], sorted; cutting one of them breaks
  /// the cycle.
  final List<BuildOrderEdge> edges;

  /// Creates a cycle of [members] joined by [edges].
  const BuildOrderCycle(this.members, this.edges);
}

/// Outcome of a build-order computation.
///
/// Carries either a successfully computed [order] (dependencies first) or,
/// when a circular dependency prevents ordering, the [cycles] that do so.
class BuildOrderResult {
  /// Ordered project paths (dependencies first), or `null` if a cycle was
  /// detected and no valid order exists.
  final List<String>? order;

  /// Names of the projects that are members of a dependency cycle, sorted.
  /// Projects that only depend on a cycle are not listed. Empty when [order]
  /// is non-null.
  final List<String> cycleParticipants;

  /// Each dependency cycle with its edges. Empty when [order] is non-null.
  final List<BuildOrderCycle> cycles;

  /// Creates a result with the given [order], [cycleParticipants] and
  /// [cycles].
  const BuildOrderResult(
    this.order,
    this.cycleParticipants, [
    this.cycles = const [],
  ]);

  /// Whether a circular dependency was detected (i.e. [order] is `null`).
  bool get hasCycle => order == null;
}

/// Computes build order for Dart projects using topological sort.
///
/// Uses Kahn's algorithm to sort projects so that dependencies are
/// built before their dependents.
class BuildOrderComputer {
  /// Compute build order for the given project paths.
  ///
  /// [allProjectPaths] - All project paths to consider for dependency graph.
  /// [includeDev] - Whether to include dev_dependencies. Off by default: a
  /// dev dependency is not needed to build a package, and pub allows cycles
  /// through dev dependencies (a package whose tests use a tool that depends
  /// on the package).
  ///
  /// Returns ordered list of paths (dependencies first), or null if
  /// a circular dependency is detected.
  ///
  /// Use [computeBuildOrderResult] instead when you also need to know which
  /// projects participate in a detected cycle (for diagnostics).
  static List<String>? computeBuildOrder(
    List<String> allProjectPaths, {
    bool includeDev = false,
  }) => computeBuildOrderResult(allProjectPaths, includeDev: includeDev).order;

  /// Compute build order and report cycle participants on failure.
  ///
  /// Like [computeBuildOrder], but returns a [BuildOrderResult] so callers can
  /// distinguish a genuine cycle from an empty order and surface an actionable
  /// diagnostic naming the projects involved.
  static BuildOrderResult computeBuildOrderResult(
    List<String> allProjectPaths, {
    bool includeDev = false,
  }) {
    // Build name → path mapping
    final nameToPath = <String, String>{};
    final pathToName = <String, String>{};
    final pathToDeps = <String, Set<String>>{};
    // Edges declared only under dev_dependencies, for the cycle report.
    final devOnly = <String, Set<String>>{};

    for (final path in allProjectPaths) {
      final name = getProjectName(path);
      nameToPath[name] = path;
      pathToName[path] = name;
      pathToDeps[path] = {};
      devOnly[path] = {};
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
                final target = nameToPath[depName]!;
                if (pathToDeps[path]!.add(target)) devOnly[path]!.add(target);
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
    queue.sort((a, b) => (pathToName[a] ?? a).compareTo(pathToName[b] ?? b));

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
      // Kahn's algorithm leaves the cycles AND everything depending on them
      // unplaced; report only the cycles themselves (strongly connected
      // components), each with its edges, so the reader sees where to cut.
      final cycles = _cycles(pathToDeps, devOnly, pathToName);
      final participants = [
        for (final cycle in cycles) ...cycle.members,
      ]..sort();
      return BuildOrderResult(null, participants, cycles);
    }

    return BuildOrderResult(result, const []);
  }

  /// The strongly connected components with more than one project
  /// (Tarjan's algorithm), as [BuildOrderCycle]s sorted by first member.
  static List<BuildOrderCycle> _cycles(
    Map<String, Set<String>> deps,
    Map<String, Set<String>> devOnly,
    Map<String, String> pathToName,
  ) {
    final index = <String, int>{};
    final low = <String, int>{};
    final stack = <String>[];
    final onStack = <String>{};
    final components = <List<String>>[];
    var counter = 0;

    void connect(String v) {
      index[v] = low[v] = counter++;
      stack.add(v);
      onStack.add(v);
      for (final w in deps[v]!) {
        if (!index.containsKey(w)) {
          connect(w);
          low[v] = low[v]! < low[w]! ? low[v]! : low[w]!;
        } else if (onStack.contains(w)) {
          low[v] = low[v]! < index[w]! ? low[v]! : index[w]!;
        }
      }
      if (low[v] == index[v]) {
        final component = <String>[];
        String w;
        do {
          w = stack.removeLast();
          onStack.remove(w);
          component.add(w);
        } while (w != v);
        if (component.length > 1) components.add(component);
      }
    }

    for (final v in deps.keys) {
      if (!index.containsKey(v)) connect(v);
    }

    String name(String path) => pathToName[path] ?? path;
    final cycles = [
      for (final component in components)
        BuildOrderCycle(
          component.map(name).toList()..sort(),
          [
            for (final from in component)
              for (final to in deps[from]!)
                if (component.contains(to))
                  BuildOrderEdge(
                    name(from),
                    name(to),
                    dev: devOnly[from]!.contains(to),
                  ),
          ]..sort((a, b) => a.toString().compareTo(b.toString())),
        ),
    ]..sort((a, b) => a.members.first.compareTo(b.members.first));
    return cycles;
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
