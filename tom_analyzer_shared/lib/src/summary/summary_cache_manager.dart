// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:analyzer/src/summary/package_bundle_reader.dart';
import 'package:analyzer/src/summary2/package_bundle_format.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../cache/tool_cache_locator.dart';
import 'analyzer_version.dart';
import 'analyzer_version.dart' as shared_version show analyzerDataVersion;
import 'package_dependency.dart';

/// Sub-directory of the shared tool cache that holds analyzer summaries.
const String _analyzerCacheSubDir = 'analyzer-cache';

/// Manages the analyzer summary cache for a workspace.
///
/// Summaries are stored in
/// `<tool-cache>/analyzer-cache/<analyzer-major>/<toolchain>/` with
/// filenames in the format `{package}@{version}+{closure-hash}.sum` (see
/// [getCachePath]), where `<tool-cache>` is
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
/// * `<toolchain>` (see [currentToolchainKey]) is
///   `<dart-sdk-version>+d<analyzer-data-version>`: the exact Dart SDK and the
///   linked analyzer's `AnalysisDriver.DATA_VERSION` ([analyzerDataVersion]),
///   which the analyzer raises whenever its stored format changes. Neither the
///   major nor the SDK is enough on its own: after the 2026-07-16 fleet SDK
///   upgrade, pre-upgrade `.sum` files crashed the new analyzer with
///   `RangeError ... StringTable`, and analyzer 14.5.0 and 14.7.0 on one Dart
///   SDK write bundles the other cannot read. Both parts are constants of the
///   running toolchain, so they are right in an AOT-compiled tool, and a
///   toolchain change starts from an empty partition automatically —
///   `--rebuild-cache` is never needed for *correctness*.
///
/// Keying the directory by both guarantees a tool only ever reads bundles its
/// own toolchain produced.
///
/// ## Usage
///
/// ```dart
/// final cacheManager = SummaryCacheManager('/path/to/workspace');
///
/// // The fingerprint of the dependency closure the bundle is linked against
/// // (SummaryGenerator.computeDependencyFingerprints).
/// final fingerprint = fingerprints['provider']!;
///
/// // Check if a summary exists
/// if (await cacheManager.hasSummary('provider', '6.1.2',
///     fingerprint: fingerprint)) {
///   print('Cache hit!');
/// }
///
/// // Write a new summary
/// await cacheManager.writeSummary('provider', '6.1.2', summaryBytes,
///     fingerprint: fingerprint);
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

  /// The analyzer data version this cache partition belongs to.
  ///
  /// Defaults to [analyzerDataVersion] (the linked analyzer's). Overridable
  /// only to let tests exercise the partitioning without another analyzer.
  final int analyzerDataVersion;

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
  /// The [analyzerMajor] and [analyzerDataVersion] select the cache
  /// partition; they default to the linked analyzer's
  /// ([analyzerMajorVersion], the library constant [analyzerDataVersion]) and
  /// should normally be left unset outside of tests.
  SummaryCacheManager(
    this.workspaceRoot, {
    String? dartSdkVersion,
    String? cacheDirectory,
    Map<String, String>? environment,
    int? analyzerMajor,
    int? analyzerDataVersion,
  }) : dartSdkVersion = dartSdkVersion ?? _getDartSdkVersion(),
       analyzerMajor = analyzerMajor ?? analyzerMajorVersion,
       analyzerDataVersion =
           analyzerDataVersion ?? shared_version.analyzerDataVersion {
    this.cacheDirectory =
        cacheDirectory ??
        p.join(
          ToolCacheLocator.resolve(
            startDirectory: workspaceRoot,
            environment: environment,
          ),
          _analyzerCacheSubDir,
          '${this.analyzerMajor}',
          currentToolchainKey(
            dartSdkVersion: this.dartSdkVersion,
            dataVersion: this.analyzerDataVersion,
          ),
        );
  }

  /// Gets the Dart SDK version from Platform.version.
  static String _getDartSdkVersion() => currentDartSdkVersion();

  /// Returns the cache file path for a package's bundle linked against the
  /// dependency closure [fingerprint] describes.
  ///
  /// Format: `<cache-dir>/{package}@{version}+{closure-hash}.sum`, the hash
  /// being [closureHash] of [fingerprint]. The closure is part of the name
  /// because one `name@version` is linked against different closures in
  /// different projects (another version of a dependency): keyed by
  /// `name@version` alone, each project's run took the other's bundle for
  /// stale and deleted it — while a concurrent run was linking against it
  /// (tom_forge later22). Under its own name every closure's bundle is valid
  /// for as long as it exists; nothing deletes one a run might be using, and
  /// one no run uses any more is swept by age (`analyzer_cache_gc clean`).
  String getCachePath(
    String packageName,
    String version, {
    required String fingerprint,
  }) => _pathFor(packageName, '$version+${closureHash(fingerprint)}');

  /// The first 16 hex digits (64 bits) of the SHA-256 of [fingerprint]: the
  /// closure part of a bundle's file name.
  static String closureHash(String fingerprint) =>
      sha256.convert(utf8.encode(fingerprint)).toString().substring(0, 16);

  String _pathFor(String packageName, String key) => p.join(
    cacheDirectory,
    '${_sanitizeFilename(packageName)}@${_sanitizeFilename(key)}.sum',
  );

  /// Returns the cache file path for the SDK summary.
  ///
  /// Format: `<cache-dir>/sdk@{dart-version}.sum`
  String getSdkSummaryPath() => _pathFor('sdk', dartSdkVersion);

  /// Checks if a valid SDK summary exists in our cache.
  Future<bool> hasSdkSummary() => _isNonEmptyFile(getSdkSummaryPath());

  /// Sanitizes a string for use in a filename.
  String _sanitizeFilename(String name) {
    // Replace any characters that might be problematic in filenames
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  /// Checks if a valid summary exists for the package, linked against the
  /// closure [fingerprint] describes.
  ///
  /// A summary is considered valid if the file exists and is not empty: it is
  /// written complete through a rename, and toolchain compatibility is
  /// guaranteed *structurally* by the partition path and the closure by the
  /// file name (see the class dartdoc and [getCachePath]).
  Future<bool> hasSummary(
    String packageName,
    String version, {
    required String fingerprint,
  }) => _isNonEmptyFile(
    getCachePath(packageName, version, fingerprint: fingerprint),
  );

  Future<bool> _isNonEmptyFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return false;
    }
    return (await file.stat()).size != 0;
  }

  /// Marks the bundle at [path] as used now (its modification time), so that
  /// `analyzer_cache_gc clean` keeps it: a bundle a run loads is never
  /// swept with those no run has used for longer than the cutoff. A bundle
  /// that cannot be touched (gone, read-only) is left as it is.
  Future<void> markUsed(String path) async {
    try {
      await File(path).setLastModified(DateTime.now());
    } on FileSystemException {
      // Only the sweep's view of it is affected.
    }
  }

  /// Checks which dependencies are missing from the cache.
  ///
  /// Returns a list of dependencies that don't have valid cached summaries.
  ///
  /// [fingerprints] holds each package's closure fingerprint by name (see
  /// SummaryGenerator.computeDependencyFingerprints).
  Future<List<PackageDependency>> findMissingSummaries(
    List<PackageDependency> dependencies, {
    required Map<String, String> fingerprints,
  }) async {
    final missing = <PackageDependency>[];

    for (final dep in dependencies) {
      if (!dep.isCacheable) continue;

      if (!await hasSummary(
        dep.name,
        dep.version,
        fingerprint: fingerprints[dep.name] ?? '',
      )) {
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
    String version, {
    required String fingerprint,
  }) async {
    final path = getCachePath(packageName, version, fingerprint: fingerprint);
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
  /// [fingerprints] holds each package's closure fingerprint by name.
  Future<SummaryDataStore> loadSummaries(
    List<PackageDependency> dependencies, {
    required Map<String, String> fingerprints,
  }) async {
    final store = SummaryDataStore();

    for (final dep in dependencies) {
      if (!dep.isCacheable) continue;

      final fingerprint = fingerprints[dep.name] ?? '';
      final bundle = await loadSummary(
        dep.name,
        dep.version,
        fingerprint: fingerprint,
      );
      if (bundle != null) {
        final path = getCachePath(
          dep.name,
          dep.version,
          fingerprint: fingerprint,
        );
        store.addBundle(path, bundle);
      }
    }

    return store;
  }

  /// Writes a summary for a package, linked against the closure
  /// [fingerprint] describes.
  ///
  /// Creates the cache directory if it doesn't exist. A summary already there
  /// under the same name (one of the same closure, built by another run) is
  /// replaced by an identical one through a rename, so a reader sees one
  /// complete file or the other.
  Future<void> writeSummary(
    String packageName,
    String version,
    Uint8List bytes, {
    required String fingerprint,
  }) => _writeAtomically(
    getCachePath(packageName, version, fingerprint: fingerprint),
    bytes,
  );

  /// Writes the SDK summary ([getSdkSummaryPath]).
  Future<void> writeSdkSummary(Uint8List bytes) =>
      _writeAtomically(getSdkSummaryPath(), bytes);

  Future<void> _writeAtomically(String path, Uint8List bytes) async {
    await ensureCacheDirectory();

    // Write atomically through a temp file of this writer's own.
    final tempFile = File(_tempPathFor(path));

    try {
      await tempFile.writeAsBytes(bytes, flush: true);
      await tempFile.rename(path);
    } catch (e) {
      // Clean up temp file on failure
      await _safeDelete(tempFile);
      rethrow;
    }
  }

  /// A temp file name for [path] no other writer uses: processes and
  /// isolates populating one partition at once each write their own and
  /// rename it into place. A name shared by all of them (`<path>.tmp`) let
  /// one writer truncate the file another had just finished and was renaming.
  static String _tempPathFor(String path) =>
      '$path.$pid-${_random.nextInt(1 << 32).toRadixString(16)}.tmp';

  static final Random _random = Random.secure();

  /// Ensures the cache directory exists.
  Future<void> ensureCacheDirectory() async {
    final dir = Directory(cacheDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Lists all cached summaries.
  ///
  /// Returns a map of `package@version+closure-hash` (`sdk@<dart-version>` for
  /// the SDK summary) -> file path.
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

  /// Deletes every file of this partition: what `--rebuild-cache` asks for.
  ///
  /// Unlike every other path through the cache this deletes bundles another
  /// run may be linking against; it is only done on request.
  Future<void> clearCache() async {
    final dir = Directory(cacheDirectory);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) {
          await _safeDelete(entity);
        }
      }
    }
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
