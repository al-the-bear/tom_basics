// BK-DOCCHK: `buildkit :doccheck` — the documents the guidelines ask of a
// package. BK-DOCCHK-1..5 call the check on fixture packages; 6..8 run the
// real executable, rooted at the fixtures under .dart_tool (-R) so the
// workspace is never read.
@TestOn('vm')
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_kit/src/doccheck/doc_check.dart';

final _buildkit = p.join(Directory.current.path, 'bin', 'buildkit.dart');

const _readme = '''
# shop

> **Shop** is part of the Tom framework. See [LICENSE](LICENSE).

A shop.

## Features

| Feature | What |
| ------- | ---- |
| Carts | Hold items. |

## Installation

```yaml
dependencies:
  shop: ^1.0.0
```

## Quick start

```dart
print(Cart().total); // 0
```

## Further documentation

- [User guide](doc/shop_user_guide.md)
''';

/// Every document the guidelines ask for.
const _complete = {
  'README.md': _readme,
  'CHANGELOG.md': '# Changelog\n\n## 1.0.0\n\n- First.\n',
  'example/shop_example.dart': 'void main() {}\n',
  'doc/shop_user_guide.md': '# Shop User Guide\n',
  '_copilot_guidelines/index.md': '# Shop guidelines\n',
};

void main() {
  late Directory root;

  setUp(() {
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync(recursive: true);
    root = base.createTempSync('doccheck_test_');
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A package [name] with [files] and, when given, [buildkit] as its
  /// buildkit.yaml.
  String package(String name, Map<String, String> files, {String? buildkit}) {
    final dir = p.join(root.path, name);
    ({
      'pubspec.yaml': 'name: $name\nenvironment:\n  sdk: ^3.0.0\n',
      'lib/$name.dart': 'class A {}\n',
      'buildkit.yaml': ?buildkit,
      ...files,
    }).forEach((path, text) {
      File(p.join(dir, path))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
    });
    return dir;
  }

  List<String> gaps(
    String dir, [
    DocCheckConfig config = const DocCheckConfig(),
  ]) => [for (final g in checkPackageDocs(dir, config).gaps) '$g'];

  test('BK-DOCCHK-1: a complete package has no gap [2026-11-14]', () {
    final report = checkPackageDocs(
      package('shop', _complete),
      const DocCheckConfig(),
    );
    expect(report.gaps, isEmpty, reason: '${report.gaps}');
    expect(report.checked, kDocChecks);
  });

  test('BK-DOCCHK-2: an incomplete package: every missing document and '
      'section is named [2026-11-14]', () {
    final dir = package('bare', {
      'README.md': '# bare\n\nNo blockquote.\n\n## Features\n\n- one\n',
      '_copilot_guidelines/build.md': '# Build\n',
    });
    expect(gaps(dir), [
      'attribution: README.md has no attribution blockquote under its title',
      'readme-sections: README.md has no "Installation" section',
      'readme-sections: README.md has no "Quick start" section',
      'readme-sections: README.md has no "Documentation" section',
      'changelog: no CHANGELOG.md',
      'example: no example/ with a .dart file',
      'doc: no user documentation (doc/*.md)',
      'guidelines-index: _copilot_guidelines/ has no index.md',
    ]);
    expect(gaps(package('nothing', {})), contains('readme: no README.md'));
  });

  test('BK-DOCCHK-3: sections match by their words in any case and with '
      'hyphens; headings in code and a blockquote after the first section do '
      'not count; no _copilot_guidelines/ needs no index [2026-11-14]', () {
    final dir = package('shop', {
      ..._complete,
      'README.md':
          '# shop\n\n## Intro\n\n> late quote\n\n'
          '## FEATURES\n\n## Installation and setup\n\n## Quick-Start\n\n'
          '```markdown\n## Documentation\n```\n',
    });
    Directory(p.join(dir, '_copilot_guidelines')).deleteSync(recursive: true);
    expect(gaps(dir), [
      'attribution: README.md has no attribution blockquote under its title',
      'readme-sections: README.md has no "Documentation" section',
    ]);
  });

  test('BK-DOCCHK-4: the configuration: the workspace\'s checks and '
      'sections, a package\'s own sections, its exclusions and its skip, '
      'each with a reason [2026-11-14]', () {
    File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync(
      'doccheck:\n  checks: [readme, readme-sections, changelog]\n'
      '  readme-sections: [Overview]\n',
    );
    final dir = package(
      'tool',
      {'README.md': '# tool\n\n## Overview\n\n## Usage\n'},
      buildkit: 'doccheck:\n  exclude:\n    changelog: released with the kit\n',
    );
    var config = DocCheckConfig.load(dir, workspaceRoot: root.path);
    expect(config.errors, isEmpty);
    expect(config.checks, ['readme', 'readme-sections', 'changelog']);
    expect(config.readmeSections, ['Overview']);
    expect(config.exclude, {'changelog': 'released with the kit'});
    final report = checkPackageDocs(dir, config);
    expect(report.gaps, isEmpty);
    expect(report.checked, ['readme', 'readme-sections']);
    expect(report.excluded, {'changelog': 'released with the kit'});

    final own = package('own', {
      'README.md': '# own\n\n## Usage\n',
    }, buildkit: 'doccheck:\n  readme-sections: [Usage]\n');
    expect(DocCheckConfig.load(own, workspaceRoot: root.path).readmeSections, [
      'Usage',
    ]);

    final fixture = package(
      'fixture',
      {},
      buildkit: 'doccheck:\n  skip: a test fixture\n',
    );
    config = DocCheckConfig.load(fixture, workspaceRoot: root.path);
    expect(config.skip, 'a test fixture');
  });

  test('BK-DOCCHK-5: an unknown check, an exclusion or skip without a reason '
      'are configuration errors, never opt-outs [2026-11-14]', () {
    final dir = package(
      'wrong',
      {},
      buildkit: '''
doccheck:
  skip: true
  exclude:
    examples: typo
    doc:
''',
    );
    final config = DocCheckConfig.load(dir);
    expect(config.skip, isNull);
    expect(config.exclude, isEmpty);
    expect(config.errors, hasLength(3));
    expect(config.errors.join('\n'), contains('unknown check "examples"'));
    expect(
      config.errors.join('\n'),
      contains('doccheck.exclude.doc needs the reason'),
    );
    expect(
      config.errors.join('\n'),
      contains('doccheck.skip needs the reason'),
    );
  });

  group('the command', () {
    setUp(() {
      File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
    });

    Future<ProcessResult> buildkit(List<String> args) => Process.run('dart', [
      'run',
      _buildkit,
      '-R',
      root.path,
      '-s',
      root.path,
      ...args,
    ], workingDirectory: root.path);

    String out(ProcessResult r) => '${r.stdout}${r.stderr}';

    test('BK-DOCCHK-6: the gaps per package; --strict exits 1, without it '
        'the run passes [2026-11-14]', () async {
      package('shop', _complete);
      package('bare', {'README.md': '# bare\n\n> quote\n'});
      var r = await buildkit([':doccheck']);
      expect(r.exitCode, 0, reason: out(r));
      final text = out(r);
      expect(text, contains('shop: complete — 7 checks'));
      expect(text, contains('bare: missing: changelog: no CHANGELOG.md'));
      expect(text, contains('bare: 7 gap(s) in 7 checks'));

      r = await buildkit([':doccheck', '--strict']);
      expect(r.exitCode, 1, reason: out(r));
    });

    test('BK-DOCCHK-7: an opted-out package is skipped with its reason and '
        'none of its gaps is reported; an excluded check is named '
        '[2026-11-14]', () async {
      package(
        'shop',
        {..._complete}..remove('example/shop_example.dart'),
        buildkit: 'doccheck:\n  exclude:\n    example: a CLI tool\n',
      );
      package('fixture', {}, buildkit: 'doccheck:\n  skip: a test fixture\n');
      final r = await buildkit([':doccheck', '--strict']);
      expect(r.exitCode, 0, reason: out(r));
      final text = out(r);
      expect(text, contains('fixture: skipped — a test fixture'));
      expect(text, isNot(contains('fixture: missing')));
      expect(text, contains('shop: complete — 6 checks; excluded: example'));
    });

    test('BK-DOCCHK-8: a configuration error fails the package even without '
        '--strict [2026-11-14]', () async {
      package(
        'wrong',
        _complete,
        buildkit: 'doccheck:\n  exclude:\n    examples: typo\n',
      );
      final r = await buildkit([':doccheck']);
      expect(r.exitCode, 1, reason: out(r));
      expect(
        out(r),
        contains(
          'wrong: configuration: buildkit.yaml doccheck.exclude: unknown check "examples"',
        ),
      );
    });
  });
}
