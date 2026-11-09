import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

/// Tests for closure-keyed bundles: a package's bundle is named by the
/// dependency closure it is linked against, so it is never loaded against
/// another closure and never has to be deleted for one.
///
/// Two failures they guard against:
///
/// * A bundle keyed only by its own `name@version` (`tom_crypto@1.0.0.sum`)
///   is silently stale when a *transitive* dependency it linked against moves
///   (`tom_basics@1.0.0` -> `1.0.1`): loading it throws "Missing library".
/// * Two projects resolving different closures for one `name@version` each
///   took the other's bundle for stale and deleted it, while a concurrent run
///   was linking against it (tom_forge later22: PathNotFoundException, then
///   lost types). Under its own name each closure's bundle stays valid.
void main() {
  late Directory tempDir;
  late SummaryCacheManager cacheManager;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('summary_fp_test_');
    cacheManager = SummaryCacheManager(
      tempDir.path,
      dartSdkVersion: '3.10.4',
      // The override is the tool-cache *root*; the manager appends its own
      // `analyzer-cache/` below it, as in production.
      environment: {'TOM_TOOL_CACHE': p.join(tempDir.path, '.tom')},
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('closure-keyed file names', () {
    test('the name carries a 16-digit hash of the closure', () {
      final path = cacheManager.getCachePath(
        'tom_crypto',
        '1.0.0',
        fingerprint: 'tom_basics@1.0.1',
      );
      final hash = SummaryCacheManager.closureHash('tom_basics@1.0.1');
      expect(hash, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(p.basename(path), equals('tom_crypto@1.0.0+$hash.sum'));
    });

    test('one closure gives one name, another closure another', () {
      String pathFor(String fingerprint) => cacheManager.getCachePath(
        'tom_crypto',
        '1.0.0',
        fingerprint: fingerprint,
      );
      expect(pathFor('tom_basics@1.0.1'), equals(pathFor('tom_basics@1.0.1')));
      expect(
        pathFor('tom_basics@1.0.1'),
        isNot(equals(pathFor('tom_basics@1.0.0'))),
      );
    });

    test('a bundle is not found for another closure', () async {
      await cacheManager.writeSummary(
        'tom_crypto',
        '1.0.0',
        Uint8List.fromList([1, 2, 3]),
        fingerprint: 'tom_basics@1.0.0',
      );
      expect(
        await cacheManager.hasSummary(
          'tom_crypto',
          '1.0.0',
          fingerprint: 'tom_basics@1.0.0',
        ),
        isTrue,
      );
      expect(
        await cacheManager.hasSummary(
          'tom_crypto',
          '1.0.0',
          fingerprint: 'tom_basics@1.0.1',
        ),
        isFalse,
      );
    });

    test('the bundles of two closures coexist', () async {
      for (final fingerprint in ['tom_basics@1.0.0', 'tom_basics@1.0.1']) {
        await cacheManager.writeSummary(
          'tom_crypto',
          '1.0.0',
          Uint8List.fromList(fingerprint.codeUnits),
          fingerprint: fingerprint,
        );
      }
      final summaries = await cacheManager.listCachedSummaries();
      expect(summaries, hasLength(2));
      for (final fingerprint in ['tom_basics@1.0.0', 'tom_basics@1.0.1']) {
        final path = cacheManager.getCachePath(
          'tom_crypto',
          '1.0.0',
          fingerprint: fingerprint,
        );
        expect(File(path).readAsStringSync(), equals(fingerprint));
      }
    });

    test('clearCache removes every file of the partition', () async {
      await cacheManager.writeSummary(
        'a',
        '1.0.0',
        Uint8List.fromList([1]),
        fingerprint: 'b@1.0.0',
      );
      File(
        p.join(cacheManager.cacheDirectory, 'a@0.9.0.sum.deps'),
      ).writeAsStringSync('left by an older release');

      await cacheManager.clearCache();

      expect(Directory(cacheManager.cacheDirectory).listSync(), isEmpty);
    });
  });

  group('computeDependencyFingerprints', () {
    final generator = SummaryGenerator(
      cacheManager: SummaryCacheManager(
        '.',
        cacheDirectory: 'unused',
        dartSdkVersion: '3.10.4',
      ),
      dependencyResolver: DependencyResolver(),
    );

    PackageDependency hosted(String name, String version) =>
        PackageDependency(name: name, version: version, source: 'hosted');

    // a -> b -> c, and d on its own.
    final graph = {
      'a': {'b'},
      'b': {'c'},
      'c': <String>{},
      'd': <String>{},
    };

    Future<Map<String, String>> fingerprintsWith(String cVersion) =>
        generator.computeDependencyFingerprints([
          hosted('a', '1.0.0'),
          hosted('b', '1.0.0'),
          hosted('c', cVersion),
          hosted('d', '1.0.0'),
        ], directDependencyGraph: graph);

    test('names the format and the sorted versioned closure', () async {
      final fingerprints = await fingerprintsWith('1.0.0');
      expect(
        fingerprints['a'],
        equals(
          [SummaryGenerator.fingerprintFormat, 'b@1.0.0', 'c@1.0.0'].join('\n'),
        ),
      );
      expect(fingerprints['d'], equals(SummaryGenerator.fingerprintFormat));
    });

    test(
      'a version change reaches every dependent, and nothing else',
      () async {
        final before = await fingerprintsWith('1.0.0');
        final after = await fingerprintsWith('1.0.1');
        // c itself keeps its closure (it has no dependencies); b and a are
        // linked against c, so their bundles get other names.
        expect(after['c'], equals(before['c']));
        expect(after['b'], isNot(equals(before['b'])));
        expect(after['a'], isNot(equals(before['a'])));
        expect(after['d'], equals(before['d']));
      },
    );

    test('cycles are tolerated', () async {
      final fingerprints = await generator.computeDependencyFingerprints(
        [hosted('x', '1.0.0'), hosted('y', '2.0.0')],
        directDependencyGraph: {
          'x': {'y'},
          'y': {'x'},
        },
      );
      expect(fingerprints['x'], contains('y@2.0.0'));
      expect(fingerprints['y'], contains('x@1.0.0'));
    });
  });

  group('SummaryGenerator.dependencyClosure', () {
    test('follows the edges transitively, not back to the start', () {
      expect(
        SummaryGenerator.dependencyClosure({
          'a': {'b'},
          'b': {'c'},
          'c': <String>{},
        }, 'a'),
        equals({'b', 'c'}),
      );
    });

    test('a package absent from the graph has an empty closure', () {
      expect(
        SummaryGenerator.dependencyClosure(<String, Set<String>>{}, 'z'),
        isEmpty,
      );
    });
  });
}
