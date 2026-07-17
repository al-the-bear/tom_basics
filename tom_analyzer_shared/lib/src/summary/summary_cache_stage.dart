// Copyright (c) 2024-2026. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'dependency_resolver.dart';
import 'package_dependency.dart';
import 'summary_cache_manager.dart';
import 'summary_generator.dart';

/// Result of a summary-cache stage execution.
///
/// The two paths are meant to be passed directly to
/// `AnalysisContextCollectionImpl(..., sdkSummaryPath:
/// sdkSummaryPath, librarySummaryPaths: summaryPaths ?? const [])`.
class SummaryCacheResult {
  /// Paths of cached package summaries (one `.sum` per hosted/SDK package).
  ///
  /// `null` means no package summaries are available. An empty list is
  /// never returned — callers receive either a non-empty list or `null`.
  final List<String>? summaryPaths;

  /// Path of the cached Dart-SDK summary (possibly including
  /// `dart:ui` via the Flutter embedder). `null` when no SDK summary
  /// could be generated or found.
  final String? sdkSummaryPath;

  const SummaryCacheResult({this.summaryPaths, this.sdkSummaryPath});

  /// Whether this result carries any usable summary at all.
  bool get isEmpty => summaryPaths == null && sdkSummaryPath == null;
}

/// Runs the summary-cache stage for a project.
///
/// Resolves dependencies from `pubspec.lock`, generates any missing SDK
/// and package summaries into the shared tool cache's `analyzer-cache/`
/// sub-directory (resolved by [ToolCacheLocator] from [projectRoot]), and
/// returns the paths that should be passed to the analyzer so it can
/// skip re-scanning stable dependencies.
///
/// Behaviour matches the private `_runSummaryCacheStage` previously
/// embedded in the reflection-generator CLI runner:
///
/// * When [rebuildCache] is `true` the cache directory is cleared
///   first.
/// * When [showCacheStatus] is `true` the current cache contents are
///   printed to stdout and `null` is returned (so the caller can exit
///   without triggering any heavy analysis).
/// * When [cacheOnlyPackages] is non-empty, only those packages are
///   considered — useful for targeted rebuilds.
/// * [log] defaults to `print`; pass a sink to redirect output.
/// * [cacheManager] overrides the default shared-cache manager — used by
///   tests to keep the cache hermetic (a fixed temp directory) instead of
///   writing into the workspace-resolved shared tool cache.
///
/// Returns `null` when no dependencies could be resolved or no
/// summaries are available. Otherwise returns a [SummaryCacheResult]
/// with whichever summaries exist on disk after the stage ran.
Future<SummaryCacheResult?> runSummaryCacheStage(
  String projectRoot, {
  bool verbose = false,
  bool rebuildCache = false,
  bool showCacheStatus = false,
  List<String> cacheOnlyPackages = const [],
  void Function(String message)? log,
  SummaryCacheManager? cacheManager,
}) async {
  final out = log ?? print;
  final cache = cacheManager ?? SummaryCacheManager(projectRoot);
  final depResolver = DependencyResolver();

  out('Resolving dependencies for summary caching...');
  List<PackageDependency> dependencies;
  try {
    dependencies = await depResolver.resolveVersionedDependencies(projectRoot);
  } catch (e) {
    out('Warning: Could not resolve dependencies for summary caching: $e');
    return null;
  }

  var cacheable = dependencies.where((d) => d.isCacheable).toList();
  out(
    'Found ${dependencies.length} dependencies '
    '(${cacheable.length} cacheable).',
  );

  if (cacheOnlyPackages.isNotEmpty) {
    cacheable = cacheable
        .where((d) => cacheOnlyPackages.contains(d.name))
        .toList();
    if (verbose) {
      out(
        'Filtering to ${cacheable.length} packages: '
        '${cacheOnlyPackages.join(', ')}',
      );
    }
  }

  if (showCacheStatus) {
    await _printCacheStatus(cache, cacheable, out);
    return null;
  }

  if (cacheable.isEmpty) {
    out('No cacheable dependencies found.');
    return null;
  }

  if (rebuildCache) {
    out('Clearing summary cache...');
    await cache.clearCache();
  }

  final generator = SummaryGenerator(
    cacheManager: cache,
    dependencyResolver: depResolver,
  );

  // SDK summary first — package summaries resolve `dart:core` and
  // (when Flutter is on the path) `dart:ui` from it.
  await generator.generateSdkSummary();

  final sdkSummaryPath = cache.getSdkSummaryPath();
  final hasSdkSummary = await File(sdkSummaryPath).exists();

  // Dependency-closure fingerprints. A summary keyed only by its own
  // `name@version` is silently stale when a *transitive* dependency changes
  // version (the classic case: `tom_crypto@1.0.0.sum` linked against
  // `tom_basics@1.0.0` after `tom_basics` moved to `1.0.1`). Compute the
  // expected closure fingerprint for every package, delete any cached bundle
  // whose recorded fingerprint no longer matches, and regenerate it against
  // the current graph. Bundles with no fingerprint sidecar (produced before
  // this mechanism existed) are treated as stale so the cache self-heals.
  final fingerprints = await generator.computeDependencyFingerprints(cacheable);

  var invalidated = 0;
  for (final dep in cacheable) {
    final expected = fingerprints[dep.name] ?? '';
    if (await cache.hasSummary(dep.name, dep.version) &&
        !await cache.isSummaryFresh(dep.name, dep.version, expected)) {
      await cache.deleteSummary(dep.name, dep.version);
      invalidated++;
    }
  }
  if (invalidated > 0) {
    out(
      'Invalidated $invalidated stale summaries (dependency version '
      'change); they will be regenerated.',
    );
  }

  final missing = await cache.findMissingSummaries(cacheable);

  if (missing.isNotEmpty) {
    out('Generating ${missing.length} missing summaries...');

    // Pass ALL cacheable deps so the topological sort sees the complete
    // dependency graph. Already-cached deps are skipped internally but
    // their paths are made available to subsequent generations.
    final result = await generator.generateMissingSummaries(
      cacheable,
      sdkSummaryPath: hasSdkSummary ? sdkSummaryPath : null,
      onProgress: (pkg, current, total) {
        out('  Generating summary ($current/$total): $pkg');
      },
    );

    if (result.generated > 0) {
      out('Generated ${result.generated} summaries.');
    }
    if (result.failed > 0) {
      out('Failed to generate ${result.failed} summaries.');
      if (verbose) {
        for (final entry in result.errors.entries) {
          out('  ${entry.key}: ${entry.value}');
        }
      }
    }
  } else {
    out('All ${cacheable.length} summaries are cached.');
  }

  // Record the dependency-closure fingerprint next to every present bundle so
  // the next run can detect a transitive version change. Idempotent overwrite.
  for (final dep in cacheable) {
    if (await cache.hasSummary(dep.name, dep.version)) {
      await cache.writeFingerprint(
        dep.name,
        dep.version,
        fingerprints[dep.name] ?? '',
      );
    }
  }

  // Load only fresh bundles. A summary whose regeneration failed above is
  // still stale — loading it would crash the analyzer with "Missing library",
  // so skip it and let the caller fall back to scanning that package's source.
  final summaryPaths = <String>[];
  for (final dep in cacheable) {
    final cachePath = cache.getCachePath(dep.name, dep.version);
    final expected = fingerprints[dep.name] ?? '';
    if (await cache.isSummaryFresh(dep.name, dep.version, expected)) {
      summaryPaths.add(cachePath);
      if (verbose) {
        // Per-summary trace so a run can be audited for actual cache use.
        out('  using ${dep.name}@${dep.version}.sum from cache at $cachePath');
      }
    } else if (await File(cachePath).exists()) {
      out(
        '  Warning: skipping stale summary ${dep.name}@${dep.version} '
        '(could not be refreshed for the current dependency graph).',
      );
    }
  }

  if (summaryPaths.isEmpty && !hasSdkSummary) {
    return null;
  }

  if (hasSdkSummary && verbose) {
    out('  using SDK summary from cache at $sdkSummaryPath');
  }

  out('Loading ${summaryPaths.length} cached summaries.');

  return SummaryCacheResult(
    summaryPaths: summaryPaths.isEmpty ? null : summaryPaths,
    sdkSummaryPath: hasSdkSummary ? sdkSummaryPath : null,
  );
}

Future<void> _printCacheStatus(
  SummaryCacheManager cacheManager,
  List<PackageDependency> cacheable,
  void Function(String) out,
) async {
  final stats = await cacheManager.getStats();
  out('Summary Cache Status:');
  out('  Cache directory: ${cacheManager.cacheDirectory}');
  out(
    '  Total cached: ${stats.summaryCount} files '
    '(${_formatBytes(stats.totalSizeBytes)})',
  );
  out('  Dart SDK version: ${cacheManager.dartSdkVersion}');
  out('');

  var cached = 0;
  var missing = 0;

  for (final dep in cacheable) {
    final hasSummary = await cacheManager.hasSummary(dep.name, dep.version);
    final status = hasSummary ? 'CACHED' : 'MISSING';
    if (hasSummary) {
      cached++;
    } else {
      missing++;
    }
    out('  [$status] ${dep.name}@${dep.version} (${dep.source})');
  }

  out('');
  out(
    '  Summary: $cached cached, $missing missing, '
    '${cacheable.length} total cacheable',
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
