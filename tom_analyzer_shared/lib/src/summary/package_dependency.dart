// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Represents a resolved package dependency with version information.
///
/// This is used to track which packages can have their analyzer summaries
/// cached and reused across builds.
class PackageDependency {
  /// The package name (e.g., 'flutter', 'provider').
  final String name;

  /// The exact resolved version (e.g., '3.32.0', '6.1.2').
  final String version;

  /// The dependency source type.
  ///
  /// Common values:
  /// - 'hosted' - From pub.dev
  /// - 'sdk' - From Dart or Flutter SDK
  /// - 'git' - From a git repository
  /// - 'path' - Local path dependency
  final String source;

  /// For path dependencies, the absolute path to the package.
  final String? path;

  /// For hosted dependencies, the hosted URL (usually pub.dev).
  final String? hostedUrl;

  /// For SDK dependencies, the SDK name ('dart' or 'flutter').
  final String? sdkName;

  const PackageDependency({
    required this.name,
    required this.version,
    required this.source,
    this.path,
    this.hostedUrl,
    this.sdkName,
  });

  /// Whether this dependency can have its summary cached.
  ///
  /// Only hosted (pub.dev) and SDK packages are cacheable because they
  /// have stable versions. Path and git dependencies may change without
  /// version updates.
  bool get isCacheable => source == 'hosted' || source == 'sdk';

  /// Returns a unique cache key for this dependency.
  ///
  /// Format: `{name}@{version}`
  String get cacheKey => '$name@$version';

  @override
  String toString() => 'PackageDependency($name@$version, source: $source)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PackageDependency &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          version == other.version &&
          source == other.source;

  @override
  int get hashCode => Object.hash(name, version, source);
}

/// Groups dependencies by their cacheability status.
class DependencySet {
  /// Dependencies that can be cached (hosted + SDK).
  final List<PackageDependency> cacheable;

  /// Dependencies that cannot be cached (path + git).
  final List<PackageDependency> uncacheable;

  const DependencySet({
    required this.cacheable,
    required this.uncacheable,
  });

  /// All dependencies combined.
  List<PackageDependency> get all => [...cacheable, ...uncacheable];

  /// Creates a DependencySet from a list of dependencies.
  factory DependencySet.from(List<PackageDependency> dependencies) {
    final cacheable = <PackageDependency>[];
    final uncacheable = <PackageDependency>[];

    for (final dep in dependencies) {
      if (dep.isCacheable) {
        cacheable.add(dep);
      } else {
        uncacheable.add(dep);
      }
    }

    return DependencySet(cacheable: cacheable, uncacheable: uncacheable);
  }
}
