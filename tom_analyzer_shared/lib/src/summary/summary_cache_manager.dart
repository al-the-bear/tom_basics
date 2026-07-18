// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/src/summary/package_bundle_reader.dart';
import 'package:analyzer/src/summary2/package_bundle_format.dart';
import 'package:path/path.dart' as p;

import '../cache/tool_cache_locator.dart';
import 'analyzer_version.dart';
import 'package_dependency.dart';

/// Sub-directory of the shared tool cache that holds analyzer summaries.
const String _analyzerCacheSubDir = 'analyzer-cache';

/// Manages the analyzer summary cache for a workspace.
///
/// Summaries are stored in
/// `<tool-cache>/analyzer-cache/<analyzer-major>/<dart-sdk-version>/` with
/// filenames in the format `{package}@{version}.sum`, where `<tool-cache>` is
/// the shared Tom tool-cache directory resolved by [ToolCacheLocator] (so the
/// same hosted-package summary is reused across projects and tools). Pass an
/// explicit [cacheDirectory] to override that resolution.
///
/// Two partition segments together prevent cross-toolchain cache poison, both
/// necessary because `.sum` files use an analyzer-version-specific binary
/// format that a *different* analyzer cannot decode (it crashes the reader):
///
/// * `<analyzer-major>` (see [analyzerMajorVersion]) partitions by the major
///   version of the `analyzer` package that produced the bundles.
/// * `<dart-sdk-version>` (see [dartSdkVersion]) partitions by the exact Dart
///   SDK that produced them. This is load-bearing because the bundle format has
///   **no stability guarantee within an analyzer major** — a point SDK upgrade
///   can ship a format-incompatible analyzer of the same major, so keying by
///   major alone is insufficient. Concretely, after the 2026-07-16 fleet SDK
///   upgrade, pre-upgrade `.sum` files were read by the new analyzer and
///   crashed with `RangeError ... StringTable` (string-table misalignment).
///   The SDK version is the AOT-safe toolchain-identity signal (the analyzer
///   exposes no runtime version constant, and AOT-compiled generators cannot
///   path-sniff their own `package_config`), and it self-freshens on every SDK
///   upgrade: a toolchain change starts from an empty partition automatically,
///   so `--rebuild-cache` is never needed for *correctness*.
///
/// Keying the directory by both guarantees a tool only ever reads bundles its
/// own toolchain produced.
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
  ///
  /// Used as the starting point for the [ToolCacheLocator] ancestor search
  /// when [cacheDirectory] is not given explicitly.
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
  /// pubspec.yaml (or the overall workspace root). It seeds the
  /// [ToolCacheLocator] ancestor search that picks the shared cache location.
  ///
  /// The [dartSdkVersion] is used to invalidate caches when the SDK changes.
  ///
  /// Provide [cacheDirectory] to bypass shared-cache resolution entirely and
  /// store summaries in a fixed directory — used by tests to stay hermetic and
  /// by callers that manage their own cache layout. [environment] overrides the
  /// process environment consulted by [ToolCacheLocator] (primarily for tests).
  ///
  /// The [analyzerMajor] selects the per-analyzer-major cache partition; it
  /// defaults to [analyzerMajorVersion] and should normally be left unset
  /// outside of tests.
  SummaryCacheManager(
    this.workspaceRoot, {
    String? dartSdkVersion,
    String? cacheDirectory,
    Map<String, String>? environment,
    int? analyzerMajor,
  }) : dartSdkVersion = dartSdkVersion ?? _getDartSdkVersion(),
       analyzerMajor = analyzerMajor ?? analyzerMajorVersion {
    this.cacheDirectory =
        cacheDirectory ??
        p.join(
          ToolCacheLocator.resolve(
            startDirectory: workspaceRoot,
            environment: environment,
          ),
          _analyzerCacheSubDir,
          '${analyzerMajor ?? analyzerMajorVersion}',
          this.dartSdkVersion,
        );
  }

  /// Gets the Dart SDK version from Platform.version.
  static String _getDartSdkVersion() => currentDartSdkVersion();

  /// Returns the cache file path for a package.
  ///
  /// Format: `<cache-dir>/{package}@{version}.sum`
  String getCachePath(String packageName, String version) {
    final sanitizedName = _sanitizeFilename(packageName);
    final sanitizedVersion = _sanitizeFilename(version);
    return p.join(cacheDirectory, '$sanitizedName@$sanitizedVersion.sum');
  }

  /// Returns the path of the dependency-fingerprint sidecar for a package.
  ///
  /// Format: `<cache-dir>/{package}@{version}.sum.deps`. The sidecar records
  /// the exact versioned dependency closure the `.sum` bundle was linked
  /// against, so the bundle can be invalidated when any package in that
  /// closure changes version — even though the package's own `name@version`
  /// (and therefore its `.sum` filename) is unchanged. See [isSummaryFresh].
  String getFingerprintPath(String packageName, String version) {
    return '${getCachePath(packageName, version)}.deps';
  }

  /// Writes the dependency-closure [fingerprint] for a cached summary.
  ///
  /// Call immediately after [writeSummary] with the fingerprint computed from
  /// the versioned dependency closure the bundle was generated against.
  Future<void> writeFingerprint(
    String packageName,
    String version,
    String fingerprint,
  ) async {
    await ensureCacheDirectory();
    final path = getFingerprintPath(packageName, version);
    final tempPath = '$path.tmp';
    final tempFile = File(tempPath);
    try {
      await tempFile.writeAsString(fingerprint, flush: true);
      await tempFile.rename(path);
    } catch (e) {
      await _safeDelete(tempFile);
      rethrow;
    }
  }

  /// Reads the recorded dependency-closure fingerprint for a cached summary.
  ///
  /// Returns `null` when the sidecar is absent (e.g. a bundle produced before
  /// fingerprinting existed, which must be treated as stale).
  Future<String?> readFingerprint(String packageName, String version) async {
    final file = File(getFingerprintPath(packageName, version));
    if (!await file.exists()) {
      return null;
    }
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Whether a cached summary is present *and* was linked against the same
  /// versioned dependency closure described by [expectedFingerprint].
  ///
  /// A summary is stale — and this returns `false` — when its `.sum` is
  /// missing/empty, its fingerprint sidecar is absent, or the recorded
  /// fingerprint differs from [expectedFingerprint] (a transitive dependency
  /// changed version). Loading a stale summary produces "Missing library"
  /// link failures because the bundle references a dependency layout that no
  /// longer matches the resolved graph.
  Future<bool> isSummaryFresh(
    String packageName,
    String version,
    String expectedFingerprint,
  ) async {
    if (!await hasSummary(packageName, version)) {
      return false;
    }
    final recorded = await readFingerprint(packageName, version);
    return recorded == expectedFingerprint;
  }

  /// Deletes a cached summary and its fingerprint sidecar, if present.
  Future<void> deleteSummary(String packageName, String version) async {
    await _safeDelete(File(getCachePath(packageName, version)));
    await _safeDelete(File(getFingerprintPath(packageName, version)));
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

  /// Deletes all cached summaries and their fingerprint sidecars.
  Future<void> clearCache() async {
    final dir = Directory(cacheDirectory);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File &&
            (entity.path.endsWith('.sum') ||
                entity.path.endsWith('.sum.deps'))) {
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
  Future<int> cleanUnusedSummaries(
    List<PackageDependency> currentDependencies,
  ) async {
    final cached = await listCachedSummaries();
    final current = <String>{
      for (final dep in currentDependencies)
        if (dep.isCacheable) dep.cacheKey,
    };

    var removed = 0;
    for (final entry in cached.entries) {
      if (!current.contains(entry.key)) {
        await _safeDelete(File(entry.value));
        await _safeDelete(File('${entry.value}.deps'));
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
