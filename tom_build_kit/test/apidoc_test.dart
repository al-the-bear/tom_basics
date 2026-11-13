// BK-APIDOC: `buildkit :apidoc` — dartdoc API documentation per package,
// outside doc/, with its warnings counted. BK-APIDOC-1..3 read dartdoc's
// output; 4..9 run the real executable on fixture packages under
// .dart_tool, rooted there (-R) so the workspace is never read.
@TestOn('vm')
@Timeout(Duration(minutes: 6))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_kit/src/v2/executors/apidoc_executor.dart';

final _buildkit = p.join(Directory.current.path, 'bin', 'buildkit.dart');

void main() {
  group('reading dartdoc', () {
    test('BK-APIDOC-1: warnings, unresolved references, libraries and '
        'undocumented elements [2026-11-13]', () {
      const output = '''
Generating docs for library good.dart from file:///x/lib/good.dart...
  warning: unresolved doc reference [Missing]
    from good.A: (file:///x/lib/good.dart:2:7)
  warning: ambiguous reexport of A
Found 2 warnings and 0 errors.
Documented 1 public library in 4.0 seconds
Success! Docs generated into /x/build/api
''';
      const index = '''
[{"name":"good","kind":9,"desc":"The library."},
 {"name":"A","kind":3,"desc":"An A."},
 {"name":"B","kind":3,"desc":""},
 {"name":"c","kind":10}]''';
      final r = DartdocResult.parse(
        0,
        output,
        indexJson: index,
        packageDir: '/x',
      );
      expect((r.warnings, r.errors, r.libraries), (2, 0, 1));
      expect(r.unresolvedReferences, 1);
      expect((r.elements, r.undocumented), (4, 2));
      expect(r.findings, [
        'warning: unresolved doc reference [Missing] '
            '(good.A: (lib/good.dart:2:7))',
        'warning: ambiguous reexport of A',
      ]);
      expect(r.failure, isNull);
      expect(
        r.describe(),
        '1 library, 2 warnings (1 unresolved reference), '
        '2 of 4 public elements undocumented',
      );
    });

    test('BK-APIDOC-2: a non-zero exit, dartdoc errors and no public '
        'library are failures [2026-11-13]', () {
      expect(
        DartdocResult.parse(
          1,
          '  error: unresolved doc reference [Missing]\n'
          'Found 0 warnings and 1 error.\n',
        ).failure,
        'dart doc failed (exit 1, 1 error(s))',
      );
      expect(
        DartdocResult.parse(0, 'Found 0 warnings and 2 errors.\n').failure,
        'dart doc: 2 error(s)',
      );
      expect(
        DartdocResult.parse(
          0,
          'Found 1 warning and 0 errors.\n'
          'Documented 0 public libraries in 0.0 seconds\n',
        ).failure,
        'no public library to document',
      );
    });

    test('BK-APIDOC-3: the output folder stays in the package and out of '
        'doc/ [2026-11-13]', () {
      expect(refuseApidocOutput('build/api'), isNull);
      expect(refuseApidocOutput('build/apidoc'), isNull);
      expect(refuseApidocOutput('doc/api'), contains('doc/'));
      expect(refuseApidocOutput('build/doc/api'), contains('doc/'));
      expect(refuseApidocOutput('../elsewhere'), contains('inside'));
      expect(refuseApidocOutput('.'), contains('inside'));
      expect(refuseApidocOutput(p.absolute('x')), contains('relative'));
    });
  });

  group('the command', () {
    late Directory root;

    setUp(() {
      final base = Directory(p.join(Directory.current.path, '.dart_tool'))
        ..createSync(recursive: true);
      root = base.createTempSync('apidoc_test_');
      File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
    });
    tearDown(() => root.deleteSync(recursive: true));

    /// A resolved package [name] with [files] (relative to the package).
    Future<String> package(String name, Map<String, String> files) async {
      final dir = p.join(root.path, name);
      ({
        'pubspec.yaml':
            'name: ${p.basename(name)}\nenvironment:\n  sdk: ^3.0.0\n',
        ...files,
      }).forEach((path, text) {
        File(p.join(dir, path))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(text);
      });
      final got = await Process.run('dart', [
        'pub',
        'get',
        '--offline',
      ], workingDirectory: dir);
      expect(got.exitCode, 0, reason: '${got.stderr}');
      return dir;
    }

    Future<ProcessResult> buildkit(
      List<String> args, {
      Map<String, String>? environment,
    }) => Process.run(
      'dart',
      ['run', _buildkit, '-R', root.path, '-s', root.path, ...args],
      workingDirectory: root.path,
      environment: environment,
    );

    String out(ProcessResult r) => '${r.stdout}${r.stderr}';

    test('BK-APIDOC-4: writes the API docs to build/api, not doc/, and '
        'prints the warnings per package [2026-11-13]', () async {
      final good = await package('good', {
        'lib/good.dart': '/// Refers to [Missing].\nclass A {}\n\nclass B {}\n',
      });
      final r = await buildkit([':apidoc']);
      expect(r.exitCode, 0, reason: out(r));
      expect(
        File(p.join(good, 'build', 'api', 'index.html')).existsSync(),
        isTrue,
      );
      expect(Directory(p.join(good, 'doc')).existsSync(), isFalse);
      final text = out(r);
      expect(
        text,
        contains(
          'good: warning: unresolved doc reference [Missing] '
          '(good.A: (lib/good.dart:2:7))',
        ),
      );
      expect(
        text,
        contains('good: ok — 1 library, 1 warning (1 unresolved reference)'),
      );
      expect(text, contains('public elements undocumented -> build/api'));
    });

    test('BK-APIDOC-5: a package whose dartdoc fails fails the run; the '
        'other packages are still documented [2026-11-13]', () async {
      final good = await package('good', {
        'lib/good.dart': '/// A.\nclass A {}\n',
      });
      await package('strict', {
        'lib/strict.dart': '/// See [Missing].\nclass A {}\n',
        // Turns the unresolved reference into an error: dartdoc exits 1.
        'dartdoc_options.yaml':
            'dartdoc:\n  errors:\n    - unresolved-doc-reference\n',
      });
      final r = await buildkit([':apidoc']);
      expect(r.exitCode, isNot(0), reason: out(r));
      final text = out(r);
      expect(text, contains('strict: error: unresolved doc reference'));
      expect(text, contains('strict: dart doc failed (exit 1, 1 error(s))'));
      expect(text, contains('good: ok'));
      expect(
        File(p.join(good, 'build', 'api', 'index.html')).existsSync(),
        isTrue,
      );
    });

    test('BK-APIDOC-6: an unresolved package and an output in doc/ are '
        'refused before dartdoc runs [2026-11-13]', () async {
      final bare = p.join(root.path, 'bare');
      File(p.join(bare, 'pubspec.yaml'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('name: bare\nenvironment:\n  sdk: ^3.0.0\n');
      File(p.join(bare, 'lib', 'bare.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('class A {}\n');
      var r = await buildkit([':apidoc']);
      expect(r.exitCode, isNot(0));
      expect(out(r), contains('run buildkit :pubget first'));
      expect(Directory(p.join(bare, 'build')).existsSync(), isFalse);

      final good = await package('good', {'lib/good.dart': 'class A {}\n'});
      r = await buildkit(['-p', 'good', ':apidoc', '--output', 'doc/api']);
      expect(r.exitCode, isNot(0));
      expect(out(r), contains('hand-authored'));
      expect(Directory(p.join(good, 'doc')).existsSync(), isFalse);
    });

    test('BK-APIDOC-7: --dry-run names the dart doc call and writes nothing '
        '[2026-11-13]', () async {
      final good = await package('good', {'lib/good.dart': 'class A {}\n'});
      final r = await buildkit(['--dry-run', ':apidoc']);
      expect(r.exitCode, 0, reason: out(r));
      expect(out(r), contains('[DRY RUN] good: dart doc --output'));
      expect(Directory(p.join(good, 'build')).existsSync(), isFalse);
    });

    test('BK-APIDOC-8: runs as a pipeline step [2026-11-13]', () async {
      File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync(
        'buildkit:\n'
        '  pipelines:\n'
        '    docs:\n'
        '      executable: true\n'
        '      core:\n'
        '        - commands:\n'
        '            - buildkit :apidoc\n',
      );
      final good = await package('good', {
        'lib/good.dart': '/// A.\nclass A {}\n',
      });
      // A pipeline's `buildkit` step spawns the buildkit on PATH: this
      // source's, compiled, so the step knows :apidoc.
      final bin = Directory(p.join(root.path, 'bin'))..createSync();
      final compiled = await Process.run('dart', [
        'compile',
        'exe',
        _buildkit,
        '-o',
        p.join(bin.path, Platform.isWindows ? 'buildkit.exe' : 'buildkit'),
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
      final r = await buildkit(
        ['docs'],
        environment: {
          'PATH':
              '${bin.path}${Platform.isWindows ? ';' : ':'}'
              '${Platform.environment['PATH']}',
        },
      );
      expect(r.exitCode, 0, reason: out(r));
      expect(out(r), contains('good: ok'));
      expect(
        File(p.join(good, 'build', 'api', 'index.html')).existsSync(),
        isTrue,
      );
    });

    test('BK-APIDOC-9: with a relative --scan the docs land in each '
        'package\'s build/api; a package without lib/ is skipped, not '
        'failed [2026-11-13]', () async {
      final good = await package('pkgs/good', {
        'lib/good.dart': '/// A.\nclass A {}\n',
      });
      final samples = p.join(root.path, 'pkgs', 'samples');
      File(p.join(samples, 'pubspec.yaml'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('name: samples\nenvironment:\n  sdk: ^3.0.0\n');
      // Run from the fixture root with a relative scan path and no -R, as
      // `buildkit -s tom_ai/basics :apidoc` runs from the workspace root.
      final r = await Process.run('dart', [
        'run',
        _buildkit,
        '-s',
        'pkgs',
        ':apidoc',
      ], workingDirectory: root.path);
      expect(r.exitCode, 0, reason: out(r));
      expect(
        File(p.join(good, 'build', 'api', 'index.html')).existsSync(),
        isTrue,
        reason: out(r),
      );
      expect(Directory(p.join(good, 'pkgs')).existsSync(), isFalse);
      expect(out(r), contains('samples: skipped — no lib/'));
      expect(Directory(p.join(samples, 'build')).existsSync(), isFalse);
    });
  });
}
