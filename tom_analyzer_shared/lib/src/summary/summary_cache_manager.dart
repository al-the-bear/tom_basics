// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/src/summary/package_bundle_reader.dart';
import 'package:analyzer/src/summary2/package_bundle_format.dart';
import 'package:path/path.dart' as p;

import 'analyzer_version.dart';
import 'package_dependency.dart';

/// Manages the analyzer summary cache for a workspace.
///
/// Summaries are stored in `<workspace>/.tom/analyzer-cache/<analyzer-major>/`
/// with filenames in the format `{package}@{version}.sum`.
///
/// The `<analyzer-major>` segment (see [analyzerMajorVersion]) partitions the
/// cache by the major version of the `analyzer` package that produced the
/// bundles. `.sum` files use an analyzer-version-specific binary format, so a
/// bundle written by one analyzer major is undecodable by another (it crashes
/// the reader). Keying the directory by analyzer major guarantees a tool only
/// ever reads bundles its own analyzer can decode, eliminating the
/// cross-version cache-poison that otherwise survives an analyzer upgrade.
///
/// ## Usage
///
/// ```dart
/// final cacheManager = SummaryCacheManager('/path/to/workspace');
///
/// // Check if a summary exists
/// if (await cacheManager.hasSummary('provider', '6.1.2')) {
///   print('Cache hit!');
/// }
///
/// // Load all summaries for dependencies
/// final store = await cacheManager.loadSummaries(dependencies);
///
/// // Write a new summary
/// await cacheManager.writeSummary('provider', '6.1.2', summaryBytes);
/// ```
class SummaryCacheManager {
  /// The workspace root directory.
  final String workspaceRoot;

  /// The directory where summaries are cached.
  late final String cacheDirectory;

  /// The current Dart SDK version, used for cache invalidation.
  final String dartSdkVersion;

  /// The analyzer major version this cache partition belongs to.
  ///
  /// Defaults to [analyzerMajorVersion] (the analyzer major this package was
  /// built against). Overridable only to let tests exercise the partitioning
  /// without rebuilding against a different analyzer.
  final int analyzerMajor;

  /// Creates a cache manager for the given workspace.
  ///
  /// The [workspaceRoot] should be the directory containing the project's
  /// pubspec.yaml (or the overall workspace root).
  ///
  /// The [dartSdkVersion] is used to invalidate caches when the SDK changes.
  ///
  /// The [analyzerMajor] selects the per-analyzer-major cache partition; it
  /// defaults to [analyzerMajorVersion] and should normally be left unset
  /// outside of tests.
  SummaryCacheManager(
    this.workspaceRoot, {
    String? dartSdkVersion,
    int? analyzerMajor,
  })  : dartSdkVersion = dartSdkVersion ?? _getDartSdkVersion(),
        analyzerMajor = analyzerMajor ?? analyzerMajorVersion {
    cacheDirectory = p.join(
      workspaceRoot,
      '.tom',
      'analyzer-cache',
      '${analyzerMajor ?? analyzerMajorVersion}',
    );
  }

  /// Gets the Dart SDK version from Platform.version.
  static String _getDartSdkVersion() {
    // Platform.version format: "3.8.0 (stable) ..."
    final version = Platform.version;
    final match = RegExp(r'^(\d+\.\d+\.\d+)').firstMatch(version);
    return match?.group(1) ?? 'unknown';
  }

  /// Returns the cache file path for a package.
  ///
  /// Format: `<cache-dir>/{package}@{version}.sum`
  String getCachePath(String packageName, String version) {
    final sanitizedName = _sanitizeFilename(packageName);
    final sanitizedVersion = _sanitizeFilename(version);
    return p.join(cacheDirectory, '$sanitizedName@$sanitizedVersion.sum');
  }

  /// Returns the cache file path for the SDK summary.
  ///
  /// Format: `<cache-dir>/sdk@{dart-version}.sum`
  String getSdkSummaryPath() {
    return getCachePath('sdk', dartSdkVersion);
  }

  /// Checks if a valid SDK summary exists in our cache.
  Future<bool> hasSdkSummary() async {
    return hasSummary('sdk', dartSdkVersion);
  }

  /// Sanitizes a string for use in a filename.
  String _sanitizeFilename(String name) {
    // Replace any characters that might be problematic in filenames
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  /// Checks if a valid summary exists for the package.
  ///
  /// A summary is considered valid if:
  /// 1. The file exists
  /// 2. The file is not empty
  /// 3. The file was created with a compatible SDK version (TODO)
  Future<bool> hasSummary(String packageName, String version) async {
    final path = getCachePath(packageName, version);
    final file = File(path);

    if (!await file.exists()) {
      return false;
    }

    // Check if file is not empty
    final stat = await file.stat();
    if (stat.size == 0) {
      return false;
    }

    // TODO: Check SDK version compatibility from summary metadata
    return true;
  }

  /// Checks which dependencies are missing from the cache.
  ///
  /// Returns a list of dependencies that don't have valid cached summaries.
  Future<List<PackageDependency>> findMissingSummaries(
    List<PackageDependency> dependencies,
  ) async {
    final missing = <PackageDependency>[];

    for (final dep in dependencies) {
      if (!dep.isCacheable) continue;

      if (!await hasSummary(dep.name, dep.version)) {
        missing.add(dep);
      }
    }

    return missing;
  }

  /// Loads a single summary from the cache.
  ///
  /// Returns null if the summary doesn't exist or is invalid.
  Future<PackageBundleReader?> loadSummary(
    String packageName,
    String version,
  ) async {
    final path = getCachePath(packageName, version);
    final file = File(path);

    if (!await file.exists()) {
      return null;
    }

    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return null;
      }
      return PackageBundleReader(bytes);
    } catch (e) {
      // Corrupted summary - delete and return null
      await _safeDelete(file);
      return null;
    }
  }

  /// Loads all available summaries into a SummaryDataStore.
  ///
  /// Only loads summaries for dependencies that:
  /// 1. Are cacheable (hosted or SDK)
  /// 2. Have a valid cached summary file
  ///
  /// Dependencies without cached summaries are silently skipped.
  Future<SummaryDataStore> loadSummaries(
    List<PackageDependency> dependencies,
  ) async {
    final store = SummaryDataStore();

    for (final dep in dependencies) {
      if (!dep.isCacheable) continue;

      final bundle = await loadSummary(dep.name, dep.version);
      if (bundle != null) {
        final path = getCachePath(dep.name, dep.version);
        store.addBundle(path, bundle);
      }
    }

    return store;
  }

  /// Writes a summary for a package.
  ///
  /// Creates the cache directory if it doesn't exist.
  /// Overwrites any existing summary for the same package@version.
  Future<void> writeSummary(
    String packageName,
    String version,
    Uint8List bytes,
  ) async {
    await ensureCacheDirectory();

    final path = getCachePath(packageName, version);

    // Write atomically using a temp file
    final tempPath = '$path.tmp';
    final tempFile = File(tempPath);

    try {
      await tempFile.writeAsBytes(bytes, flush: true);
      await tempFile.rename(path);
    } catch (e) {
      // Clean up temp file on failure
      await _safeDelete(tempFile);
      rethrow;
    }
  }

  /// Ensures the cache directory exists.
  Future<void> ensureCacheDirectory() async {
    final dir = Directory(cacheDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Lists all cached summaries.
  ///
  /// Returns a map of package@version -> file path.
  Future<Map<String, String>> listCachedSummaries() async {
    final dir = Directory(cacheDirectory);
    if (!await dir.exists()) {
      return {};
    }

    final summaries = <String, String>{};

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.sum')) {
        final basename = p.basenameWithoutExtension(entity.path);
        summaries[basename] = entity.path;
      }
    }

    return summaries;
  }

  /// Deletes all cached summaries.
  Future<void> clearCache() async {
    final dir = Directory(cacheDirectory);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.sum')) {
          await _safeDelete(entity);
        }
      }
    }
  }

  /// Clears outdated summaries created with a different SDK version.
  ///
  /// Since SDK version is not currently embedded in summary files,
  /// this is a placeholder that clears all summaries when the SDK changes.
  /// 
  /// TODO: Implement SDK version checking in summary metadata.
  Future<void> cleanOutdated() async {
    // For now, we can't check SDK version in summaries.
    // This will be implemented when we add SDK metadata to summaries.
    // Currently a no-op - callers should use cleanUnusedSummaries() instead.
  }

  /// Clears summaries that don't match current dependencies.
  ///
  /// Keeps only summaries that match a dependency in [currentDependencies].
  /// This helps clean up old version summaries after pub upgrade.
  Future<int> cleanUnusedSummaries(List<PackageDependency> currentDependencies) async {
    final cached = await listCachedSummaries();
    final current = <String>{
      for (final dep in currentDependencies)
        if (dep.isCacheable) dep.cacheKey,
    };

    var removed = 0;
    for (final entry in cached.entries) {
      if (!current.contains(entry.key)) {
        await _safeDelete(File(entry.value));
        removed++;
      }
    }

    return removed;
  }

  /// Safely deletes a file, ignoring errors.
  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore deletion errors
    }
  }

  /// Returns cache statistics.
  Future<CacheStats> getStats() async {
    final cached = await listCachedSummaries();
    var totalSize = 0;

    for (final path in cached.values) {
      final file = File(path);
      if (await file.exists()) {
        totalSize += await file.length();
      }
    }

    return CacheStats(
      summaryCount: cached.length,
      totalSizeBytes: totalSize,
      cacheDirectory: cacheDirectory,
    );
  }
}

/// Statistics about the summary cache.
class CacheStats {
  /// Number of cached summaries.
  final int summaryCount;

  /// Total size of all cached summaries in bytes.
  final int totalSizeBytes;

  /// The cache directory path.
  final String cacheDirectory;

  const CacheStats({
    required this.summaryCount,
    required this.totalSizeBytes,
    required this.cacheDirectory,
  });

  /// Total size in megabytes.
  double get totalSizeMB => totalSizeBytes / (1024 * 1024);

  @override
  String toString() {
    return 'CacheStats(summaries: $summaryCount, '
        'size: ${totalSizeMB.toStringAsFixed(2)} MB, '
        'dir: $cacheDirectory)';
  }
}
