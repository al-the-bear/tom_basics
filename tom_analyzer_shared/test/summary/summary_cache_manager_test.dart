import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

void main() {
  late Directory tempDir;
  late SummaryCacheManager cacheManager;

  /// Builds a cache manager whose shared tool-cache root is pinned inside
  /// [root] (via `TOM_TOOL_CACHE`), so the suite stays hermetic while still
  /// exercising the *default* resolution — including the analyzer-major
  /// partition segment that only the default path appends. Passing an explicit
  /// `cacheDirectory` would bypass that resolution and drop the segment, which
  /// the analyzer-major partitioning tests depend on.
  SummaryCacheManager makeCacheManager(
    String root, {
    int? analyzerMajor,
    String? dartSdkVersion,
  }) {
    return SummaryCacheManager(
      root,
      dartSdkVersion: dartSdkVersion,
      analyzerMajor: analyzerMajor,
      environment: {'TOM_TOOL_CACHE': p.join(root, '.tom', 'tom_tool_cache')},
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('summary_cache_test_');
    cacheManager = makeCacheManager(tempDir.path, dartSdkVersion: '3.10.4');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SummaryCacheManager', () {
    group('getCachePath', () {
      test('returns correct path for package@version', () {
        final path = cacheManager.getCachePath('provider', '6.1.2');
        expect(path, endsWith('provider@6.1.2.sum'));
        expect(path, contains('.tom'));
        expect(path, contains('analyzer-cache'));
      });

      test('sanitizes special characters in package name', () {
        final path = cacheManager.getCachePath('my:pkg', '1.0.0');
        expect(path, contains('my_pkg@1.0.0.sum'));
      });

      test('sanitizes special characters in version', () {
        final path = cacheManager.getCachePath('pkg', '1.0.0+1');
        // '+' is not in the sanitize regex, so it stays
        expect(path, endsWith('.sum'));
      });
    });

    group('analyzer-major partitioning', () {
      test('cache directory is nested under the analyzer major and SDK version',
          () {
        // Default major comes from analyzerMajorVersion (the analyzer this
        // package is built against); the innermost segment is the Dart SDK
        // version, which tracks the toolchain (see the SDK-version
        // partitioning group below for why).
        expect(
          cacheManager.cacheDirectory,
          endsWith(p.join('analyzer-cache', '$analyzerMajorVersion', '3.10.4')),
        );
        expect(cacheManager.analyzerMajor, equals(analyzerMajorVersion));
      });

      test('different analyzer majors resolve to different cache dirs', () {
        // This is the poison-prevention property: a tool running analyzer 8
        // and one running analyzer 10 must never share a `.sum` file, because
        // the bundle binary format is analyzer-major-specific.
        final manager8 = makeCacheManager(tempDir.path, analyzerMajor: 8);
        final manager10 = makeCacheManager(tempDir.path, analyzerMajor: 10);

        expect(
          manager8.cacheDirectory,
          isNot(equals(manager10.cacheDirectory)),
        );
        expect(
          manager8.getCachePath('async', '2.13.0'),
          isNot(equals(manager10.getCachePath('async', '2.13.0'))),
        );
        expect(
          manager8.cacheDirectory,
          contains(p.join('analyzer-cache', '8')),
        );
        expect(
          manager10.cacheDirectory,
          contains(p.join('analyzer-cache', '10')),
        );
      });

      test('same analyzer major resolves to the same cache dir', () {
        final a = makeCacheManager(tempDir.path, analyzerMajor: 10);
        final b = makeCacheManager(tempDir.path, analyzerMajor: 10);
        expect(
          a.getCachePath('pkg', '1.0.0'),
          equals(b.getCachePath('pkg', '1.0.0')),
        );
      });

      test('writes from one major are invisible to another major', () async {
        final manager8 = makeCacheManager(tempDir.path, analyzerMajor: 8);
        final manager10 = makeCacheManager(tempDir.path, analyzerMajor: 10);

        await manager8.writeSummary(
            'async', '2.13.0', Uint8List.fromList([1, 2, 3]));

        // The analyzer-10 partition must not see the analyzer-8 bundle.
        expect(await manager10.hasSummary('async', '2.13.0'), isFalse);
        expect(await manager8.hasSummary('async', '2.13.0'), isTrue);
      });
    });

    group('hasSummary', () {
      test('returns false when no file exists', () async {
        final result = await cacheManager.hasSummary('nonexistent', '1.0.0');
        expect(result, isFalse);
      });

      test('returns false when file is empty', () async {
        await cacheManager.ensureCacheDirectory();
        final path = cacheManager.getCachePath('empty', '1.0.0');
        File(path).writeAsBytesSync(Uint8List(0));

        final result = await cacheManager.hasSummary('empty', '1.0.0');
        expect(result, isFalse);
      });

      test('returns true when valid file exists', () async {
        await cacheManager.ensureCacheDirectory();
        final path = cacheManager.getCachePath('valid', '1.0.0');
        File(path).writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));

        final result = await cacheManager.hasSummary('valid', '1.0.0');
        expect(result, isTrue);
      });
    });

    group('writeSummary', () {
      test('creates cache directory and writes file', () async {
        final bytes = Uint8List.fromList([10, 20, 30, 40]);
        await cacheManager.writeSummary('test_pkg', '2.0.0', bytes);

        final path = cacheManager.getCachePath('test_pkg', '2.0.0');
        final file = File(path);
        expect(file.existsSync(), isTrue);
        expect(file.readAsBytesSync(), equals(bytes));
      });

      test('overwrites existing file', () async {
        final bytes1 = Uint8List.fromList([1, 2, 3]);
        final bytes2 = Uint8List.fromList([4, 5, 6]);

        await cacheManager.writeSummary('pkg', '1.0.0', bytes1);
        await cacheManager.writeSummary('pkg', '1.0.0', bytes2);

        final path = cacheManager.getCachePath('pkg', '1.0.0');
        expect(File(path).readAsBytesSync(), equals(bytes2));
      });
    });

    group('findMissingSummaries', () {
      test('returns all cacheable deps when cache is empty', () async {
        final deps = [
          const PackageDependency(
              name: 'a', version: '1.0.0', source: 'hosted'),
          const PackageDependency(
              name: 'b', version: '2.0.0', source: 'hosted'),
          const PackageDependency(
              name: 'c', version: '3.0.0', source: 'path', path: '/some/path'),
        ];

        final missing = await cacheManager.findMissingSummaries(deps);
        expect(missing, hasLength(2));
        expect(missing.map((d) => d.name), containsAll(['a', 'b']));
      });

      test('excludes already cached packages', () async {
        await cacheManager.writeSummary(
            'a', '1.0.0', Uint8List.fromList([1, 2, 3]));

        final deps = [
          const PackageDependency(
              name: 'a', version: '1.0.0', source: 'hosted'),
          const PackageDependency(
              name: 'b', version: '2.0.0', source: 'hosted'),
        ];

        final missing = await cacheManager.findMissingSummaries(deps);
        expect(missing, hasLength(1));
        expect(missing.first.name, equals('b'));
      });

      test('skips non-cacheable dependencies', () async {
        final deps = [
          const PackageDependency(
              name: 'local', version: '1.0.0', source: 'path', path: '/p'),
          const PackageDependency(
              name: 'remote', version: '1.0.0', source: 'git'),
        ];

        final missing = await cacheManager.findMissingSummaries(deps);
        expect(missing, isEmpty);
      });
    });

    group('listCachedSummaries', () {
      test('returns empty map when no cache directory', () async {
        final summaries = await cacheManager.listCachedSummaries();
        expect(summaries, isEmpty);
      });

      test('lists all .sum files', () async {
        await cacheManager.writeSummary(
            'pkg_a', '1.0.0', Uint8List.fromList([1]));
        await cacheManager.writeSummary(
            'pkg_b', '2.0.0', Uint8List.fromList([2]));

        final summaries = await cacheManager.listCachedSummaries();
        expect(summaries, hasLength(2));
        expect(summaries.keys, containsAll(['pkg_a@1.0.0', 'pkg_b@2.0.0']));
      });

      test('ignores non-.sum files', () async {
        await cacheManager.ensureCacheDirectory();
        File('${cacheManager.cacheDirectory}/notes.txt')
            .writeAsStringSync('hello');
        await cacheManager.writeSummary(
            'real', '1.0.0', Uint8List.fromList([1]));

        final summaries = await cacheManager.listCachedSummaries();
        expect(summaries, hasLength(1));
        expect(summaries.keys.first, equals('real@1.0.0'));
      });
    });

    group('clearCache', () {
      test('removes all .sum files', () async {
        await cacheManager.writeSummary(
            'a', '1.0.0', Uint8List.fromList([1]));
        await cacheManager.writeSummary(
            'b', '2.0.0', Uint8List.fromList([2]));

        await cacheManager.clearCache();

        final summaries = await cacheManager.listCachedSummaries();
        expect(summaries, isEmpty);
      });

      test('no-op when cache directory does not exist', () async {
        // Should not throw
        await cacheManager.clearCache();
      });
    });

    group('cleanUnusedSummaries', () {
      test('removes summaries not in current dependencies', () async {
        await cacheManager.writeSummary(
            'old_pkg', '1.0.0', Uint8List.fromList([1]));
        await cacheManager.writeSummary(
            'current', '2.0.0', Uint8List.fromList([2]));

        final currentDeps = [
          const PackageDependency(
              name: 'current', version: '2.0.0', source: 'hosted'),
        ];

        final removed =
            await cacheManager.cleanUnusedSummaries(currentDeps);
        expect(removed, equals(1));

        final remaining = await cacheManager.listCachedSummaries();
        expect(remaining, hasLength(1));
        expect(remaining.keys.first, equals('current@2.0.0'));
      });

      test('removes old version when dependency upgraded', () async {
        await cacheManager.writeSummary(
            'pkg', '1.0.0', Uint8List.fromList([1]));
        await cacheManager.writeSummary(
            'pkg', '2.0.0', Uint8List.fromList([2]));

        final currentDeps = [
          const PackageDependency(
              name: 'pkg', version: '2.0.0', source: 'hosted'),
        ];

        final removed =
            await cacheManager.cleanUnusedSummaries(currentDeps);
        expect(removed, equals(1));

        final has1 = await cacheManager.hasSummary('pkg', '1.0.0');
        final has2 = await cacheManager.hasSummary('pkg', '2.0.0');
        expect(has1, isFalse);
        expect(has2, isTrue);
      });

      test('returns 0 when all summaries are current', () async {
        await cacheManager.writeSummary(
            'pkg', '1.0.0', Uint8List.fromList([1]));

        final currentDeps = [
          const PackageDependency(
              name: 'pkg', version: '1.0.0', source: 'hosted'),
        ];

        final removed =
            await cacheManager.cleanUnusedSummaries(currentDeps);
        expect(removed, equals(0));
      });
    });

    group('getStats', () {
      test('returns zero stats when cache is empty', () async {
        final stats = await cacheManager.getStats();
        expect(stats.summaryCount, equals(0));
        expect(stats.totalSizeBytes, equals(0));
      });

      test('returns correct counts and sizes', () async {
        final bytes4 = Uint8List.fromList([1, 2, 3, 4]);
        final bytes8 = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

        await cacheManager.writeSummary('a', '1.0.0', bytes4);
        await cacheManager.writeSummary('b', '2.0.0', bytes8);

        final stats = await cacheManager.getStats();
        expect(stats.summaryCount, equals(2));
        expect(stats.totalSizeBytes, equals(12));
        expect(stats.cacheDirectory, equals(cacheManager.cacheDirectory));
      });
    });

    group('loadSummary', () {
      test('returns null when file does not exist', () async {
        final result = await cacheManager.loadSummary('missing', '1.0.0');
        expect(result, isNull);
      });

      test('returns null and deletes corrupted file', () async {
        await cacheManager.ensureCacheDirectory();
        final path = cacheManager.getCachePath('corrupt', '1.0.0');
        // Write invalid bytes that aren't a valid summary bundle
        File(path).writeAsBytesSync(Uint8List.fromList([0xFF, 0xFF, 0xFF]));

        final result = await cacheManager.loadSummary('corrupt', '1.0.0');
        expect(result, isNull);
        // Corrupted file should be deleted
        expect(File(path).existsSync(), isFalse);
      });
    });

    group('ensureCacheDirectory', () {
      test('creates nested directories', () async {
        await cacheManager.ensureCacheDirectory();
        expect(Directory(cacheManager.cacheDirectory).existsSync(), isTrue);
      });

      test('is idempotent', () async {
        await cacheManager.ensureCacheDirectory();
        await cacheManager.ensureCacheDirectory();
        expect(Directory(cacheManager.cacheDirectory).existsSync(), isTrue);
      });
    });

    group('SDK version handling', () {
      test('accepts custom dart SDK version', () {
        final manager =
            makeCacheManager(tempDir.path, dartSdkVersion: '3.8.0');
        expect(manager.dartSdkVersion, equals('3.8.0'));
      });

      test('detects SDK version from Platform when not provided', () {
        final manager = makeCacheManager(tempDir.path);
        expect(
          manager.dartSdkVersion,
          matches(RegExp(r'^\d+\.\d+\.\d+$')),
        );
      });

      test('different SDK versions resolve to different cache paths', () {
        // Poison-prevention across a toolchain upgrade: the analyzer's binary
        // `.sum` format has no stability guarantee *within* an analyzer major,
        // so bundles written under one Dart SDK can crash the analyzer bundled
        // with the next SDK (observed: `RangeError ... StringTable` after the
        // 2026-07-16 fleet SDK upgrade). The SDK version is the AOT-safe
        // toolchain-identity signal, so it partitions the cache.
        final managerA =
            makeCacheManager(tempDir.path, dartSdkVersion: '3.8.0');
        final managerB =
            makeCacheManager(tempDir.path, dartSdkVersion: '3.10.0');

        final pathA = managerA.getCachePath('pkg', '1.0.0');
        final pathB = managerB.getCachePath('pkg', '1.0.0');
        expect(pathA, isNot(equals(pathB)));
        expect(managerA.cacheDirectory, endsWith('3.8.0'));
        expect(managerB.cacheDirectory, endsWith('3.10.0'));
      });

      test('a summary written under a mismatched SDK partition is not loaded',
          () async {
        // The explicit RCK26 requirement: a `.sum` produced by one toolchain
        // must be invisible to a manager keyed to a different toolchain, so a
        // Dart SDK upgrade starts from an empty partition automatically and
        // never reads a stale, format-incompatible bundle.
        final oldToolchain =
            makeCacheManager(tempDir.path, dartSdkVersion: '3.8.0');
        final newToolchain =
            makeCacheManager(tempDir.path, dartSdkVersion: '3.10.0');

        await oldToolchain.writeSummary(
            'async', '2.13.0', Uint8List.fromList([1, 2, 3]));

        expect(await newToolchain.hasSummary('async', '2.13.0'), isFalse);
        expect(await newToolchain.loadSummary('async', '2.13.0'), isNull);
        expect(await oldToolchain.hasSummary('async', '2.13.0'), isTrue);
      });
    });

    group('cleanOutdated', () {
      test('is currently a no-op', () async {
        // cleanOutdated is a placeholder until SDK version metadata
        // is embedded in summary files. Verify it doesn't throw.
        await cacheManager.writeSummary(
            'pkg', '1.0.0', Uint8List.fromList([1]));
        await cacheManager.cleanOutdated();

        // Summary should still exist (no-op)
        expect(await cacheManager.hasSummary('pkg', '1.0.0'), isTrue);
      });
    });

    group('loadSummaries', () {
      test('returns empty store when no summaries exist', () async {
        final deps = [
          const PackageDependency(
              name: 'a', version: '1.0.0', source: 'hosted'),
        ];

        final store = await cacheManager.loadSummaries(deps);
        // SummaryDataStore doesn't expose a count, but should not throw
        expect(store, isNotNull);
      });

      test('skips non-cacheable dependencies', () async {
        final deps = [
          const PackageDependency(
              name: 'local', version: '1.0.0', source: 'path'),
        ];

        final store = await cacheManager.loadSummaries(deps);
        expect(store, isNotNull);
      });
    });

    group('CacheStats', () {
      test('totalSizeMB converts bytes correctly', () {
        const stats = CacheStats(
          summaryCount: 1,
          totalSizeBytes: 1048576, // 1 MB
          cacheDirectory: '/tmp/test',
        );
        expect(stats.totalSizeMB, closeTo(1.0, 0.001));
      });

      test('toString contains summary count and size', () {
        const stats = CacheStats(
          summaryCount: 5,
          totalSizeBytes: 2097152, // 2 MB
          cacheDirectory: '/tmp/test',
        );
        final str = stats.toString();
        expect(str, contains('5'));
        expect(str, contains('2.00'));
      });
    });
  });
}
