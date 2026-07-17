import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

/// Tests for the dependency-closure fingerprint mechanism that keeps a
/// `.sum` bundle from being loaded after a *transitive* dependency changes
/// version.
///
/// The failure it guards against: a summary keyed only by its own
/// `name@version` (e.g. `tom_crypto@1.0.0.sum`) is silently stale when a
/// transitive dependency it linked against moves — `tom_basics@1.0.0`'s
/// `src/exception_base.dart` becoming `tom_basics@1.0.1`'s
/// `src/exceptions/exception_base.dart`. Loading the stale bundle throws
/// "Missing library", which the bridge generator swallows and drops the
/// affected classes. A per-bundle `.sum.deps` sidecar records the versioned
/// closure the bundle was linked against so it can be invalidated precisely.
void main() {
  late Directory tempDir;
  late SummaryCacheManager cacheManager;

  SummaryCacheManager makeCacheManager(String root) {
    return SummaryCacheManager(
      root,
      dartSdkVersion: '3.10.4',
      environment: {'TOM_TOOL_CACHE': p.join(root, '.tom', 'tom_tool_cache')},
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('summary_fp_test_');
    cacheManager = makeCacheManager(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('fingerprint sidecar', () {
    test('getFingerprintPath is the .sum path plus .deps', () {
      final sum = cacheManager.getCachePath('tom_crypto', '1.0.0');
      final fp = cacheManager.getFingerprintPath('tom_crypto', '1.0.0');
      expect(fp, equals('$sum.deps'));
      expect(fp, endsWith('tom_crypto@1.0.0.sum.deps'));
    });

    test('writeFingerprint then readFingerprint round-trips', () async {
      await cacheManager.writeFingerprint(
        'tom_crypto',
        '1.0.0',
        'tom_basics@1.0.1',
      );
      final recorded = await cacheManager.readFingerprint(
        'tom_crypto',
        '1.0.0',
      );
      expect(recorded, equals('tom_basics@1.0.1'));
    });

    test('readFingerprint returns null when sidecar is absent', () async {
      final recorded = await cacheManager.readFingerprint(
        'tom_crypto',
        '1.0.0',
      );
      expect(recorded, isNull);
    });

    test('a .sum.deps sidecar is not listed as a cached summary', () async {
      await cacheManager.writeSummary(
        'tom_crypto',
        '1.0.0',
        Uint8List.fromList([1, 2, 3]),
      );
      await cacheManager.writeFingerprint(
        'tom_crypto',
        '1.0.0',
        'tom_basics@1.0.1',
      );

      final summaries = await cacheManager.listCachedSummaries();
      expect(summaries.keys, equals(['tom_crypto@1.0.0']));
    });
  });

  group('isSummaryFresh', () {
    test('false when the summary bundle is absent', () async {
      // No .sum at all — even a matching sidecar cannot make it fresh.
      await cacheManager.writeFingerprint(
        'tom_crypto',
        '1.0.0',
        'tom_basics@1.0.1',
      );
      expect(
        await cacheManager.isSummaryFresh(
          'tom_crypto',
          '1.0.0',
          'tom_basics@1.0.1',
        ),
        isFalse,
      );
    });

    test(
      'false when the sidecar is missing (pre-fingerprint bundle)',
      () async {
        // Bundles produced before fingerprinting existed have no sidecar and
        // must self-heal: they are treated as stale so they get regenerated.
        await cacheManager.writeSummary(
          'tom_crypto',
          '1.0.0',
          Uint8List.fromList([1, 2, 3]),
        );
        expect(
          await cacheManager.isSummaryFresh(
            'tom_crypto',
            '1.0.0',
            'tom_basics@1.0.1',
          ),
          isFalse,
        );
      },
    );

    test('false when a transitive dependency changed version', () async {
      // Bundle was linked against tom_basics@1.0.0; the graph now resolves
      // tom_basics@1.0.1 — the classic stale-transitive-dep poison.
      await cacheManager.writeSummary(
        'tom_crypto',
        '1.0.0',
        Uint8List.fromList([1, 2, 3]),
      );
      await cacheManager.writeFingerprint(
        'tom_crypto',
        '1.0.0',
        'tom_basics@1.0.0',
      );
      expect(
        await cacheManager.isSummaryFresh(
          'tom_crypto',
          '1.0.0',
          'tom_basics@1.0.1',
        ),
        isFalse,
      );
    });

    test('true when bundle and sidecar match the expected closure', () async {
      await cacheManager.writeSummary(
        'tom_crypto',
        '1.0.0',
        Uint8List.fromList([1, 2, 3]),
      );
      await cacheManager.writeFingerprint(
        'tom_crypto',
        '1.0.0',
        'tom_basics@1.0.1',
      );
      expect(
        await cacheManager.isSummaryFresh(
          'tom_crypto',
          '1.0.0',
          'tom_basics@1.0.1',
        ),
        isTrue,
      );
    });
  });

  group('deleteSummary', () {
    test('removes both the .sum bundle and its .deps sidecar', () async {
      await cacheManager.writeSummary(
        'tom_crypto',
        '1.0.0',
        Uint8List.fromList([1, 2, 3]),
      );
      await cacheManager.writeFingerprint(
        'tom_crypto',
        '1.0.0',
        'tom_basics@1.0.0',
      );

      final sumPath = cacheManager.getCachePath('tom_crypto', '1.0.0');
      final fpPath = cacheManager.getFingerprintPath('tom_crypto', '1.0.0');
      expect(File(sumPath).existsSync(), isTrue);
      expect(File(fpPath).existsSync(), isTrue);

      await cacheManager.deleteSummary('tom_crypto', '1.0.0');

      expect(File(sumPath).existsSync(), isFalse);
      expect(File(fpPath).existsSync(), isFalse);
    });

    test('is a no-op when neither file exists', () async {
      // Should not throw.
      await cacheManager.deleteSummary('missing', '9.9.9');
    });
  });

  group('sidecar cleanup', () {
    test('clearCache removes .sum.deps sidecars as well', () async {
      await cacheManager.writeSummary('a', '1.0.0', Uint8List.fromList([1]));
      await cacheManager.writeFingerprint('a', '1.0.0', 'b@1.0.0');

      final fpPath = cacheManager.getFingerprintPath('a', '1.0.0');
      expect(File(fpPath).existsSync(), isTrue);

      await cacheManager.clearCache();

      expect(File(fpPath).existsSync(), isFalse);
      expect(await cacheManager.listCachedSummaries(), isEmpty);
    });

    test(
      'cleanUnusedSummaries removes the sidecar of a dropped package',
      () async {
        await cacheManager.writeSummary(
          'old_pkg',
          '1.0.0',
          Uint8List.fromList([1]),
        );
        await cacheManager.writeFingerprint('old_pkg', '1.0.0', 'dep@1.0.0');
        await cacheManager.writeSummary(
          'current',
          '2.0.0',
          Uint8List.fromList([2]),
        );
        await cacheManager.writeFingerprint('current', '2.0.0', 'dep@2.0.0');

        final removed = await cacheManager.cleanUnusedSummaries([
          const PackageDependency(
            name: 'current',
            version: '2.0.0',
            source: 'hosted',
          ),
        ]);
        expect(removed, equals(1));

        expect(
          File(
            cacheManager.getFingerprintPath('old_pkg', '1.0.0'),
          ).existsSync(),
          isFalse,
        );
        expect(
          File(
            cacheManager.getFingerprintPath('current', '2.0.0'),
          ).existsSync(),
          isTrue,
        );
      },
    );
  });
}
