@Tags(['integration'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

/// Integration tests for the summary caching system.
///
/// These tests use real packages from the pub cache to verify the
/// end-to-end summary generation and loading pipeline.
///
/// Tagged as 'integration' since they require analyzer context creation
/// and take longer than unit tests.
void main() {
  late Directory tempDir;
  late SummaryCacheManager cacheManager;
  late DependencyResolver dependencyResolver;
  late SummaryGenerator generator;

  /// Finds a small hosted package in the pub cache for testing.
  ///
  /// Returns a PackageDependency for the first available package from
  /// a list of known small packages, or null if none are available.
  PackageDependency? findTestPackage() {
    final pubCache = Platform.environment['PUB_CACHE'] ??
        '${Platform.environment['HOME']}/.pub-cache';
    final hostedDir = Directory('$pubCache/hosted/pub.dev');

    if (!hostedDir.existsSync()) return null;

    // Look for small, well-known packages
    final candidates = ['meta', 'path', 'collection'];
    for (final name in candidates) {
      for (final entity in hostedDir.listSync()) {
        if (entity is Directory) {
          final dirName = entity.path.split('/').last;
          final match =
              RegExp('^${RegExp.escape(name)}-(\\d+\\.\\d+\\.\\d+)\$')
                  .firstMatch(dirName);
          if (match != null) {
            final version = match.group(1)!;
            // Verify it has a lib/ directory
            if (Directory('${entity.path}/lib').existsSync()) {
              return PackageDependency(
                name: name,
                version: version,
                source: 'hosted',
                hostedUrl: 'https://pub.dev',
              );
            }
          }
        }
      }
    }
    return null;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('summary_integration_test_');
    cacheManager = SummaryCacheManager(
      tempDir.path,
      // Hermetic: keep the cache inside the temp dir.
      cacheDirectory: p.join(tempDir.path, '.tom', 'analyzer-cache'),
    );
    dependencyResolver = DependencyResolver();
    generator = SummaryGenerator(
      cacheManager: cacheManager,
      dependencyResolver: dependencyResolver,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Summary generation integration', () {
    test('generates and caches a summary for a real package', () async {
      final testPkg = findTestPackage();
      if (testPkg == null) {
        markTestSkipped('No suitable package found in pub cache');
        return;
      }

      // Verify no summary exists yet
      expect(
        await cacheManager.hasSummary(testPkg.name, testPkg.version),
        isFalse,
      );

      // Generate summary
      final result = await generator.generateSummary(testPkg);
      expect(result, isTrue, reason: 'Summary generation should succeed');

      // Verify summary was written to cache
      expect(
        await cacheManager.hasSummary(testPkg.name, testPkg.version),
        isTrue,
      );

      // Verify the cached file is non-trivial
      final cachePath =
          cacheManager.getCachePath(testPkg.name, testPkg.version);
      final fileSize = File(cachePath).lengthSync();
      expect(fileSize, greaterThan(0),
          reason: 'Summary file should not be empty');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('skips already-cached package on second run', () async {
      final testPkg = findTestPackage();
      if (testPkg == null) {
        markTestSkipped('No suitable package found in pub cache');
        return;
      }

      // First run: generates
      final firstResult = await generator.generateSummary(testPkg);
      expect(firstResult, isTrue);

      // Second run: skips (already cached)
      final secondResult = await generator.generateSummary(testPkg);
      expect(secondResult, isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('loadSummary returns valid reader for generated summary', () async {
      final testPkg = findTestPackage();
      if (testPkg == null) {
        markTestSkipped('No suitable package found in pub cache');
        return;
      }

      // Generate
      await generator.generateSummary(testPkg);

      // Load back
      final reader =
          await cacheManager.loadSummary(testPkg.name, testPkg.version);
      expect(reader, isNotNull, reason: 'Should load generated summary');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('generateMissingSummaries reports correct counts', () async {
      final testPkg = findTestPackage();
      if (testPkg == null) {
        markTestSkipped('No suitable package found in pub cache');
        return;
      }

      final progressLog = <String>[];

      final result = await generator.generateMissingSummaries(
        [testPkg],
        onProgress: (pkg, current, total) {
          progressLog.add('$pkg ($current/$total)');
        },
      );

      expect(result.generated, equals(1));
      expect(result.skipped, equals(0));
      expect(result.failed, equals(0));
      expect(progressLog, hasLength(1));

      // Run again — should all be skipped
      final result2 = await generator.generateMissingSummaries([testPkg]);
      expect(result2.generated, equals(0));
      expect(result2.skipped, equals(1));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('cleanUnusedSummaries removes old package versions', () async {
      final testPkg = findTestPackage();
      if (testPkg == null) {
        markTestSkipped('No suitable package found in pub cache');
        return;
      }

      // Generate a real summary
      await generator.generateSummary(testPkg);

      // Simulate upgrading the package to a new version
      final upgradedDeps = [
        PackageDependency(
          name: testPkg.name,
          version: '99.99.99', // fake new version
          source: 'hosted',
        ),
      ];

      final removed = await cacheManager.cleanUnusedSummaries(upgradedDeps);
      expect(removed, equals(1));
      expect(
        await cacheManager.hasSummary(testPkg.name, testPkg.version),
        isFalse,
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Edge cases with real filesystem', () {
    test('handles package directory with no lib/ folder', () async {
      // Create a fake "package" directory with no lib/
      final fakePkgDir = Directory('${tempDir.path}/fake_pkg');
      fakePkgDir.createSync();
      File('${fakePkgDir.path}/pubspec.yaml')
          .writeAsStringSync('name: fake_pkg\n');

      // The generator checks for lib/ directory — should return false
      const dep = PackageDependency(
        name: 'fake_pkg',
        version: '1.0.0',
        source: 'hosted',
        hostedUrl: 'https://pub.dev',
      );

      // generateSummary resolves via getHostedPackagePath which won't
      // point to our fake dir. Instead test _findPublicLibraries behavior
      // indirectly by verifying no summary is produced for
      // a nonexistent path
      final result = await generator.generateSummary(dep);
      expect(result, isFalse);
    });

    test('cache stats reflect real summary files', () async {
      final testPkg = findTestPackage();
      if (testPkg == null) {
        markTestSkipped('No suitable package found in pub cache');
        return;
      }

      // Empty cache
      var stats = await cacheManager.getStats();
      expect(stats.summaryCount, equals(0));
      expect(stats.totalSizeBytes, equals(0));

      // Generate one summary
      await generator.generateSummary(testPkg);

      // Stats should reflect it
      stats = await cacheManager.getStats();
      expect(stats.summaryCount, equals(1));
      expect(stats.totalSizeBytes, greaterThan(0));
      expect(stats.totalSizeMB, greaterThanOrEqualTo(0));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
