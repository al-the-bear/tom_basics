@Tags(['integration'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

/// Tests for [runSummaryCacheStage] — in particular the verbose
/// per-summary cache-usage trace ("using {pkg}@{ver}.sum from cache at
/// {path}") that lets a run be audited for actual cache reads.
///
/// Tagged 'integration' because the stage generates a real summary for a
/// small hosted package from the pub cache. The cache stays hermetic via an
/// injected [SummaryCacheManager] pointing at a temp directory.
void main() {
  late Directory tempDir;

  /// Finds a small hosted package in the pub cache to depend on.
  ({String name, String version})? findTestPackage() {
    final pubCache = Platform.environment['PUB_CACHE'] ??
        '${Platform.environment['HOME']}/.pub-cache';
    final hostedDir = Directory('$pubCache/hosted/pub.dev');
    if (!hostedDir.existsSync()) return null;

    for (final name in const ['meta', 'path', 'collection']) {
      for (final entity in hostedDir.listSync()) {
        if (entity is! Directory) continue;
        final dirName = p.basename(entity.path);
        final match = RegExp('^${RegExp.escape(name)}-(\\d+\\.\\d+\\.\\d+)\$')
            .firstMatch(dirName);
        if (match != null &&
            Directory('${entity.path}/lib').existsSync()) {
          return (name: name, version: match.group(1)!);
        }
      }
    }
    return null;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('summary_stage_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
    'verbose run traces each loaded summary with its cache path',
    () async {
      final pkg = findTestPackage();
      if (pkg == null) {
        markTestSkipped('No suitable package found in pub cache');
        return;
      }

      // Minimal project: a pubspec.lock listing the one hosted package.
      File(p.join(tempDir.path, 'pubspec.lock')).writeAsStringSync('''
packages:
  ${pkg.name}:
    dependency: "direct main"
    description:
      name: ${pkg.name}
      url: "https://pub.dev"
    source: hosted
    version: "${pkg.version}"
sdks:
  dart: ">=3.0.0 <4.0.0"
''');

      // Hermetic cache inside the temp dir — never touches the shared cache.
      final cacheManager = SummaryCacheManager(
        tempDir.path,
        cacheDirectory: p.join(tempDir.path, '.tom', 'analyzer-cache'),
      );

      final logs = <String>[];
      final result = await runSummaryCacheStage(
        tempDir.path,
        verbose: true,
        cacheManager: cacheManager,
        log: logs.add,
      );

      expect(result, isNotNull, reason: 'Stage should produce a result');
      expect(result!.summaryPaths, isNotNull);

      final cachePath = cacheManager.getCachePath(pkg.name, pkg.version);
      final trace = logs.firstWhere(
        (l) => l.contains('using ${pkg.name}@${pkg.version}.sum from cache at'),
        orElse: () => '',
      );
      expect(trace, isNotEmpty,
          reason: 'Expected a per-summary cache-usage trace line');
      expect(trace, contains(cachePath),
          reason: 'Trace should name the real cache path of the summary');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'non-verbose run omits per-summary traces',
    () async {
      final pkg = findTestPackage();
      if (pkg == null) {
        markTestSkipped('No suitable package found in pub cache');
        return;
      }

      File(p.join(tempDir.path, 'pubspec.lock')).writeAsStringSync('''
packages:
  ${pkg.name}:
    dependency: "direct main"
    description:
      name: ${pkg.name}
      url: "https://pub.dev"
    source: hosted
    version: "${pkg.version}"
sdks:
  dart: ">=3.0.0 <4.0.0"
''');

      final cacheManager = SummaryCacheManager(
        tempDir.path,
        cacheDirectory: p.join(tempDir.path, '.tom', 'analyzer-cache'),
      );

      final logs = <String>[];
      await runSummaryCacheStage(
        tempDir.path,
        cacheManager: cacheManager,
        log: logs.add,
      );

      expect(
        logs.any((l) => l.contains('using ') && l.contains('.sum from cache')),
        isFalse,
        reason: 'Non-verbose runs must not emit per-summary traces',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
