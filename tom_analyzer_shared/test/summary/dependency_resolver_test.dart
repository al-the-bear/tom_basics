import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

void main() {
  late Directory tempDir;
  late DependencyResolver resolver;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dep_resolver_test_');
    resolver = DependencyResolver();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('DependencyResolver', () {
    group('getDartVersion', () {
      test('returns a semantic version string', () {
        final version = resolver.getDartVersion();
        expect(version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
      });
    });

    group('resolveVersionedDependencies', () {
      test('throws when pubspec.lock does not exist', () async {
        expect(
          () => resolver.resolveVersionedDependencies(tempDir.path),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('returns empty list for empty yaml', () async {
        _writeLockFile(tempDir.path, '');

        final deps =
            await resolver.resolveVersionedDependencies(tempDir.path);
        expect(deps, isEmpty);
      });

      test('returns empty list when packages section is missing', () async {
        _writeLockFile(tempDir.path, 'sdks:\n  dart: ">=3.0.0"\n');

        final deps =
            await resolver.resolveVersionedDependencies(tempDir.path);
        expect(deps, isEmpty);
      });

      test('parses hosted dependency', () async {
        _writeLockFile(tempDir.path, '''
packages:
  provider:
    dependency: "direct main"
    description:
      name: provider
      sha256: abc123
      url: "https://pub.dev"
    source: hosted
    version: "6.1.2"
''');

        final deps =
            await resolver.resolveVersionedDependencies(tempDir.path);
        expect(deps, hasLength(1));

        final dep = deps.first;
        expect(dep.name, equals('provider'));
        expect(dep.version, equals('6.1.2'));
        expect(dep.source, equals('hosted'));
        expect(dep.hostedUrl, equals('https://pub.dev'));
        expect(dep.isCacheable, isTrue);
      });

      test('parses path dependency', () async {
        _writeLockFile(tempDir.path, '''
packages:
  my_local:
    dependency: "direct main"
    description:
      path: "../my_local"
      relative: true
    source: path
    version: "0.1.0"
''');

        final deps =
            await resolver.resolveVersionedDependencies(tempDir.path);
        expect(deps, hasLength(1));

        final dep = deps.first;
        expect(dep.name, equals('my_local'));
        expect(dep.version, equals('0.1.0'));
        expect(dep.source, equals('path'));
        expect(dep.isCacheable, isFalse);
        expect(dep.path, isNotNull);
      });

      test('parses git dependency', () async {
        _writeLockFile(tempDir.path, '''
packages:
  my_git_pkg:
    dependency: "direct main"
    description:
      path: "."
      ref: main
      resolved-ref: abc123
      url: "https://github.com/user/repo.git"
    source: git
    version: "1.0.0"
''');

        final deps =
            await resolver.resolveVersionedDependencies(tempDir.path);
        expect(deps, hasLength(1));

        final dep = deps.first;
        expect(dep.name, equals('my_git_pkg'));
        expect(dep.version, equals('1.0.0'));
        expect(dep.source, equals('git'));
        expect(dep.isCacheable, isFalse);
      });

      test('parses SDK dependency', () async {
        _writeLockFile(tempDir.path, '''
packages:
  sky_engine:
    dependency: transitive
    description: flutter
    source: sdk
    version: "0.0.99"
''');

        final deps =
            await resolver.resolveVersionedDependencies(tempDir.path);
        expect(deps, hasLength(1));

        final dep = deps.first;
        expect(dep.name, equals('sky_engine'));
        expect(dep.source, equals('sdk'));
        expect(dep.sdkName, equals('flutter'));
        expect(dep.isCacheable, isTrue);
      });

      test('parses multiple dependencies and sorts by name', () async {
        _writeLockFile(tempDir.path, '''
packages:
  z_pkg:
    dependency: "direct main"
    description:
      name: z_pkg
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
  a_pkg:
    dependency: "direct main"
    description:
      name: a_pkg
      url: "https://pub.dev"
    source: hosted
    version: "2.0.0"
  m_pkg:
    dependency: "direct main"
    description:
      name: m_pkg
      url: "https://pub.dev"
    source: hosted
    version: "3.0.0"
''');

        final deps =
            await resolver.resolveVersionedDependencies(tempDir.path);
        expect(deps, hasLength(3));
        expect(deps[0].name, equals('a_pkg'));
        expect(deps[1].name, equals('m_pkg'));
        expect(deps[2].name, equals('z_pkg'));
      });

      test('skips entries with null source', () async {
        _writeLockFile(tempDir.path, '''
packages:
  broken:
    dependency: "direct main"
    description: something
    version: "1.0.0"
''');

        final deps =
            await resolver.resolveVersionedDependencies(tempDir.path);
        expect(deps, isEmpty);
      });

      test('skips hosted dependency without version', () async {
        _writeLockFile(tempDir.path, '''
packages:
  no_version:
    dependency: "direct main"
    description:
      name: no_version
      url: "https://pub.dev"
    source: hosted
''');

        final deps =
            await resolver.resolveVersionedDependencies(tempDir.path);
        expect(deps, isEmpty);
      });
    });

    group('resolveCacheableDependencies', () {
      test('returns only hosted and SDK dependencies', () async {
        _writeLockFile(tempDir.path, '''
packages:
  hosted_pkg:
    dependency: "direct main"
    description:
      name: hosted_pkg
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
  path_pkg:
    dependency: "direct main"
    description:
      path: "../local"
      relative: true
    source: path
    version: "0.1.0"
  git_pkg:
    dependency: "direct main"
    description:
      url: "https://github.com/user/repo"
    source: git
    version: "1.0.0"
''');

        final cacheable =
            await resolver.resolveCacheableDependencies(tempDir.path);
        expect(cacheable, hasLength(1));
        expect(cacheable.first.name, equals('hosted_pkg'));
      });
    });

    group('resolveDependencySet', () {
      test('groups dependencies by cacheability', () async {
        _writeLockFile(tempDir.path, '''
packages:
  hosted_a:
    dependency: "direct main"
    description:
      name: hosted_a
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
  hosted_b:
    dependency: "direct main"
    description:
      name: hosted_b
      url: "https://pub.dev"
    source: hosted
    version: "2.0.0"
  local:
    dependency: "direct main"
    description:
      path: "../local"
      relative: true
    source: path
    version: "0.1.0"
''');

        final depSet = await resolver.resolveDependencySet(tempDir.path);
        expect(depSet.cacheable, hasLength(2));
        expect(depSet.uncacheable, hasLength(1));
        expect(depSet.all, hasLength(3));
      });
    });

    group('getHostedPackagePath', () {
      test('returns null for non-hosted dependency', () {
        const dep = PackageDependency(
          name: 'local',
          version: '1.0.0',
          source: 'path',
        );
        expect(resolver.getHostedPackagePath(dep), isNull);
      });

      test('returns pub cache path for hosted dependency', () {
        const dep = PackageDependency(
          name: 'provider',
          version: '6.1.2',
          source: 'hosted',
          hostedUrl: 'https://pub.dev',
        );
        final path = resolver.getHostedPackagePath(dep);
        expect(path, isNotNull);
        expect(path, contains('pub-cache'));
        expect(path, contains('provider-6.1.2'));
      });
    });
  });

  group('PackageDependency', () {
    test('cacheKey format is name@version', () {
      const dep = PackageDependency(
        name: 'provider',
        version: '6.1.2',
        source: 'hosted',
      );
      expect(dep.cacheKey, equals('provider@6.1.2'));
    });

    test('isCacheable is true for hosted', () {
      const dep = PackageDependency(
        name: 'pkg', version: '1.0.0', source: 'hosted');
      expect(dep.isCacheable, isTrue);
    });

    test('isCacheable is true for sdk', () {
      const dep = PackageDependency(
        name: 'flutter', version: '3.0.0', source: 'sdk');
      expect(dep.isCacheable, isTrue);
    });

    test('isCacheable is false for path', () {
      const dep = PackageDependency(
        name: 'local', version: '1.0.0', source: 'path');
      expect(dep.isCacheable, isFalse);
    });

    test('isCacheable is false for git', () {
      const dep = PackageDependency(
        name: 'remote', version: '1.0.0', source: 'git');
      expect(dep.isCacheable, isFalse);
    });

    test('equality by name, version, and source', () {
      const a = PackageDependency(
        name: 'pkg', version: '1.0.0', source: 'hosted');
      const b = PackageDependency(
        name: 'pkg', version: '1.0.0', source: 'hosted');
      const c = PackageDependency(
        name: 'pkg', version: '2.0.0', source: 'hosted');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString includes name, version, and source', () {
      const dep = PackageDependency(
        name: 'provider', version: '6.1.2', source: 'hosted');
      expect(dep.toString(), contains('provider'));
      expect(dep.toString(), contains('6.1.2'));
      expect(dep.toString(), contains('hosted'));
    });
  });

  group('DependencySet', () {
    test('from separates cacheable and uncacheable', () {
      final deps = [
        const PackageDependency(
            name: 'a', version: '1.0.0', source: 'hosted'),
        const PackageDependency(
            name: 'b', version: '1.0.0', source: 'path'),
        const PackageDependency(
            name: 'c', version: '1.0.0', source: 'sdk', sdkName: 'flutter'),
        const PackageDependency(
            name: 'd', version: '1.0.0', source: 'git'),
      ];

      final set = DependencySet.from(deps);
      expect(set.cacheable, hasLength(2));
      expect(set.uncacheable, hasLength(2));
      expect(set.all, hasLength(4));
    });

    test('empty list yields empty sets', () {
      final set = DependencySet.from([]);
      expect(set.cacheable, isEmpty);
      expect(set.uncacheable, isEmpty);
      expect(set.all, isEmpty);
    });
  });

  group('DependencyListExtensions', () {
    final deps = [
      const PackageDependency(
          name: 'hosted_a', version: '1.0.0', source: 'hosted'),
      const PackageDependency(
          name: 'sdk_a', version: '1.0.0', source: 'sdk', sdkName: 'flutter'),
      const PackageDependency(
          name: 'path_a', version: '1.0.0', source: 'path'),
      const PackageDependency(
          name: 'hosted_b', version: '2.0.0', source: 'hosted'),
    ];

    test('findByName returns matching dependency', () {
      expect(deps.findByName('hosted_a')?.name, equals('hosted_a'));
    });

    test('findByName returns null when not found', () {
      expect(deps.findByName('nonexistent'), isNull);
    });

    test('hosted returns only hosted deps', () {
      expect(deps.hosted, hasLength(2));
    });

    test('sdk returns only sdk deps', () {
      expect(deps.sdk, hasLength(1));
    });

    test('paths returns only path deps', () {
      expect(deps.paths, hasLength(1));
    });

    test('cacheable returns hosted + sdk', () {
      expect(deps.cacheable, hasLength(3));
    });
  });
}

/// Writes a pubspec.lock file with the given content.
void _writeLockFile(String projectRoot, String content) {
  File(p.join(projectRoot, 'pubspec.lock')).writeAsStringSync(content);
}
