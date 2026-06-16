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

  String tsLines(int n) =>
      List.generate(n, (i) => 'const x$i = $i;').join('\n');

  /// Scaffold a TypeScript package `<root>/<prefix>/<repo>/<pkg>/` — discovered
  /// via `package.json` + `tsconfig.json` rather than a `pubspec.yaml`. A
  /// minimal `tsconfig.json` is auto-added; [packageJson] defaults to a bare
  /// `{ "name", "version" }`.
  void tsPackage(
    String repo,
    String pkg, {
    required Map<String, String> files,
    String? packageJson,
  }) {
    final dir = Directory(
        p.joinAll([root.path, ...p.posix.split(_prefix), repo, pkg]));
    dir.createSync(recursive: true);
    final all = {
      'tsconfig.json': '{ "compilerOptions": {} }\n',
      if (!files.containsKey('package.json'))
        'package.json':
            packageJson ?? '{ "name": "$pkg", "version": "0.0.1" }\n',
      ...files,
    };
    all.forEach((rel, content) {
      final f = File(p.join(dir.path, rel));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(content);
    });
  }

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

    test('a release.md marker also yields released', () {
      package('core', 'tom_marked', files: {
        'lib/tom_marked.dart': dartLines(5),
        'release.md': '# Released 1.0.0\n',
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

  group('metrics (§4.2.2)', () {
    test('loc counts non-blank lib/ lines and matches the >200-rule count', () {
      package('basics', 'tom_metrics', files: {
        'lib/tom_metrics.dart': dartLines(250),
      }, pubspec: 'name: tom_metrics\nversion: 0.1.0\npublish_to: none\n');

      final info = scanner().scanRepo('basics', repoIsPublic: true).single;
      // Same count the status ladder used (250 LOC ⇒ works).
      expect(info.metrics.loc, 250);
      expect(info.status, ComponentStatus.works);
    });

    test('loc excludes generated files (*.g.dart, *.freezed.dart)', () {
      package('basics', 'tom_gen', files: {
        'lib/tom_gen.dart': dartLines(30),
        'lib/tom_gen.g.dart': dartLines(900),
        'lib/model.freezed.dart': dartLines(500),
        'lib/config.options.dart': dartLines(400),
      }, pubspec: 'name: tom_gen\nversion: 0.1.0\npublish_to: none\n');

      final info = scanner().scanRepo('basics', repoIsPublic: true).single;
      expect(info.metrics.loc, 30); // generated lines ignored
    });

    test('tests counts test() and testWidgets() invocations', () {
      package('basics', 'tom_tested', files: {
        'lib/tom_tested.dart': dartLines(250),
        'test/a_test.dart': '''
import 'package:test/test.dart';
void main() {
  group('g', () {
    test('one', () {});
    test('two', () {});
  });
  testWidgets('three', (t) async {});
}
''',
      }, pubspec: 'name: tom_tested\nversion: 0.1.0\npublish_to: none\n');

      final info = scanner().scanRepo('basics', repoIsPublic: true).single;
      expect(info.metrics.tests, 3); // 2 test() + 1 testWidgets(), not group()
    });

    test('tests ignores test( in comments', () {
      package('basics', 'tom_commented', files: {
        'lib/tom_commented.dart': dartLines(250),
        'test/a_test.dart': '''
import 'package:test/test.dart';
void main() {
  // test('disabled', () {});
  test('real', () {});
}
''',
      }, pubspec: 'name: tom_commented\nversion: 0.1.0\npublish_to: none\n');

      final info = scanner().scanRepo('basics', repoIsPublic: true).single;
      expect(info.metrics.tests, 1);
    });

    test('testLoc counts non-blank test/ lines, generated excluded', () {
      package('basics', 'tom_testloc', files: {
        'lib/tom_testloc.dart': dartLines(250),
        'test/a_test.dart': dartLines(40),
        'test/mock.g.dart': dartLines(600),
      }, pubspec: 'name: tom_testloc\nversion: 0.1.0\npublish_to: none\n');

      final info = scanner().scanRepo('basics', repoIsPublic: true).single;
      expect(info.metrics.testLoc, 40); // generated mock not counted
    });

    test('a stub with no test/ reports zero tests and testLoc', () {
      package('basics', 'tom_stub', files: {
        'lib/tom_stub.dart': dartLines(10),
      }, pubspec: 'name: tom_stub\nversion: 0.0.1\npublish_to: none\n');

      final info = scanner().scanRepo('basics', repoIsPublic: true).single;
      expect(info.metrics.loc, 10);
      expect(info.metrics.tests, 0);
      expect(info.metrics.testLoc, 0);
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

    test('a package.json without tsconfig.json is not a package', () {
      // npm metadata alone (no TS config, no pubspec) is not a scannable dir.
      final dir = Directory(p.joinAll(
          [root.path, ...p.posix.split(_prefix), 'vscode', 'tom_loose']))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'package.json'))
          .writeAsStringSync('{ "name": "x" }\n');

      expect(scanner().scanRepo('vscode', repoIsPublic: true), isEmpty);
    });
  });

  group('typescript projects', () {
    test('discovers a package.json + tsconfig.json folder (no pubspec)', () {
      tsPackage('vscode', 'tom_ext', files: {
        'src/extension.ts': tsLines(5),
      });

      final info = scanner().scanRepo('vscode', repoIsPublic: true).single;
      expect(info.dirName, 'tom_ext');
      expect(info.name, 'tom_ext');
      // TypeScript is never a pub package.
      expect(info.publishTo, isNull);
    });

    test('name, version, description and license come from package.json', () {
      tsPackage('vscode', 'tom_ext', files: {
        'src/extension.ts': tsLines(5),
      }, packageJson: '{ "name": "@tom/ext", "version": "1.4.2", '
          '"description": "The Tom VS Code extension.", "license": "MIT" }\n');

      final info = scanner().scanRepo('vscode', repoIsPublic: true).single;
      expect(info.version, '1.4.2');
      expect(info.description, 'The Tom VS Code extension.');
      expect(info.license, 'MIT');
      // The folder name is the stable identifier, not the npm package name.
      expect(info.name, 'tom_ext');
    });

    test('a curated tom_project.yaml license wins over package.json', () {
      tsPackage('vscode', 'tom_ext', files: {
        'src/extension.ts': tsLines(5),
        'tom_project.yaml': 'name: tom_ext\nlicense: Apache-2.0\n',
      }, packageJson: '{ "name": "tom_ext", "license": "MIT" }\n');

      final info = scanner().scanRepo('vscode', repoIsPublic: true).single;
      expect(info.license, 'Apache-2.0');
      expect(info.hasProjectYaml, isTrue);
    });

    test('real src/ above the threshold is works (never published)', () {
      tsPackage('vscode', 'tom_ext', files: {
        'src/extension.ts': tsLines(250),
      });

      final info = scanner().scanRepo('vscode', repoIsPublic: true).single;
      expect(info.status, ComponentStatus.works);
      expect(info.statusReason, 'src/ 250 LOC');
      expect(info.metrics.loc, 250);
    });

    test('a small src/ is not_started (stub) with the src/ reason', () {
      tsPackage('vscode', 'tom_stub', files: {
        'src/extension.ts': tsLines(10),
      });

      final info = scanner().scanRepo('vscode', repoIsPublic: true).single;
      expect(info.status, ComponentStatus.notStarted);
      expect(info.statusReason, contains('stub'));
    });

    test('no src/ is not_started with the "no src/" reason', () {
      tsPackage('vscode', 'tom_empty', files: const {});

      final info = scanner().scanRepo('vscode', repoIsPublic: true).single;
      expect(info.status, ComponentStatus.notStarted);
      expect(info.statusReason, 'no src/');
    });

    test('a release.md marker yields released', () {
      tsPackage('vscode', 'tom_done', files: {
        'src/extension.ts': tsLines(5),
        'release.md': '# Released 1.0.0\n',
      });

      final info = scanner().scanRepo('vscode', repoIsPublic: true).single;
      expect(info.status, ComponentStatus.released);
    });

    test('loc excludes *.d.ts and src/ test files; tests come from them', () {
      tsPackage('vscode', 'tom_ext', files: {
        'src/extension.ts': tsLines(40),
        'src/types.d.ts': tsLines(900),
        'src/extension.test.ts': '''
import { test } from 'vitest';
test('one', () => {});
test('two', () => {});
it('three', () => {});
''',
      });

      final info = scanner().scanRepo('vscode', repoIsPublic: true).single;
      expect(info.metrics.loc, 40); // declarations and test file excluded
      expect(info.metrics.tests, 3); // 2 test() + 1 it()
      expect(info.metrics.testLoc, greaterThan(0));
    });

    test('tests and testLoc also come from a sibling test/ dir', () {
      tsPackage('vscode', 'tom_ext', files: {
        'src/extension.ts': tsLines(250),
        'test/extension.spec.ts': '''
import { it } from 'vitest';
// it('disabled', () => {});
it('real', () => {});
''',
      });

      final info = scanner().scanRepo('vscode', repoIsPublic: true).single;
      expect(info.metrics.tests, 1); // commented it() ignored
      expect(info.metrics.testLoc, greaterThan(0));
    });

    test('links read repository (object form) and homepage from package.json',
        () {
      tsPackage('vscode', 'tom_ext', files: {
        'src/extension.ts': tsLines(5),
      }, packageJson: '''
{
  "name": "tom_ext",
  "repository": { "type": "git", "url": "https://github.com/al-the-bear/vscode" },
  "homepage": "https://enterprise-flutter.dev"
}
''');

      final info = scanner().scanRepo('vscode', repoIsPublic: true).single;
      expect(info.links['repository'], 'https://github.com/al-the-bear/vscode');
      expect(info.links['homepage'], 'https://enterprise-flutter.dev');
    });

    test('links read a bare repository string', () {
      tsPackage('vscode', 'tom_ext', files: {
        'src/extension.ts': tsLines(5),
      }, packageJson: '{ "name": "tom_ext", '
          '"repository": "https://github.com/al-the-bear/vscode" }\n');

      final info = scanner().scanRepo('vscode', repoIsPublic: true).single;
      expect(info.links['repository'], 'https://github.com/al-the-bear/vscode');
    });

    test('Dart and TypeScript packages coexist in one repo', () {
      package('vscode', 'tom_bridge', files: {
        'lib/tom_bridge.dart': dartLines(250),
      }, pubspec: 'name: tom_bridge\nversion: 0.1.0\npublish_to: none\n');
      tsPackage('vscode', 'tom_ext', files: {
        'src/extension.ts': tsLines(250),
      });

      final packages = scanner().scanRepo('vscode', repoIsPublic: true);
      expect(packages.map((p) => p.dirName), ['tom_bridge', 'tom_ext']);
      final bridge = packages.firstWhere((p) => p.dirName == 'tom_bridge');
      final ext = packages.firstWhere((p) => p.dirName == 'tom_ext');
      expect(bridge.statusReason, 'lib/ 250 LOC');
      expect(ext.statusReason, 'src/ 250 LOC');
    });
  });
}
