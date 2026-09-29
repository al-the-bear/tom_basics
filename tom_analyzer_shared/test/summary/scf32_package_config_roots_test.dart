// SCF32 — the summary cache on Windows.
//
// Measured on legiondary01 (2026-09-29): every hosted package reported
// "Skipping <pkg>: no public libraries", because its location was guessed as
// `$HOME/.pub-cache/...`; on Windows the pub cache is under
// `%LOCALAPPDATA%\Pub\Cache`. The Flutter SDK packages were still found, so
// `flutter@3.44.6.sum` WAS built — linked against a `vector_math` with no
// summary and no resolvable source. `Matrix4` went into it as an invalid type,
// and the bridge generator downstream silently lost every API that mentions
// it.
//
// Two repairs, one case each:
// * package locations come from `.dart_tool/package_config.json`, which pub
//   writes for every platform (F-SCF32-1);
// * a summary is never linked against a dependency that has none — it is left
//   out, and its source analysed directly (F-SCF32-2).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

/// A `pubspec.lock` entry for a hosted package.
String _hosted(String name, String version) =>
    '''
  $name:
    dependency: "direct main"
    description:
      name: $name
      url: "https://pub.dev"
    source: hosted
    version: "$version"
''';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('scf32_tas_'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  /// A project resolving [lockEntries], whose package config records
  /// [roots] (name → rootUri, written verbatim).
  Directory project(String lockEntries, Map<String, String> roots) {
    final dir = Directory(p.join(tempDir.path, 'project'))..createSync();
    File(
      p.join(dir.path, 'pubspec.lock'),
    ).writeAsStringSync('packages:\n$lockEntries');
    final entries = roots.entries
        .map(
          (e) =>
              '{"name": "${e.key}", "rootUri": "${e.value}", '
              '"packageUri": "lib/"}',
        )
        .join(', ');
    File(p.join(dir.path, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{"configVersion": 2, "packages": [$entries]}');
    return dir;
  }

  /// A package directory with [pubspec] and one library [libSource].
  Directory package(String name, String pubspec, String libSource) {
    final dir = Directory(p.join(tempDir.path, name))..createSync();
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
    File(p.join(dir.path, 'lib', '$name.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(libSource);
    return dir;
  }

  test('F-SCF32-1: package locations come from package_config.json, '
      'relative and absolute alike [2026-09-29] (PASS)', () async {
    final hosted = package('zom_hosted', 'name: zom_hosted\n', '');
    final sdk = package('zom_sdk', 'name: zom_sdk\n', '');
    final dir = project(_hosted('zom_hosted', '1.0.0'), {
      // pub writes hosted roots as absolute file URIs, and path roots
      // relative to `.dart_tool/`.
      'zom_hosted': '${hosted.uri}',
      'zom_sdk': '../../zom_sdk',
    });

    final resolver = DependencyResolver();
    await resolver.resolveVersionedDependencies(dir.path);

    expect(
      resolver.getHostedPackagePath(
        const PackageDependency(
          name: 'zom_hosted',
          version: '1.0.0',
          source: 'hosted',
        ),
      ),
      p.normalize(hosted.path),
      reason: 'not a guessed pub-cache path',
    );
    expect(
      await resolver.getSdkPackagePath(
        const PackageDependency(
          name: 'zom_sdk',
          version: '1.0.0',
          source: 'sdk',
          sdkName: 'flutter',
        ),
      ),
      p.normalize(sdk.path),
    );
  });

  test('F-SCF32-2: a summary is not linked against a dependency whose own '
      'summary failed [2026-09-29] (PASS)', () async {
    // zom_b depends on zom_a. zom_b is where the package config says; zom_a
    // is recorded nowhere, so its lookup falls back to a pub-cache guess that
    // does not exist — Windows' situation for every hosted package.
    final b = package(
      'zom_b',
      'name: zom_b\ndependencies:\n  zom_a: ^1.0.0\n',
      "import 'package:zom_a/zom_a.dart';\nA make() => A();\n",
    );
    final dir = project(
      _hosted('zom_a', '97.0.0') + _hosted('zom_b', '1.0.0'),
      {'zom_b': '${b.uri}'},
    );
    final resolver = DependencyResolver();
    final deps = await resolver.resolveVersionedDependencies(dir.path);
    final cache = SummaryCacheManager(
      dir.path,
      dartSdkVersion: '0.0.0-test',
      cacheDirectory: p.join(tempDir.path, 'cache'),
    );

    final result = await SummaryGenerator(
      cacheManager: cache,
      dependencyResolver: resolver,
    ).generateMissingSummaries(deps);

    expect(result.errors['zom_a'], contains('not found at'));
    expect(
      result.errors['zom_b'],
      contains('zom_a'),
      reason:
          'linking zom_b now would record A as an invalid type in a bundle '
          'the cache then treats as fresh',
    );
    expect(result.generated, 0);
    expect(await cache.hasSummary('zom_b', '1.0.0'), isFalse);
  });

  test('F-SCF32-3: a bundle fingerprinted before the complete-link rule is '
      'stale [2026-09-29] (PASS)', () async {
    // A bundle poisoned on Windows carries a fingerprint that matches its
    // closure exactly; only the format line tells the two generations apart.
    final a = package('zom_a', 'name: zom_a\n', 'class A {}\n');
    final b = package(
      'zom_b',
      'name: zom_b\ndependencies:\n  zom_a: ^1.0.0\n',
      "import 'package:zom_a/zom_a.dart';\nA make() => A();\n",
    );
    final dir = project(_hosted('zom_a', '1.0.0') + _hosted('zom_b', '1.0.0'), {
      'zom_a': '${a.uri}',
      'zom_b': '${b.uri}',
    });
    final resolver = DependencyResolver();
    final deps = await resolver.resolveVersionedDependencies(dir.path);
    final cache = SummaryCacheManager(
      dir.path,
      dartSdkVersion: '0.0.0-test',
      cacheDirectory: p.join(tempDir.path, 'cache'),
    );
    final fingerprints = await SummaryGenerator(
      cacheManager: cache,
      dependencyResolver: resolver,
    ).computeDependencyFingerprints(deps);

    expect(
      fingerprints['zom_b'],
      '${SummaryGenerator.fingerprintFormat}\nzom_a@1.0.0',
    );
    expect(fingerprints['zom_a'], SummaryGenerator.fingerprintFormat);

    // The sidecar a pre-SCF32 build wrote for the same closure.
    await cache.writeSummary('zom_b', '1.0.0', Uint8List.fromList([1]));
    await cache.writeFingerprint('zom_b', '1.0.0', 'zom_a@1.0.0');
    expect(
      await cache.isSummaryFresh('zom_b', '1.0.0', fingerprints['zom_b']!),
      isFalse,
    );
  });
}
