@Tags(['integration'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

/// Two summary-cache stages populating ONE empty partition at the same time
/// must leave it exactly as one stage after the other does.
///
/// Measured 2026-11-07 (tom_forge later21): a partition populated by a
/// `dart test -j 4` run and a bridge regeneration at once held bundles far
/// smaller than a cold build (`yaml` 1.7 KB instead of 67 KB, `dcli_core`
/// 13 KB instead of 65 KB), and a consumer lost types without a word. The
/// two stages here run in two isolates, as `dart test -j` runs its suites,
/// on dependency closures that overlap (`collection`, `path`,
/// `string_scanner`, `source_span`, `term_glyph`, `meta`).
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('summary_concurrency_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('two concurrent populations of an empty partition equal one after the '
      'other', () async {
    final pubCache = _pubCacheHosted();
    final yamlStack = _available(pubCache, _yamlStack);
    final globStack = _available(pubCache, _globStack);
    if (yamlStack == null || globStack == null) {
      markTestSkipped('the fixture packages are not all in the pub cache');
      return;
    }

    final projectA = _project(tempDir, 'project_a', yamlStack);
    final projectB = _project(tempDir, 'project_b', globStack);

    final sequential = p.join(tempDir.path, 'sequential');
    await _stage(projectA, sequential);
    await _stage(projectB, sequential);
    final expected = _bundles(sequential);
    expect(
      expected.keys.map(_packageOf).toSet(),
      containsAll(<String>{
        for (final e in [...yamlStack.entries, ...globStack.entries])
          '${e.key}@${e.value}',
      }),
      reason: 'the sequential build caches every package',
    );

    // Several rounds: a race does not show on every interleaving.
    for (var round = 1; round <= 3; round++) {
      final concurrent = p.join(tempDir.path, 'concurrent_$round');
      await Future.wait([
        Isolate.run(() => _stage(projectA, concurrent)),
        Isolate.run(() => _stage(projectB, concurrent)),
      ]);
      final actual = _bundles(concurrent);
      expect(
        actual.keys.toSet(),
        expected.keys.toSet(),
        reason: 'round $round',
      );
      for (final name in expected.keys) {
        expect(
          actual[name],
          expected[name],
          reason: 'round $round: $name differs from the sequential build',
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('a package linked without its dependencies\' summaries is reported and '
      'not cached', () async {
    final hosted = _pubCacheHosted();
    final yamlStack = _available(hosted, _yamlStack);
    if (yamlStack == null) {
      markTestSkipped('the fixture packages are not all in the pub cache');
      return;
    }
    final cache = SummaryCacheManager(
      tempDir.path,
      cacheDirectory: p.join(tempDir.path, 'cache'),
    );
    final generator = SummaryGenerator(
      cacheManager: cache,
      dependencyResolver: DependencyResolver(),
    );
    await generator.generateSdkSummary();

    final yaml = PackageDependency(
      name: 'yaml',
      version: yamlStack['yaml']!,
      source: 'hosted',
    );
    final yamlDir = Directory(p.join(hosted, 'yaml-${yaml.version}'));
    final dartToolBefore = Directory(
      p.join(yamlDir.path, '.dart_tool'),
    ).existsSync();

    // No bundle of source_span, string_scanner, collection ...: yaml's
    // imports of them cannot resolve.
    const fingerprint = 'a closure the test makes up';
    await expectLater(
      generator.generateSummary(
        yaml,
        fingerprint: fingerprint,
        sdkSummaryPath: cache.getSdkSummaryPath(),
        librarySummaryPaths: const [],
      ),
      throwsA(
        isA<IncompleteSummaryException>()
            .having((e) => e.packageName, 'packageName', 'yaml')
            .having(
              (e) => e.problems.join('\n'),
              'problems',
              contains('package:source_span/'),
            ),
      ),
    );
    expect(
      await cache.hasSummary(yaml.name, yaml.version, fingerprint: fingerprint),
      isFalse,
    );
    expect(
      Directory(
        cache.cacheDirectory,
      ).listSync().where((e) => e.path.endsWith('.tmp')),
      isEmpty,
      reason: 'no temp file is left behind',
    );
    expect(
      Directory(p.join(yamlDir.path, '.dart_tool')).existsSync(),
      dartToolBefore,
      reason: 'the pub-cache package directory is only read',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
  test('stages whose closures for one package differ never delete each '
      "other's bundles", () async {
    final hosted = _pubCacheHosted();
    final base = _available(hosted, _yamlStack);
    final oldGlyph = _versionIn(
      hosted,
      'term_glyph',
      exclude: base?['term_glyph'],
    );
    if (base == null || oldGlyph == null) {
      markTestSkipped(
        'the fixture packages, and a second term_glyph, are not all in the '
        'pub cache',
      );
      return;
    }
    // One package set, two resolutions of term_glyph: source_span,
    // string_scanner and yaml are the same name@version in both projects
    // and are linked against different closures.
    final projectA = _project(tempDir, 'closure_a', base);
    final projectB = _project(tempDir, 'closure_b', {
      ...base,
      'term_glyph': oldGlyph,
    });

    // Each project alone: the bundles it must load.
    final aloneA = await _stage(projectA, p.join(tempDir.path, 'alone_a'));
    final aloneB = await _stage(projectB, p.join(tempDir.path, 'alone_b'));
    final expectedA = _loaded(aloneA.paths);
    final expectedB = _loaded(aloneB.paths);

    // One after the other: B must not invalidate what A cached.
    final shared = p.join(tempDir.path, 'shared');
    await _stage(projectA, shared);
    await _stage(projectB, shared);
    final again = await _stage(projectA, shared);
    expect(
      again.logs,
      contains(startsWith('All ')),
      reason: "A's bundles survived B's run: ${again.logs.join(' | ')}",
    );

    // At once, several rounds into fresh partitions.
    for (var round = 1; round <= 3; round++) {
      final partition = p.join(tempDir.path, 'concurrent_$round');
      final runs = await Future.wait([
        Isolate.run(() => _stage(projectA, partition)),
        Isolate.run(() => _stage(projectB, partition)),
        Isolate.run(() => _stage(projectA, partition)),
        Isolate.run(() => _stage(projectB, partition)),
      ]);
      for (final (i, run) in runs.indexed) {
        final problems = run.logs.where(
          (l) =>
              l.contains('Warning') ||
              l.contains('PathNotFoundException') ||
              l.contains('not generated'),
        );
        expect(problems, isEmpty, reason: 'round $round, stage $i');
        expect(
          _loaded(run.paths),
          i.isEven ? expectedA : expectedB,
          reason:
              'round $round, stage $i loads the bundles its project builds '
              'alone',
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// The `yaml` stack, by the versions this package itself resolves.
const _yamlStack = [
  'yaml',
  'source_span',
  'string_scanner',
  'collection',
  'path',
  'term_glyph',
  'meta',
];

/// The `glob` stack; it shares six packages with [_yamlStack].
const _globStack = [
  'glob',
  'async',
  'file',
  'collection',
  'path',
  'string_scanner',
  'source_span',
  'term_glyph',
  'meta',
];

String _pubCacheHosted() => p.join(
  Platform.environment['PUB_CACHE'] ??
      p.join(Platform.environment['HOME'] ?? '', '.pub-cache'),
  'hosted',
  'pub.dev',
);

/// [names] at the versions in this package's own `pubspec.lock`, or `null`
/// when one is missing from the pub cache.
Map<String, String>? _available(String hosted, List<String> names) {
  final lock = File('pubspec.lock');
  if (!lock.existsSync()) return null;
  final text = lock.readAsStringSync();
  final out = <String, String>{};
  for (final name in names) {
    final match = RegExp(
      '^  ${RegExp.escape(name)}:\\n(?:    .*\\n)*?    version: "([^"]+)"',
      multiLine: true,
    ).firstMatch(text);
    if (match == null) return null;
    final version = match.group(1)!;
    if (!Directory(p.join(hosted, '$name-$version', 'lib')).existsSync()) {
      return null;
    }
    out[name] = version;
  }
  return out;
}

/// A project whose `pubspec.lock` resolves exactly [packages].
String _project(Directory parent, String name, Map<String, String> packages) {
  final dir = Directory(p.join(parent.path, name))..createSync();
  final lock = StringBuffer('packages:\n');
  for (final e in packages.entries) {
    lock.write('''
  ${e.key}:
    dependency: "direct main"
    description:
      name: ${e.key}
      url: "https://pub.dev"
    source: hosted
    version: "${e.value}"
''');
  }
  lock.write('sdks:\n  dart: ">=3.0.0 <4.0.0"\n');
  File(p.join(dir.path, 'pubspec.lock')).writeAsStringSync(lock.toString());
  return dir.path;
}

/// Runs the summary-cache stage of [project] against [cacheDirectory] and
/// answers the bundles it loads and everything it logged.
Future<({List<String> paths, List<String> logs})> _stage(
  String project,
  String cacheDirectory,
) async {
  final logs = <String>[];
  final result = await runSummaryCacheStage(
    project,
    log: logs.add,
    cacheManager: SummaryCacheManager(project, cacheDirectory: cacheDirectory),
  );
  if (result == null) throw StateError('no summaries for $project');
  return (paths: result.summaryPaths ?? const <String>[], logs: logs);
}

/// The bundles at [paths], read now, by `name@version`: their length, digest
/// and library URIs.
Map<String, String> _loaded(List<String> paths) => {
  for (final path in paths) _packageOf(path): _describe(File(path)),
};

/// `name@version` of a bundle file, without any closure suffix.
String _packageOf(String path) =>
    p.basenameWithoutExtension(path).split('+').first;

/// A second cached version of [name], other than [exclude], or `null`.
String? _versionIn(String hosted, String name, {String? exclude}) {
  final dir = Directory(hosted);
  if (!dir.existsSync()) return null;
  for (final entity in dir.listSync()) {
    final match = RegExp(
      '^${RegExp.escape(name)}-(\\d+\\.\\d+\\.\\d+)\$',
    ).firstMatch(p.basename(entity.path));
    if (match != null &&
        match.group(1) != exclude &&
        Directory(p.join(entity.path, 'lib')).existsSync()) {
      return match.group(1);
    }
  }
  return null;
}

/// Every package bundle in [cacheDirectory] (the SDK summary aside), by file
/// name, described by [_describe].
Map<String, String> _bundles(String cacheDirectory) => {
  for (final entity in Directory(cacheDirectory).listSync())
    if (entity is File &&
        entity.path.endsWith('.sum') &&
        !p.basename(entity.path).startsWith('sdk@'))
      p.basename(entity.path): _describe(entity),
};

/// A bundle's length, a digest of its bytes and the library URIs it holds, as
/// one line a failure prints readably; `missing` when the file is gone.
String _describe(File file) {
  if (!file.existsSync()) return 'missing';
  final bytes = file.readAsBytesSync();
  final libraries = summaryLibraryUris(bytes)..sort();
  return '${bytes.length} bytes, digest ${_digest(bytes)}, '
      '${libraries.length} libraries: ${libraries.join(' ')}';
}

/// A cheap content digest (FNV-1a); collisions do not matter for a test that
/// also compares lengths and library sets.
String _digest(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final b in bytes) {
    hash = ((hash ^ b) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16);
}
