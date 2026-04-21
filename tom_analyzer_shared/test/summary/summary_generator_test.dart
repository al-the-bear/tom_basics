import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

void main() {
  late Directory tempDir;
  late SummaryCacheManager cacheManager;
  late DependencyResolver dependencyResolver;
  late SummaryGenerator generator;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('summary_gen_test_');
    cacheManager = SummaryCacheManager(
      tempDir.path,
      dartSdkVersion: '3.10.4',
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

  group('SummaryGenerator', () {
    group('generateSummary', () {
      test('returns false for non-cacheable dependency', () async {
        const dep = PackageDependency(
          name: 'local',
          version: '1.0.0',
          source: 'path',
          path: '/some/path',
        );

        final result = await generator.generateSummary(dep);
        expect(result, isFalse);
      });

      test('returns false when summary already cached', () async {
        // Pre-populate the cache
        await cacheManager.writeSummary(
          'cached_pkg',
          '1.0.0',
          Uint8List.fromList([1, 2, 3, 4]),
        );

        const dep = PackageDependency(
          name: 'cached_pkg',
          version: '1.0.0',
          source: 'hosted',
        );

        final result = await generator.generateSummary(dep);
        expect(result, isFalse);
      });

      test('returns false for package without public libraries', () async {
        // A hosted package that resolves to a path but has no lib/ directory
        // getHostedPackagePath constructs a path regardless of existence
        const dep = PackageDependency(
          name: 'nonexistent_pkg_xyz_abc',
          version: '99.99.99',
          source: 'hosted',
          hostedUrl: 'https://pub.dev',
        );

        final result = await generator.generateSummary(dep);
        expect(result, isFalse);
      });

      test('throws for SDK package without resolvable path', () async {
        // SDK packages require running flutter sdk-path, which may return null
        const dep = PackageDependency(
          name: 'nonexistent_sdk_pkg',
          version: '0.0.0',
          source: 'sdk',
          sdkName: 'nonexistent_sdk',
        );

        // getSdkPackagePath returns null for unknown SDKs
        // generateSummary throws StateError when path is null
        expect(
          () => generator.generateSummary(dep),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('generateMissingSummaries', () {
      test('returns all skipped for non-cacheable deps', () async {
        final deps = [
          const PackageDependency(
              name: 'local', version: '1.0.0', source: 'path'),
          const PackageDependency(
              name: 'remote', version: '1.0.0', source: 'git'),
        ];

        final result = await generator.generateMissingSummaries(deps);
        expect(result.generated, equals(0));
        expect(result.skipped, equals(0));
        expect(result.failed, equals(0));
        expect(result.total, equals(0));
      });

      test('skips already-cached packages', () async {
        await cacheManager.writeSummary(
          'cached',
          '1.0.0',
          Uint8List.fromList([1, 2, 3]),
        );

        final deps = [
          const PackageDependency(
              name: 'cached', version: '1.0.0', source: 'hosted'),
        ];

        final result = await generator.generateMissingSummaries(deps);
        expect(result.skipped, equals(1));
        expect(result.generated, equals(0));
        expect(result.failed, equals(0));
      });

      test('skips hosted package without public libraries', () async {
        // getHostedPackagePath returns a path, but the package doesn't exist
        // on disk, so no public libraries are found and it's skipped
        final deps = [
          const PackageDependency(
            name: 'nonexistent_xyz',
            version: '99.0.0',
            source: 'hosted',
            hostedUrl: 'https://pub.dev',
          ),
        ];

        final result = await generator.generateMissingSummaries(deps);
        expect(result.skipped, equals(1));
        expect(result.generated, equals(0));
        expect(result.failed, equals(0));
      });

      test('calls progress callback', () async {
        await cacheManager.writeSummary(
          'a', '1.0.0', Uint8List.fromList([1]));

        final deps = [
          const PackageDependency(
              name: 'a', version: '1.0.0', source: 'hosted'),
        ];

        final progress = <String>[];
        await generator.generateMissingSummaries(
          deps,
          onProgress: (pkg, current, total) {
            progress.add('$pkg:$current/$total');
          },
        );

        expect(progress, hasLength(1));
        expect(progress.first, equals('a:1/1'));
      });

      test('handles mixed cached and missing packages', () async {
        // Pre-cache one package
        await cacheManager.writeSummary(
          'cached_a',
          '1.0.0',
          Uint8List.fromList([1, 2]),
        );

        final deps = [
          const PackageDependency(
            name: 'cached_a',
            version: '1.0.0',
            source: 'hosted',
          ),
          const PackageDependency(
            name: 'missing_xyz',
            version: '99.0.0',
            source: 'hosted',
            hostedUrl: 'https://pub.dev',
          ),
        ];

        final result = await generator.generateMissingSummaries(deps);
        // cached_a: hasSummary=true → skipped
        // missing_xyz: hasSummary=false → generateSummary returns false (no libs) → skipped
        expect(result.skipped, equals(2));
        expect(result.generated, equals(0));
      });

      test('processes packages independently (no circular dependency issue)',
          () async {
        // Packages that might depend on each other in reality are each
        // analyzed independently — each gets its own AnalysisContextCollection.
        // This means circular transitive dependencies between packages
        // can't cause infinite loops during summary generation.
        final deps = [
          const PackageDependency(
            name: 'nonexistent_a',
            version: '1.0.0',
            source: 'hosted',
            hostedUrl: 'https://pub.dev',
          ),
          const PackageDependency(
            name: 'nonexistent_b',
            version: '1.0.0',
            source: 'hosted',
            hostedUrl: 'https://pub.dev',
          ),
        ];

        // Should complete without hanging — each package is processed
        // sequentially and independently
        final result = await generator.generateMissingSummaries(deps);
        expect(result.total, equals(2));
      });
    });
  });

  group('SummaryGenerationResult', () {
    test('total sums generated, skipped, and failed', () {
      const result = SummaryGenerationResult(
        generated: 3,
        skipped: 5,
        failed: 2,
        errors: {},
      );
      expect(result.total, equals(10));
    });

    test('toString includes counts', () {
      const result = SummaryGenerationResult(
        generated: 1,
        skipped: 2,
        failed: 0,
        errors: {},
      );
      final str = result.toString();
      expect(str, contains('generated: 1'));
      expect(str, contains('skipped: 2'));
      expect(str, contains('failed: 0'));
    });
  });
}
