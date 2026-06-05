import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_package_scanner/tom_package_scanner.dart';

const _prefix = 'tom_agent_container/tom_ai';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pkg_scanner_test_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  PackageScanner scanner({int locThreshold = 200}) => PackageScanner(
        sourceRoot: root.path,
        pathPrefix: _prefix,
        locThreshold: locThreshold,
      );

  /// Scaffold `<root>/<prefix>/<repo>/<pkg>/` and write [files] into it
  /// (relative path → contents). A `pubspec.yaml` is auto-added unless [files]
  /// already provides one.
  void package(
    String repo,
    String pkg, {
    required Map<String, String> files,
    String? pubspec,
  }) {
    final dir = Directory(p.joinAll([root.path, ...p.posix.split(_prefix), repo, pkg]));
    dir.createSync(recursive: true);
    final all = {
      if (pubspec != null || !files.containsKey('pubspec.yaml'))
        'pubspec.yaml': pubspec ?? 'name: $pkg\nversion: 0.0.1\n',
      ...files,
    };
    all.forEach((rel, content) {
      final f = File(p.join(dir.path, rel));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(content);
    });
  }

  String dartLines(int n) =>
      List.generate(n, (i) => 'final x$i = $i;').join('\n');

  group('status derivation', () {
    test('a small lib/ is not_started (stub)', () {
      package('basics', 'tom_stub', files: {
        'lib/tom_stub.dart': dartLines(10),
      }, pubspec: 'name: tom_stub\nversion: 0.0.1\npublish_to: none\n');

      final info = scanner().scanRepo('basics', repoIsPublic: true).single;
      expect(info.status, ComponentStatus.notStarted);
      expect(info.statusReason, contains('stub'));
    });

    test('no lib/ is not_started with the "no lib/" reason', () {
      package('basics', 'tom_empty',
          pubspec: 'name: tom_empty\nversion: 0.0.1\npublish_to: none\n',
          files: const {});

      final info = scanner().scanRepo('basics', repoIsPublic: true).single;
      expect(info.status, ComponentStatus.notStarted);
      expect(info.statusReason, 'no lib/');
    });

    test('real lib/ above the threshold is works', () {
      package('basics', 'tom_real', files: {
        'lib/tom_real.dart': dartLines(250),
      }, pubspec: 'name: tom_real\nversion: 0.1.0\npublish_to: none\n');

      final info = scanner().scanRepo('basics', repoIsPublic: true).single;
      expect(info.status, ComponentStatus.works);
      expect(info.statusReason, contains('250 LOC'));
    });

    test('publishable + public repo is published (even with a small lib/)', () {
      package('d4rt', 'tom_pub', files: {
        'lib/tom_pub.dart': dartLines(5),
      }, pubspec: 'name: tom_pub\nversion: 1.2.3\n');

      final info = scanner().scanRepo('d4rt', repoIsPublic: true).single;
      expect(info.status, ComponentStatus.published);
      expect(info.statusReason, contains('1.2.3'));
    });

    test('publishable but private repo falls back to lib/ size', () {
      package('d4rt', 'tom_pub', files: {
        'lib/tom_pub.dart': dartLines(5),
      }, pubspec: 'name: tom_pub\nversion: 1.2.3\n');

      final info = scanner().scanRepo('d4rt', repoIsPublic: false).single;
      expect(info.status, ComponentStatus.notStarted);
    });

    test('publish_to: none never counts as published', () {
      package('d4rt', 'tom_internal', files: {
        'lib/tom_internal.dart': dartLines(250),
      }, pubspec: 'name: tom_internal\nversion: 1.0.0\npublish_to: none\n');

      final info = scanner().scanRepo('d4rt', repoIsPublic: true).single;
      expect(info.status, ComponentStatus.works);
    });

    test('release.state in tom_project.yaml wins over everything', () {
      package('core', 'tom_released', files: {
        'lib/tom_released.dart': dartLines(5),
        'tom_project.yaml':
            'name: tom_released\nrelease:\n  state: released\n  version: 1.0.0\n',
      }, pubspec: 'name: tom_released\nversion: 1.0.0\n');

      final info = scanner().scanRepo('core', repoIsPublic: true).single;
      expect(info.status, ComponentStatus.released);
      expect(info.statusReason, 'release marker');
    });

    test('a RELEASED.md marker also yields released', () {
      package('core', 'tom_marked', files: {
        'lib/tom_marked.dart': dartLines(5),
        'RELEASED.md': '# Released 1.0.0\n',
      }, pubspec: 'name: tom_marked\nversion: 1.0.0\npublish_to: none\n');

      final info = scanner().scanRepo('core', repoIsPublic: true).single;
      expect(info.status, ComponentStatus.released);
    });
  });

  group('tolerating a missing tom_project.yaml', () {
    test('synthesises the record and flags hasProjectYaml=false', () {
      package('basics', 'tom_no_project', files: {
        'lib/tom_no_project.dart': dartLines(250),
        'LICENSE': 'MIT License\n\nPermission is hereby granted, free of charge',
      }, pubspec: 'name: tom_no_project\nversion: 0.1.0\npublish_to: none\n');

      final info = scanner().scanRepo('basics', repoIsPublic: true).single;
      expect(info.hasProjectYaml, isFalse);
      expect(info.status, ComponentStatus.works);
      expect(info.license, 'MIT');
    });
  });

  group('license sourcing', () {
    test('a curated tom_project.yaml license: is preferred over the body', () {
      package('basics', 'tom_curated', files: {
        'lib/tom_curated.dart': dartLines(5),
        'tom_project.yaml': 'name: tom_curated\nlicense: Apache-2.0\n',
        'LICENSE': 'Redistribution and use in source and binary forms\n'
            'Neither the name',
      }, pubspec: 'name: tom_curated\nversion: 0.1.0\npublish_to: none\n');

      final info = scanner().scanRepo('basics', repoIsPublic: true).single;
      expect(info.license, 'Apache-2.0');
    });

    test('falls back to classifying the LICENSE body', () {
      package('basics', 'tom_bsd', files: {
        'lib/tom_bsd.dart': dartLines(5),
        'tom_project.yaml': 'name: tom_bsd\n',
        'LICENSE': 'Copyright (c) 2015\nAll rights reserved.\n'
            'Redistribution and use in source and binary forms\n'
            'Neither the name',
      }, pubspec: 'name: tom_bsd\nversion: 0.1.0\npublish_to: none\n');

      final info = scanner().scanRepo('basics', repoIsPublic: true).single;
      expect(info.license, 'BSD-3-Clause');
    });

    test('unknown license is null', () {
      package('basics', 'tom_unknown', files: {
        'lib/tom_unknown.dart': dartLines(5),
      }, pubspec: 'name: tom_unknown\nversion: 0.1.0\npublish_to: none\n');

      final info = scanner().scanRepo('basics', repoIsPublic: true).single;
      expect(info.license, isNull);
    });
  });

  group('metadata capture', () {
    test('records sourcePath, name, version, description and links', () {
      package('d4rt', 'tom_meta', files: {
        'lib/tom_meta.dart': dartLines(5),
      }, pubspec: 'name: tom_meta\nversion: 2.0.0\n'
          'description: A meta package.\n'
          'repository: https://github.com/al-the-bear/d4rt\n'
          'homepage: https://enterprise-flutter.dev\n');

      final info = scanner().scanRepo('d4rt', repoIsPublic: true).single;
      expect(info.sourcePath, '$_prefix/d4rt/tom_meta');
      expect(info.name, 'tom_meta');
      expect(info.version, '2.0.0');
      expect(info.description, 'A meta package.');
      expect(info.links['repository'], 'https://github.com/al-the-bear/d4rt');
      expect(info.links['homepage'], 'https://enterprise-flutter.dev');
    });
  });

  group('discovery', () {
    test('returns packages sorted by folder name', () {
      package('basics', 'tom_zebra',
          files: {'lib/z.dart': dartLines(5)},
          pubspec: 'name: tom_zebra\nversion: 0.1.0\npublish_to: none\n');
      package('basics', 'tom_alpha',
          files: {'lib/a.dart': dartLines(5)},
          pubspec: 'name: tom_alpha\nversion: 0.1.0\npublish_to: none\n');

      final names =
          scanner().scanRepo('basics', repoIsPublic: true).map((p) => p.dirName);
      expect(names, ['tom_alpha', 'tom_zebra']);
    });

    test('an absent repo dir yields an empty list', () {
      expect(scanner().scanRepo('ghost', repoIsPublic: true), isEmpty);
    });

    test('skips child folders without a pubspec.yaml', () {
      package('basics', 'tom_real',
          files: {'lib/r.dart': dartLines(5)},
          pubspec: 'name: tom_real\nversion: 0.1.0\npublish_to: none\n');
      // A non-package sibling dir (e.g. docs) must be ignored.
      Directory(p.joinAll(
              [root.path, ...p.posix.split(_prefix), 'basics', 'doc']))
          .createSync(recursive: true);

      final packages = scanner().scanRepo('basics', repoIsPublic: true);
      expect(packages.map((p) => p.dirName), ['tom_real']);
    });
  });
}
