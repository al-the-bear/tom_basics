// BK-INC: steps that declare their inputs (`:compiler`, `:versioner`,
// `:runner`) skip a project whose inputs did not change since the step last
// succeeded there; `--force` runs it anyway. The fixture workspace is a git
// repository of its own under .dart_tool, and the run is rooted there (-R),
// so the workspace is never read. Its compile step appends a line to
// runs.log beside the projects (not one of their inputs), one per run.
@TestOn('vm')
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_kit/src/v2/incremental/step_inputs.dart';

final _buildkit = p.join(Directory.current.path, 'bin', 'buildkit.dart');

const _gitEnv = {
  'GIT_AUTHOR_NAME': 'Test',
  'GIT_AUTHOR_EMAIL': 'test@example.com',
  'GIT_COMMITTER_NAME': 'Test',
  'GIT_COMMITTER_EMAIL': 'test@example.com',
};

const _lock = '''
packages:
  helper:
    dependency: "direct main"
    description:
      path: "../helper"
      relative: true
    source: path
    version: "1.0.0"
sdks:
  dart: ">=3.0.0 <4.0.0"
''';

void main() {
  late Directory root;

  String path(String rel) => p.join(root.path, rel);
  void write(String rel, String text) => File(path(rel))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  /// The projects whose compile step ran, one line per run.
  List<String> runs() {
    final log = File(path('runs.log'));
    return log.existsSync()
        ? log.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList()
        : [];
  }

  setUp(() {
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync(recursive: true);
    root = base.createTempSync('incremental_steps_test_');
    write('buildkit_master.yaml', '');
    write('.gitignore', 'runs.log\n.dart_tool/\npubspec.lock\n');
    for (final name in ['alpha', 'beta']) {
      write('$name/pubspec.yaml', 'name: $name\nenvironment:\n  sdk: ^3.0.0\n');
      write('$name/bin/main.dart', 'void main() {}\n');
      write(
        '$name/buildkit.yaml',
        'compiler:\n  compiles:\n    - commandline:\n'
            '        - shell echo $name >> ../runs.log\n'
            '      files:\n        - bin/main.dart\n',
      );
      write('$name/pubspec.lock', _lock);
    }
    write('helper/lib/helper.dart', 'int helper() => 1;\n');
    _git(root.path, ['init', '-q', '-b', 'main']);
    _git(root.path, ['add', '-A']);
    _git(root.path, ['commit', '-q', '-m', 'fixture']);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<ProcessResult> buildkit(List<String> args) => Process.run('dart', [
    'run',
    _buildkit,
    '-R',
    root.path,
    '-s',
    root.path,
    '-r',
    ...args,
  ], workingDirectory: root.path);

  Future<String> compile([List<String> extra = const []]) async {
    final r = await buildkit([':compiler', ...extra]);
    final out = '${r.stdout}${r.stderr}';
    expect(r.exitCode, 0, reason: out);
    return out;
  }

  test('BK-INC-1: a second :compiler over unchanged projects skips them '
      '[2026-11-14]', () async {
    await compile();
    expect(runs()..sort(), ['alpha', 'beta']);
    final out = await compile();
    expect(runs(), hasLength(2), reason: out);
    expect(out, contains('alpha: :compiler up to date'));
    expect(out, contains('beta: :compiler up to date'));
    expect(
      File(path('alpha/.dart_tool/buildkit/steps.json')).readAsStringSync(),
      contains('"compiler"'),
    );
  });

  test('BK-INC-2: a changed source, lock or path dependency makes the '
      'project run again [2026-11-14]', () async {
    await compile();
    write('alpha/bin/main.dart', 'void main() { print(1); }\n');
    await compile();
    expect(runs().skip(2), ['alpha'], reason: 'a changed source');

    // pubspec.lock is gitignored here, as in a library: still an input.
    write('beta/pubspec.lock', '$_lock# changed\n');
    await compile();
    expect(runs().skip(3), ['beta'], reason: 'a changed lock');

    write('helper/lib/helper.dart', 'int helper() => 2;\n');
    await compile();
    expect(runs().skip(4).toList()..sort(), [
      'alpha',
      'beta',
    ], reason: 'a changed path dependency');

    write('alpha/lib/extra.dart', 'int extra = 1;\n');
    await compile();
    expect(runs().skip(6), ['alpha'], reason: 'a new untracked file');
  });

  test('BK-INC-3: --force runs every project; a failed run is not recorded '
      '[2026-11-14]', () async {
    await compile();
    await compile(['--force']);
    expect(runs(), hasLength(4));

    write(
      'alpha/buildkit.yaml',
      'compiler:\n  compiles:\n    - commandline:\n'
          '        - shell exit 1\n      files:\n        - bin/main.dart\n',
    );
    var r = await buildkit([':compiler']);
    expect(r.exitCode, isNot(0));
    expect(
      File(path('alpha/.dart_tool/buildkit/steps.json')).readAsStringSync(),
      isNot(contains('"compiler"')),
    );
    r = await buildkit([':compiler']);
    expect(r.exitCode, isNot(0), reason: 'a failed project runs again');
  });

  test('BK-INC-4: a dry run skips an up-to-date project and records nothing '
      '[2026-11-14]', () async {
    final dry = await compile(['--dry-run']);
    expect(runs(), isEmpty, reason: dry);
    expect(
      File(path('alpha/.dart_tool/buildkit/steps.json')).existsSync(),
      isFalse,
    );
    await compile();
    expect(
      await compile(['--dry-run']),
      contains('alpha: :compiler up to date'),
    );
  });

  test('BK-INC-5: a second :versioner over an unchanged project writes no '
      'new build [2026-11-14]', () async {
    write('alpha/buildkit.yaml', 'versioner:\n  variable-prefix: alpha\n');
    _git(root.path, ['add', '-A']);
    _git(root.path, ['commit', '-q', '-m', 'versioner']);
    var r = await buildkit([':versioner']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    final stamp = File(path('alpha/lib/src/version.versioner.dart'));
    final first = stamp.readAsStringSync();
    r = await buildkit([':versioner']);
    expect('${r.stdout}', contains('alpha: :versioner up to date'));
    expect(stamp.readAsStringSync(), first);
    r = await buildkit([':versioner', '--force']);
    expect(stamp.readAsStringSync(), isNot(first));
  });

  test('BK-INC-8: a later step that rewrites an input of an earlier one '
      'makes it run once more, then both skip [2026-11-14]', () async {
    write(
      'alpha/buildkit.yaml',
      '${File(path('alpha/buildkit.yaml')).readAsStringSync()}'
          'versioner:\n  variable-prefix: alpha\n',
    );
    _git(root.path, ['add', '-A']);
    _git(root.path, ['commit', '-q', '-m', 'versioner']);
    Future<String> both() async {
      final r = await buildkit(['-p', 'alpha', ':compiler', ':versioner']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      return '${r.stdout}';
    }

    await both();
    var out = await both();
    expect(runs(), ['alpha', 'alpha'], reason: out);
    expect(out, contains('alpha: :versioner up to date'));
    out = await both();
    expect(runs(), hasLength(2), reason: out);
    expect(out, contains('alpha: :compiler up to date'));
  });

  group('projectFiles', () {
    test('BK-INC-6: in git: tracked and untracked files, not the ignored '
        'ones; elsewhere: every file outside .dart_tool, build and hidden '
        'folders [2026-11-14]', () {
      write('alpha/new.txt', 'x');
      write('alpha/.dart_tool/x.json', '{}');
      expect(projectFiles(path('alpha')), [
        'bin/main.dart',
        'buildkit.yaml',
        'new.txt',
        'pubspec.yaml',
      ]);

      final outside = Directory.systemTemp.createTempSync('inc_walk_');
      addTearDown(() => outside.deleteSync(recursive: true));
      for (final rel in ['a.dart', 'lib/b.dart', 'build/c', '.hidden/d']) {
        File(p.join(outside.path, rel))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('');
      }
      expect(projectFiles(outside.path), ['a.dart', 'lib/b.dart']);
    });

    test('BK-INC-7: the path dependencies of a lock [2026-11-14]', () {
      expect(pathDependencies(path('alpha')), [
        (name: 'helper', path: path('helper')),
      ]);
    });
  });
}

void _git(String dir, List<String> args) {
  final r = Process.runSync(
    'git',
    args,
    workingDirectory: dir,
    environment: _gitEnv,
  );
  if (r.exitCode != 0) throw StateError('git ${args.join(' ')}: ${r.stderr}');
}
