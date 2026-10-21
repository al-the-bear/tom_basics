/// The package graph as the pubspecs declare it and as `pub get` resolved
/// it: reading a pubspec, finding packages, and following dependencies.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// A parsed `pubspec.yaml`: the package name plus every declared dependency,
/// across all three blocks.
class Pubspec {
  Pubspec._(
    this.name,
    this.directory,
    this.dependencies,
    this.pathDependencies,
    this.runtimeDependencies,
    this.sdkDependencies,
  );

  final String name;
  final String directory;

  /// Names declared under `dependencies`, `dev_dependencies` **and**
  /// `dependency_overrides`: an override is as much a licence edge as a
  /// dependency.
  final Set<String> dependencies;

  /// The subset declared with a `path:`, mapped to the absolute directory —
  /// the edges a transitive walk can actually follow without a resolved
  /// package graph.
  final Map<String, String> pathDependencies;

  /// Names declared under `dependencies` alone: the edges a package brings
  /// into somebody *else's* resolved graph. A hosted package's dev
  /// dependencies are never resolved for its consumers, so a walk through a
  /// hosted package follows only these.
  final Set<String> runtimeDependencies;

  /// The subset declared with an `sdk:` (`flutter`, `flutter_test`, …) —
  /// resolved by the SDK rather than by pub, and so never "unresolved".
  final Set<String> sdkDependencies;

  static Pubspec? read(String packageDir) {
    final file = File(p.join(packageDir, 'pubspec.yaml'));
    if (!file.existsSync()) return null;
    final doc = loadYaml(file.readAsStringSync());
    if (doc is! YamlMap) return null;
    final names = <String>{};
    final runtime = <String>{};
    final sdk = <String>{};
    final paths = <String, String>{};
    for (final block in const [
      'dependencies',
      'dev_dependencies',
      'dependency_overrides',
    ]) {
      final section = doc[block];
      if (section is! YamlMap) continue;
      for (final entry in section.entries) {
        final name = entry.key.toString();
        names.add(name);
        if (block == 'dependencies') runtime.add(name);
        final spec = entry.value;
        if (spec is YamlMap && spec['path'] != null) {
          paths[name] = p.normalize(
            p.join(packageDir, spec['path'].toString()),
          );
        }
        if (spec is YamlMap && spec['sdk'] != null) sdk.add(name);
      }
    }
    return Pubspec._(
      doc['name'].toString(),
      packageDir,
      names,
      paths,
      runtime,
      sdk,
    );
  }
}

/// Every package directory directly under [root] that carries a `pubspec.yaml`.
List<Pubspec> packagesIn(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  final found = <Pubspec>[];
  for (final entity in dir.listSync().whereType<Directory>()) {
    final pubspec = Pubspec.read(entity.path);
    if (pubspec != null) found.add(pubspec);
  }
  found.sort((a, b) => a.name.compareTo(b.name));
  return found;
}

/// Every package whose directory is named [prefix]`*` under [workspaceRoot],
/// searched to [maxDepth] so a moved repository is found without walking the
/// whole workspace.
List<Pubspec> prefixedPackagesIn(
  String workspaceRoot,
  String prefix, {
  int maxDepth = 3,
}) {
  final found = <Pubspec>[];
  void walk(Directory dir, int depth) {
    if (depth > maxDepth) return;
    List<FileSystemEntity> children;
    try {
      children = dir.listSync();
    } on FileSystemException {
      return;
    }
    for (final entity in children.whereType<Directory>()) {
      final name = p.basename(entity.path);
      if (name.startsWith('.') || name == 'node_modules') continue;
      if (name.startsWith(prefix)) {
        final pubspec = Pubspec.read(entity.path);
        if (pubspec != null) {
          found.add(pubspec);
          continue;
        }
      }
      walk(entity, depth + 1);
    }
  }

  walk(Directory(workspaceRoot), 0);
  found.sort((a, b) => a.name.compareTo(b.name));
  return found;
}

/// Package name → its root directory in the graph `pub get` resolved for the
/// package at [packageDir], read from `.dart_tool/package_config.json`. Null
/// when the package has not been resolved.
///
/// This is how a walk follows **hosted** dependencies: a pubspec names a hosted
/// package by version constraint only, and only the resolution says which
/// copy — in the pub cache — is the one a build links, so it is that copy's
/// pubspec the walk reads.
Map<String, String>? resolvedPackagesOf(String packageDir) {
  final config = File(p.join(packageDir, '.dart_tool', 'package_config.json'));
  if (!config.existsSync()) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(config.readAsStringSync());
  } on FormatException {
    return null;
  }
  if (decoded is! Map || decoded['packages'] is! List) return null;
  final base = Uri.file(config.path);
  return {
    for (final entry in decoded['packages'] as List)
      if (entry is Map && entry['name'] is String && entry['rootUri'] is String)
        entry['name'] as String: p.normalize(
          base.resolve(entry['rootUri'] as String).toFilePath(),
        ),
  };
}

/// The type names (`class`, `mixin`, `enum`, `extension`, `typedef`) declared
/// at the start of a line in any `.dart` file under [directory].
Set<String> declaredTypeNamesUnder(String directory) {
  final declaration = RegExp(
    r'^\s*(?:abstract\s+|base\s+|final\s+|sealed\s+|mixin\s+)*'
    r'(?:class|mixin|enum|extension|typedef)\s+(\w+)',
  );
  final symbols = <String>{};
  final dir = Directory(directory);
  if (!dir.existsSync()) return symbols;
  for (final entity in dir.listSync(recursive: true).whereType<File>()) {
    if (!entity.path.endsWith('.dart')) continue;
    for (final line in const LineSplitter().convert(
      entity.readAsStringSync(),
    )) {
      final match = declaration.firstMatch(line);
      if (match != null) symbols.add(match.group(1)!);
    }
  }
  return symbols;
}

/// The packages [isBanned] matches that [root] reaches — each with the
/// dependency chain that reaches it — and the hosted dependencies the walk
/// could not follow because [root] was never resolved.
///
/// [root] and every path package are followed through all three declared
/// blocks; a hosted package through its runtime `dependencies` only, read
/// from the copy [root]'s resolution names. [pubspecs] caches the reads
/// across roots, which share most of their graph. A walk that reaches a
/// banned package does not go further into it.
({Map<String, List<String>> reached, Set<String> unresolved}) dependencyReach(
  Pubspec root, {
  required bool Function(String package) isBanned,
  Map<String, Pubspec?>? pubspecs,
}) {
  final cache = pubspecs ?? <String, Pubspec?>{};
  final reached = <String, List<String>>{};
  final unresolved = <String>{};
  final resolved = resolvedPackagesOf(root.directory);
  final seen = <String>{};
  void walk(Pubspec node, List<String> chain, {required bool declared}) {
    if (!seen.add(node.directory)) return;
    final edges = declared ? node.dependencies : node.runtimeDependencies;
    for (final dependency in edges) {
      if (isBanned(dependency)) {
        reached.putIfAbsent(dependency, () => [...chain, node.name]);
        continue;
      }
      final path = node.pathDependencies[dependency];
      final directory = path ?? resolved?[dependency];
      if (directory == null) {
        // Unresolved: an SDK package answers for itself, and a name missing
        // from a resolution that exists is a dev dependency of a non-root
        // package — never part of the graph.
        if (resolved == null && !node.sdkDependencies.contains(dependency)) {
          unresolved.add(dependency);
        }
        continue;
      }
      final next = cache.putIfAbsent(directory, () => Pubspec.read(directory));
      if (next != null) {
        walk(next, [...chain, node.name], declared: path != null);
      }
    }
  }

  walk(root, const [], declared: true);
  return (reached: reached, unresolved: unresolved);
}
