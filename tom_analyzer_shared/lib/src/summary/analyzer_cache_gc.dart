// Copyright (c) 2026. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Opt-in garbage collection for the shared analyzer summary cache.
///
/// The cache is partitioned by `<analyzer-major>/<dart-sdk-version>` (see
/// [SummaryCacheManager]), which makes it self-freshening: a toolchain change
/// simply starts from a fresh, empty partition. The acknowledged cost is that
/// *retired* partitions — from a Dart SDK or analyzer major the machine no
/// longer uses — are never reclaimed and linger on disk forever. There is
/// deliberately no automatic pruning, because the cache is shared across every
/// project and tool on the machine and a background collector cannot safely
/// know a partition is truly dead (another checkout pinned to an older SDK
/// might still need it).
///
/// [AnalyzerCacheGarbageCollector] is the *deliberate*, human/CI-driven
/// reclaimer: it enumerates the partitions with their last-used time and size,
/// and deletes those older than a caller-supplied cutoff — never touching the
/// live partition unless explicitly told to.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../cache/tool_cache_locator.dart';
import 'analyzer_version.dart';

/// Sub-directory of the shared tool cache that holds analyzer summaries.
///
/// Kept in sync with the private constant of the same purpose in
/// `summary_cache_manager.dart`; both describe the single
/// `<tool-cache>/analyzer-cache/` root.
const String _analyzerCacheSubDir = 'analyzer-cache';

/// One `<analyzer-major>/<dart-sdk-version>` partition in the shared cache.
///
/// A partition is the leaf directory that actually holds `.sum` bundles and
/// their `.sum.deps` fingerprint sidecars for a single toolchain identity.
class AnalyzerCachePartition {
  /// The analyzer major version segment of the partition path.
  final int analyzerMajor;

  /// The Dart SDK version segment of the partition path.
  final String dartSdkVersion;

  /// Absolute path of the partition directory.
  final String path;

  /// The most recent modification time among the partition's files.
  ///
  /// A partition is only written to when its toolchain is active (bundles are
  /// generated on cache miss), so the newest file mtime is a reliable proxy for
  /// "last used". Falls back to the directory's own mtime when it is empty.
  final DateTime lastUsed;

  /// Total size on disk of the partition's files, in bytes.
  final int sizeBytes;

  /// Number of `.sum` bundles in the partition.
  final int summaryCount;

  const AnalyzerCachePartition({
    required this.analyzerMajor,
    required this.dartSdkVersion,
    required this.path,
    required this.lastUsed,
    required this.sizeBytes,
    required this.summaryCount,
  });

  /// Stable `"<analyzer-major>/<dart-sdk-version>"` identity.
  ///
  /// Used to protect the live partition from collection (the caller passes the
  /// current toolchain's key in `keep`).
  String get key => '$analyzerMajor/$dartSdkVersion';

  /// Total size in mebibytes.
  double get sizeMB => sizeBytes / (1024 * 1024);

  /// How long ago this partition was last used, measured from [now].
  Duration ageFrom(DateTime now) => now.difference(lastUsed);

  @override
  String toString() =>
      'AnalyzerCachePartition($key, $summaryCount summaries, '
      '${sizeMB.toStringAsFixed(2)} MB, lastUsed: '
      '${lastUsed.toIso8601String()})';
}

/// Opt-in garbage collector for orphaned analyzer-cache partitions.
///
/// Operates at the `analyzer-cache` root (the parent of the per-toolchain
/// `<major>/<sdk>` partitions), so it can enumerate and prune sibling
/// partitions the running toolchain does not use.
class AnalyzerCacheGarbageCollector {
  /// The `analyzer-cache` root directory holding `<major>/<sdk>` partitions.
  final String cacheRoot;

  /// Creates a collector rooted at an explicit `analyzer-cache` directory.
  ///
  /// Prefer [AnalyzerCacheGarbageCollector.resolve] outside of tests; this
  /// constructor exists so callers (and tests) can point at a fixed root.
  AnalyzerCacheGarbageCollector(this.cacheRoot);

  /// Resolves the shared `analyzer-cache` root via [ToolCacheLocator].
  ///
  /// [startDirectory] seeds the ancestor search (defaults to the current
  /// directory); [environment] overrides the process environment consulted by
  /// [ToolCacheLocator] (primarily for tests).
  factory AnalyzerCacheGarbageCollector.resolve({
    String? startDirectory,
    Map<String, String>? environment,
  }) {
    final root = p.join(
      ToolCacheLocator.resolve(
        startDirectory: startDirectory ?? Directory.current.path,
        environment: environment,
      ),
      _analyzerCacheSubDir,
    );
    return AnalyzerCacheGarbageCollector(root);
  }

  /// The `"<analyzer-major>/<dart-sdk-version>"` key of the partition the
  /// *current* toolchain uses.
  ///
  /// Pass this to [collect]'s `keep` set to protect the live partition. The
  /// segments default to the running toolchain ([analyzerMajorVersion] and
  /// [currentDartSdkVersion]); overridable for tests.
  static String currentPartitionKey({
    int? analyzerMajor,
    String? dartSdkVersion,
  }) {
    final major = analyzerMajor ?? analyzerMajorVersion;
    final sdk = dartSdkVersion ?? currentDartSdkVersion();
    return '$major/$sdk';
  }

  /// Enumerates all `<major>/<sdk>` partitions under [cacheRoot].
  ///
  /// Returns an empty list when the root does not exist. Stray entries that do
  /// not match the layout (files directly under the root, or `<major>`
  /// directories whose name is not an integer) are ignored so an unexpected
  /// filesystem entry never derails the sweep. The result is sorted oldest
  /// [AnalyzerCachePartition.lastUsed] first.
  Future<List<AnalyzerCachePartition>> listPartitions() async {
    final root = Directory(cacheRoot);
    if (!await root.exists()) return const [];

    final partitions = <AnalyzerCachePartition>[];
    await for (final majorEntity in root.list(followLinks: false)) {
      if (majorEntity is! Directory) continue;
      final major = int.tryParse(p.basename(majorEntity.path));
      if (major == null) continue;

      await for (final sdkEntity in majorEntity.list(followLinks: false)) {
        if (sdkEntity is! Directory) continue;
        partitions.add(
          await _describePartition(
            major,
            p.basename(sdkEntity.path),
            sdkEntity.path,
          ),
        );
      }
    }

    partitions.sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    return partitions;
  }

  Future<AnalyzerCachePartition> _describePartition(
    int major,
    String sdk,
    String dirPath,
  ) async {
    final dir = Directory(dirPath);
    var sizeBytes = 0;
    var summaryCount = 0;
    DateTime? newest;

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      sizeBytes += stat.size;
      if (entity.path.endsWith('.sum')) summaryCount++;
      if (newest == null || stat.modified.isAfter(newest)) {
        newest = stat.modified;
      }
    }

    // Empty partition: fall back to the directory's own mtime.
    newest ??= (await dir.stat()).modified;

    return AnalyzerCachePartition(
      analyzerMajor: major,
      dartSdkVersion: sdk,
      path: dirPath,
      lastUsed: newest,
      sizeBytes: sizeBytes,
      summaryCount: summaryCount,
    );
  }

  /// Pure selection of the partitions eligible for collection.
  ///
  /// A partition is selected when its [AnalyzerCachePartition.lastUsed] is
  /// strictly before [cutoff] (the boundary is exclusive) and its
  /// [AnalyzerCachePartition.key] is not in [keep]. Separated from the
  /// filesystem side-effects in [collect] so the policy is unit-testable
  /// without touching disk.
  static List<AnalyzerCachePartition> selectForCollection(
    List<AnalyzerCachePartition> partitions, {
    required DateTime cutoff,
    Set<String> keep = const {},
  }) {
    return [
      for (final part in partitions)
        if (!keep.contains(part.key) && part.lastUsed.isBefore(cutoff)) part,
    ];
  }

  /// Deletes partitions last used before [cutoff], returning those removed.
  ///
  /// Partitions whose [AnalyzerCachePartition.key] is in [keep] are never
  /// deleted — pass [currentPartitionKey] to protect the live partition. When
  /// [dryRun] is true the eligible partitions are returned without any
  /// filesystem change, so a caller can preview a sweep.
  Future<List<AnalyzerCachePartition>> collect({
    required DateTime cutoff,
    Set<String> keep = const {},
    bool dryRun = false,
  }) async {
    final partitions = await listPartitions();
    final doomed = selectForCollection(partitions, cutoff: cutoff, keep: keep);
    if (!dryRun) {
      for (final part in doomed) {
        final dir = Directory(part.path);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    }
    return doomed;
  }
}
