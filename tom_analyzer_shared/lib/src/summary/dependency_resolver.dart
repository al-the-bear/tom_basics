// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package_dependency.dart';

/// Resolves project dependencies with their versions from pubspec.lock.
///
/// This class parses the pubspec.lock file to extract all dependencies
/// with their exact resolved versions, which is needed for summary caching.
///
/// ## Usage
///
/// ```dart
/// final resolver = DependencyResolver();
///
/// // Resolve all dependencies
/// final deps = await resolver.resolveVersionedDependencies('/path/to/project');
///
/// // Filter to only cacheable dependencies
/// final cacheable = deps.where((d) => d.isCacheable).toList();
/// ```
class DependencyResolver {
  /// Gets the Dart SDK version.
  ///
  /// Extracts the version from `Platform.version` which has format:
  /// "3.8.0 (stable) (Wed Apr 3 13:28:12 2026 +0200) on "linux_x64""
  String getDartVersion() {
    final version = Platform.version;
    final match = RegExp(r'^(\d+\.\d+\.\d+)').firstMatch(version);
    return match?.group(1) ?? 'unknown';
  }

  /// Gets the Flutter SDK version.
  ///
  /// Runs `flutter --version --machine` and parses the JSON output.
  /// Returns null if Flutter is not available or the command fails.
  Future<String?> getFlutterVersion() async {
    try {
      final result = await Process.run(
        'flutter',
        ['--version', '--machine'],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        return null;
      }

      // Parse JSON output
      final output = result.stdout as String;
      final versionMatch = RegExp(r'"frameworkVersion"\s*:\s*"([^"]+)"')
          .firstMatch(output);
      return versionMatch?.group(1);
    } catch (e) {
      return null;
    }
  }

  /// Parses pubspec.lock to get exact dependency versions.
  ///
  /// Returns a list of all dependencies including transitive ones.
  /// Each dependency includes:
  /// - name: Package name
  /// - version: Exact resolved version
  /// - source: 'hosted', 'sdk', 'path', or 'git'
  /// - path: For path dependencies, the resolved path
  ///
  /// Throws [FileSystemException] if pubspec.lock doesn't exist.
  Future<List<PackageDependency>> resolveVersionedDependencies(
    String projectRoot,
  ) async {
    final lockFile = File(p.join(projectRoot, 'pubspec.lock'));

    if (!await lockFile.exists()) {
      throw FileSystemException(
        'pubspec.lock not found. Run "dart pub get" first.',
        lockFile.path,
      );
    }

    final content = await lockFile.readAsString();
    final yaml = loadYaml(content) as YamlMap?;

    if (yaml == null) {
      return [];
    }

    final packages = yaml['packages'] as YamlMap?;
    if (packages == null) {
      return [];
    }

    final dependencies = <PackageDependency>[];
    final flutterVersion = await getFlutterVersion();

    for (final entry in packages.entries) {
      final name = entry.key as String;
      final data = entry.value as YamlMap;

      final dep = _parseDependency(
        name,
        data,
        projectRoot,
        flutterVersion: flutterVersion,
      );

      if (dep != null) {
        dependencies.add(dep);
      }
    }

    // Sort by name for consistent ordering
    dependencies.sort((a, b) => a.name.compareTo(b.name));

    return dependencies;
  }

  /// Parses a single dependency entry from pubspec.lock.
  PackageDependency? _parseDependency(
    String name,
    YamlMap data,
    String projectRoot, {
    String? flutterVersion,
  }) {
    final source = data['source'] as String?;
    final version = data['version'] as String?;
    final description = data['description'];

    if (source == null) {
      return null;
    }

    switch (source) {
      case 'hosted':
        return _parseHostedDependency(name, version, description);

      case 'sdk':
        return _parseSdkDependency(name, description, flutterVersion);

      case 'path':
        return _parsePathDependency(name, version, description, projectRoot);

      case 'git':
        return _parseGitDependency(name, version, description);

      default:
        // Unknown source type - skip
        return null;
    }
  }

  /// Parses a hosted (pub.dev) dependency.
  PackageDependency? _parseHostedDependency(
    String name,
    String? version,
    dynamic description,
  ) {
    if (version == null) return null;

    String? hostedUrl;
    if (description is YamlMap) {
      hostedUrl = description['url'] as String?;
    }

    return PackageDependency(
      name: name,
      version: version,
      source: 'hosted',
      hostedUrl: hostedUrl ?? 'https://pub.dev',
    );
  }

  /// Parses an SDK dependency (Flutter or Dart).
  PackageDependency? _parseSdkDependency(
    String name,
    dynamic description,
    String? flutterVersion,
  ) {
    String sdkName = 'flutter'; // Default to flutter SDK

    if (description is YamlMap) {
      sdkName = description['sdk'] as String? ?? 'flutter';
    } else if (description is String) {
      sdkName = description;
    }

    // SDK packages have version "0.0.0" in lock file - use actual SDK version
    final version = sdkName == 'flutter'
        ? (flutterVersion ?? '0.0.0')
        : Platform.version.split(' ').first;

    return PackageDependency(
      name: name,
      version: version,
      source: 'sdk',
      sdkName: sdkName,
    );
  }

  /// Parses a path dependency.
  PackageDependency? _parsePathDependency(
    String name,
    String? version,
    dynamic description,
    String projectRoot,
  ) {
    if (version == null) return null;

    String? path;
    if (description is YamlMap) {
      final relativePath = description['path'] as String?;
      final isRelative = description['relative'] as bool? ?? true;

      if (relativePath != null) {
        path = isRelative
            ? p.normalize(p.join(projectRoot, relativePath))
            : relativePath;
      }
    }

    return PackageDependency(
      name: name,
      version: version,
      source: 'path',
      path: path,
    );
  }

  /// Parses a git dependency.
  PackageDependency? _parseGitDependency(
    String name,
    String? version,
    dynamic description,
  ) {
    // Git dependencies are versioned by commit hash, not semantic version
    // Use the version field if available, otherwise "git"
    return PackageDependency(
      name: name,
      version: version ?? 'git',
      source: 'git',
    );
  }

  /// Resolves and returns only cacheable dependencies.
  ///
  /// This is a convenience method that filters out path and git dependencies.
  Future<List<PackageDependency>> resolveCacheableDependencies(
    String projectRoot,
  ) async {
    final all = await resolveVersionedDependencies(projectRoot);
    return all.where((d) => d.isCacheable).toList();
  }

  /// Returns a DependencySet with dependencies grouped by cacheability.
  Future<DependencySet> resolveDependencySet(String projectRoot) async {
    final all = await resolveVersionedDependencies(projectRoot);
    return DependencySet.from(all);
  }

  /// Gets the package location for a hosted dependency.
  ///
  /// Returns the path in the pub cache where the package is installed.
  String? getHostedPackagePath(PackageDependency dependency) {
    if (dependency.source != 'hosted') return null;

    // Standard pub cache location
    final pubCache = Platform.environment['PUB_CACHE'] ??
        p.join(
          Platform.environment['HOME'] ?? '',
          '.pub-cache',
        );

    // Hosted packages are in pub-cache/hosted/pub.dev/
    final hostDir = dependency.hostedUrl?.replaceAll('https://', '') ?? 'pub.dev';
    return p.join(
      pubCache,
      'hosted',
      hostDir,
      '${dependency.name}-${dependency.version}',
    );
  }

  /// Gets the package location for an SDK dependency.
  ///
  /// Returns the path in the Flutter/Dart SDK where the package is located.
  Future<String?> getSdkPackagePath(PackageDependency dependency) async {
    if (dependency.source != 'sdk') return null;

    if (dependency.sdkName == 'flutter') {
      final sdkPath = await getFlutterSdkPath();
      if (sdkPath == null) return null;

      // sky_engine and flutter_gpu are in bin/cache/pkg/, not packages/
      if (dependency.name == 'sky_engine' ||
          dependency.name == 'flutter_gpu') {
        final cachePath =
            p.join(sdkPath, 'bin', 'cache', 'pkg', dependency.name);
        if (await Directory(cachePath).exists()) {
          return cachePath;
        }
      }

      // Regular Flutter packages are in packages/
      final packagesPath = p.join(sdkPath, 'packages', dependency.name);
      if (await Directory(packagesPath).exists()) {
        return packagesPath;
      }
    }

    // Dart SDK packages - not typically cached
    return null;
  }

  /// Gets the Flutter SDK root path.
  ///
  /// Tries multiple methods:
  /// 1. FLUTTER_ROOT environment variable
  /// 2. Resolve `which flutter` to find SDK path
  Future<String?> getFlutterSdkPath() async {
    // Try FLUTTER_ROOT environment variable first
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null && flutterRoot.isNotEmpty) {
      final dir = Directory(flutterRoot);
      if (await dir.exists()) {
        return flutterRoot;
      }
    }

    // Resolve from `which flutter` - the flutter binary is at <sdk>/bin/flutter
    try {
      final result = await Process.run('which', ['flutter'], runInShell: true);
      if (result.exitCode == 0) {
        final flutterPath = (result.stdout as String).trim();
        if (flutterPath.isNotEmpty) {
          // Resolve symlinks to get real path
          final resolved = await File(flutterPath).resolveSymbolicLinks();
          // Flutter binary is at <sdk>/bin/flutter, so SDK is two levels up
          final sdkPath = p.dirname(p.dirname(resolved));
          if (await Directory(sdkPath).exists()) {
            return sdkPath;
          }
        }
      }
    } catch (_) {
      // Fall through
    }

    return null;
  }
}

/// Extension methods for working with dependency lists.
extension DependencyListExtensions on List<PackageDependency> {
  /// Finds a dependency by name.
  PackageDependency? findByName(String name) {
    for (final dep in this) {
      if (dep.name == name) return dep;
    }
    return null;
  }

  /// Returns only hosted dependencies.
  List<PackageDependency> get hosted =>
      where((d) => d.source == 'hosted').toList();

  /// Returns only SDK dependencies.
  List<PackageDependency> get sdk =>
      where((d) => d.source == 'sdk').toList();

  /// Returns only path dependencies.
  List<PackageDependency> get paths =>
      where((d) => d.source == 'path').toList();

  /// Returns only cacheable dependencies.
  List<PackageDependency> get cacheable =>
      where((d) => d.isCacheable).toList();
}
