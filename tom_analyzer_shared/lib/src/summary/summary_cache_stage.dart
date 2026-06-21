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

  const SummaryCacheResult({
    this.summaryPaths,
    this.sdkSummaryPath,
  });

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
}) async {
  final out = log ?? print;
  final cacheManager = SummaryCacheManager(projectRoot);
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
  out('Found ${dependencies.length} dependencies '
      '(${cacheable.length} cacheable).');

  if (cacheOnlyPackages.isNotEmpty) {
    cacheable = cacheable
        .where((d) => cacheOnlyPackages.contains(d.name))
        .toList();
    if (verbose) {
      out('Filtering to ${cacheable.length} packages: '
          '${cacheOnlyPackages.join(', ')}');
    }
  }

  if (showCacheStatus) {
    await _printCacheStatus(cacheManager, cacheable, out);
    return null;
  }

  if (cacheable.isEmpty) {
    out('No cacheable dependencies found.');
    return null;
  }

  if (rebuildCache) {
    out('Clearing summary cache...');
    await cacheManager.clearCache();
  }

  final generator = SummaryGenerator(
    cacheManager: cacheManager,
    dependencyResolver: depResolver,
  );

  // SDK summary first — package summaries resolve `dart:core` and
  // (when Flutter is on the path) `dart:ui` from it.
  await generator.generateSdkSummary();

  final sdkSummaryPath = cacheManager.getSdkSummaryPath();
  final hasSdkSummary = await File(sdkSummaryPath).exists();

  final missing = await cacheManager.findMissingSummaries(cacheable);

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

  final summaryPaths = <String>[];
  for (final dep in cacheable) {
    final cachePath = cacheManager.getCachePath(dep.name, dep.version);
    if (await File(cachePath).exists()) {
      summaryPaths.add(cachePath);
    }
  }

  if (summaryPaths.isEmpty && !hasSdkSummary) {
    return null;
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
  out('  Total cached: ${stats.summaryCount} files '
      '(${_formatBytes(stats.totalSizeBytes)})');
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
  out('  Summary: $cached cached, $missing missing, '
      '${cacheable.length} total cacheable');
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
