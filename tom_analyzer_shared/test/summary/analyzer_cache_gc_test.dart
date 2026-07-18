// Copyright (c) 2026. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';
import 'package:test/test.dart';

/// Builds a partition directory `<root>/analyzer-cache/<major>/<sdk>` and writes
/// [summaryCount] `.sum` files (each [bytesPerSummary] bytes) plus a matching
/// `.sum.deps` sidecar into it. Returns the partition directory path.
String _makePartition(
  String cacheRoot,
  int major,
  String sdk, {
  int summaryCount = 1,
  int bytesPerSummary = 16,
}) {
  final dir = Directory(p.join(cacheRoot, '$major', sdk))
    ..createSync(recursive: true);
  for (var i = 0; i < summaryCount; i++) {
    File(p.join(dir.path, 'pkg$i@1.0.0.sum'))
        .writeAsBytesSync(List<int>.filled(bytesPerSummary, 0x41));
    File(p.join(dir.path, 'pkg$i@1.0.0.sum.deps')).writeAsStringSync('fp$i');
  }
  return dir.path;
}

AnalyzerCachePartition _part(
  String key, {
  required DateTime lastUsed,
}) {
  final parts = key.split('/');
  return AnalyzerCachePartition(
    analyzerMajor: int.parse(parts[0]),
    dartSdkVersion: parts[1],
    path: '/fake/$key',
    lastUsed: lastUsed,
    sizeBytes: 0,
    summaryCount: 0,
  );
}

void main() {
  group('currentDartSdkVersion', () {
    test('parses a <major>.<minor>.<patch> from the running toolchain', () {
      final v = currentDartSdkVersion();
      expect(v, matches(RegExp(r'^\d+\.\d+\.\d+$')),
          reason: 'should be a three-part version or "unknown": $v');
    });
  });

  group('AnalyzerCacheGarbageCollector.currentPartitionKey', () {
    test('is "<analyzer-major>/<sdk>" from the current toolchain', () {
      final key = AnalyzerCacheGarbageCollector.currentPartitionKey();
      expect(key, '$analyzerMajorVersion/${currentDartSdkVersion()}');
    });

    test('honors explicit overrides', () {
      final key = AnalyzerCacheGarbageCollector.currentPartitionKey(
        analyzerMajor: 8,
        dartSdkVersion: '3.0.0',
      );
      expect(key, '8/3.0.0');
    });
  });

  group('AnalyzerCacheGarbageCollector.selectForCollection (pure)', () {
    final oldPart = _part('10/3.0.0', lastUsed: DateTime(2020, 1, 1));
    final midPart = _part('10/3.6.0', lastUsed: DateTime(2023, 1, 1));
    final newPart = _part('10/3.12.0', lastUsed: DateTime(2026, 1, 1));
    final all = [oldPart, midPart, newPart];

    test('selects only partitions strictly older than the cutoff', () {
      final doomed = AnalyzerCacheGarbageCollector.selectForCollection(
        all,
        cutoff: DateTime(2024, 1, 1),
      );
      expect(doomed.map((e) => e.key), ['10/3.0.0', '10/3.6.0']);
    });

    test('cutoff boundary is exclusive (isBefore, not isAtOrBefore)', () {
      final doomed = AnalyzerCacheGarbageCollector.selectForCollection(
        all,
        cutoff: DateTime(2023, 1, 1), // exactly midPart.lastUsed
      );
      expect(doomed.map((e) => e.key), ['10/3.0.0'],
          reason: 'a partition whose lastUsed equals the cutoff is kept');
    });

    test('never selects a protected (keep) partition', () {
      final doomed = AnalyzerCacheGarbageCollector.selectForCollection(
        all,
        cutoff: DateTime(2027, 1, 1), // everything is older
        keep: {'10/3.12.0'},
      );
      expect(doomed.map((e) => e.key), ['10/3.0.0', '10/3.6.0']);
    });

    test('returns empty when nothing is older than the cutoff', () {
      final doomed = AnalyzerCacheGarbageCollector.selectForCollection(
        all,
        cutoff: DateTime(2019, 1, 1),
      );
      expect(doomed, isEmpty);
    });
  });

  group('AnalyzerCacheGarbageCollector.listPartitions (I/O)', () {
    late Directory tmp;
    late String cacheRoot;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('analyzer_gc_test_');
      cacheRoot = p.join(tmp.path, 'analyzer-cache');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('returns empty when the cache root does not exist', () async {
      final gc = AnalyzerCacheGarbageCollector(cacheRoot);
      expect(await gc.listPartitions(), isEmpty);
    });

    test('discovers every <major>/<sdk> partition', () async {
      _makePartition(cacheRoot, 10, '3.12.0');
      _makePartition(cacheRoot, 10, '3.6.0');
      _makePartition(cacheRoot, 8, '3.0.0');

      final gc = AnalyzerCacheGarbageCollector(cacheRoot);
      final parts = await gc.listPartitions();
      expect(parts.map((e) => e.key).toSet(),
          {'10/3.12.0', '10/3.6.0', '8/3.0.0'});
    });

    test('reports summary count and total size per partition', () async {
      _makePartition(cacheRoot, 10, '3.12.0',
          summaryCount: 3, bytesPerSummary: 100);

      final gc = AnalyzerCacheGarbageCollector(cacheRoot);
      final part = (await gc.listPartitions()).single;
      expect(part.summaryCount, 3);
      // 3 * (.sum 100 bytes) + 3 * (.sum.deps "fpN" = 3 bytes) = 309.
      expect(part.sizeBytes, 3 * 100 + 3 * 3);
    });

    test('lastUsed reflects the newest file mtime in the partition', () async {
      final path = _makePartition(cacheRoot, 10, '3.12.0', summaryCount: 2);
      final newest = Directory(path)
          .listSync()
          .whereType<File>()
          .map((f) => f.statSync().modified)
          .reduce((a, b) => a.isAfter(b) ? a : b);

      final gc = AnalyzerCacheGarbageCollector(cacheRoot);
      final part = (await gc.listPartitions()).single;
      expect(part.lastUsed, newest);
    });

    test('ignores stray non-integer major directories', () async {
      _makePartition(cacheRoot, 10, '3.12.0');
      Directory(p.join(cacheRoot, 'not-a-major', '3.0.0'))
          .createSync(recursive: true);

      final gc = AnalyzerCacheGarbageCollector(cacheRoot);
      final parts = await gc.listPartitions();
      expect(parts.map((e) => e.key), ['10/3.12.0']);
    });
  });

  group('AnalyzerCacheGarbageCollector.collect (I/O)', () {
    late Directory tmp;
    late String cacheRoot;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('analyzer_gc_collect_');
      cacheRoot = p.join(tmp.path, 'analyzer-cache');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('deletes partitions older than the cutoff', () async {
      final oldPath = _makePartition(cacheRoot, 8, '3.0.0');
      _makePartition(cacheRoot, 10, '3.12.0');

      final gc = AnalyzerCacheGarbageCollector(cacheRoot);
      // Cutoff in the future → every partition qualifies as "older".
      final removed = await gc.collect(
        cutoff: DateTime.now().add(const Duration(days: 1)),
        keep: {'10/3.12.0'},
      );

      expect(removed.map((e) => e.key), ['8/3.0.0']);
      expect(Directory(oldPath).existsSync(), isFalse);
      expect(Directory(p.join(cacheRoot, '10', '3.12.0')).existsSync(), isTrue);
    });

    test('dry run reports doomed partitions without deleting them', () async {
      final oldPath = _makePartition(cacheRoot, 8, '3.0.0');

      final gc = AnalyzerCacheGarbageCollector(cacheRoot);
      final removed = await gc.collect(
        cutoff: DateTime.now().add(const Duration(days: 1)),
        dryRun: true,
      );

      expect(removed.map((e) => e.key), ['8/3.0.0']);
      expect(Directory(oldPath).existsSync(), isTrue,
          reason: 'dry run must not touch the filesystem');
    });

    test('deletes nothing when no partition predates the cutoff', () async {
      _makePartition(cacheRoot, 10, '3.12.0');

      final gc = AnalyzerCacheGarbageCollector(cacheRoot);
      final removed = await gc.collect(
        cutoff: DateTime(2000, 1, 1),
      );

      expect(removed, isEmpty);
      expect(Directory(p.join(cacheRoot, '10', '3.12.0')).existsSync(), isTrue);
    });
  });
}
