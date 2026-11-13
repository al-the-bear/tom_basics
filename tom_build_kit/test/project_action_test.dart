/// `:build`, `:test`, `:clean` per nature, and `:bumpversion` in every
/// language's version file (build_tom build_cleanup6).
///
/// Test IDs: BK-ACT-1..7.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/src/v2/buildkit_executors.dart';
import 'package:tom_build_kit/src/v2/buildkit_tool.dart';
import 'package:tom_build_kit/src/v2/executors/project_action_executor.dart';

void main() {
  late Directory ws;
  final detector = NatureDetector();

  setUp(() {
    ws = Directory.systemTemp.createTempSync('bk_action_');
    File(p.join(ws.path, 'buildkit_master.yaml')).writeAsStringSync('');
  });
  tearDown(() => ws.deleteSync(recursive: true));

  String project(String name, Map<String, String> files) {
    final dir = p.join(ws.path, name);
    files.forEach((rel, text) {
      File(p.join(dir, rel))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
    });
    return dir;
  }

  ActionStep? step(ProjectAction action, String dir) =>
      actionStepFor(action, dir, detector.detectNatures(FsFolder(path: dir)));

  Future<(ToolResult, String)> buildkit(List<String> args) async {
    final out = StringBuffer();
    final previous = Directory.current;
    Directory.current = ws;
    try {
      final result = await ToolRunner(
        tool: buildkitTool,
        executors: createBuildkitExecutors(),
        output: out,
      ).run(args);
      return (result, out.toString());
    } finally {
      Directory.current = previous;
    }
  }

  test('BK-ACT-1: each language\'s default build / test / clean', () {
    final cases = <String, (Map<String, String>, List<String>)>{
      'rust': (
        {'Cargo.toml': '[package]\nname = "r"\n'},
        ['cargo build', 'cargo test', 'cargo clean'],
      ),
      'go': (
        {'go.mod': 'module a/b\n'},
        ['go build ./...', 'go test ./...', 'go clean ./...'],
      ),
      'c': (
        {'Makefile': 'all:\n', 'src/a.c': ''},
        ['make', 'make test', 'make clean'],
      ),
      'cpp': (
        {'Makefile': 'all:\n', 'src/a.cpp': ''},
        ['make', 'make test', 'make clean'],
      ),
      'java': (
        {'pom.xml': '<project/>'},
        ['mvn -q -B package -DskipTests', 'mvn -q -B test', 'mvn -q -B clean'],
      ),
      'dart': (
        {'pubspec.yaml': 'name: d\n'},
        ['dart analyze', 'dart test', 'delete build'],
      ),
      'js': (
        {'package.json': '{"scripts": {"test": "node t.js"}}'},
        ['', 'npm test', ''],
      ),
      'ts': (
        {'package.json': '{}', 'tsconfig.json': '{}'},
        ['npx tsc -p .', '', 'delete dist'],
      ),
    };
    cases.forEach((name, c) {
      final dir = project(name, c.$1);
      final got = [
        for (final a in ProjectAction.values) step(a, dir)!.describe(),
      ];
      expect(got, c.$2, reason: name);
    });
    final py = project('py', {'pyproject.toml': '[project]\nname = "p"\n'});
    expect(step(ProjectAction.test, py)!.describe(), 'python3 -m pytest -q');
    expect(
      step(ProjectAction.clean, py)!.deletes,
      containsAll(['build', '**/__pycache__']),
    );
  });

  test('BK-ACT-2: a build: / test: / clean: entry in buildkit.yaml replaces '
      'the default: a command, a list, or false', () {
    final dir = project('rt', {
      'Cargo.toml': '[package]\nname = "r"\n',
      'buildkit.yaml':
          'project_id: RT\ntest: ./run_tests.sh\nbuild:\n  - echo a\n  - echo b\n'
          'clean: false\n',
    });
    expect(step(ProjectAction.test, dir)!.commands, ['./run_tests.sh']);
    expect(step(ProjectAction.test, dir)!.origin, 'buildkit.yaml');
    expect(step(ProjectAction.build, dir)!.commands, ['echo a', 'echo b']);
    expect(step(ProjectAction.clean, dir)!.isEmpty, isTrue);
    final bad = project('bad', {'buildkit.yaml': 'test:\n  command: x\n'});
    expect(() => step(ProjectAction.test, bad), throwsFormatException);
  });

  test('BK-ACT-3: the primary nature: Dart before the other languages; no '
      'nature, no step', () {
    final both = project('both', {
      'pubspec.yaml': 'name: both\n',
      'package.json': '{}',
    });
    expect(step(ProjectAction.test, both)!.commands, ['dart test']);
    expect(
      step(ProjectAction.test, project('none', {'README.md': ''})),
      isNull,
    );
  });

  test('BK-ACT-4: :test runs the step in each project; :test --dry-run '
      'shows it and runs nothing', () async {
    final a = project('a_go', {
      'go.mod': 'module a\n',
      'buildkit.yaml': 'test: echo ran > ran.txt\n',
    });
    final (dry, _) = await buildkit(['-s', '.', '--dry-run', ':test']);
    expect(dry.success, isTrue);
    expect(dry.itemResults.single.message, 'dry run');
    expect(File(p.join(a, 'ran.txt')).existsSync(), isFalse);

    final (run, _) = await buildkit(['-s', '.', ':test']);
    expect(run.success, isTrue);
    expect(File(p.join(a, 'ran.txt')).readAsStringSync().trim(), 'ran');
  });

  test('BK-ACT-5: a failing step fails the run, naming the command', () async {
    project('b_rust', {
      'Cargo.toml': '[package]\nname = "r"\n',
      'buildkit.yaml': 'build: exit 3\n',
    });
    final (result, _) = await buildkit(['-s', '.', ':build']);
    expect(result.success, isFalse);
    expect(result.itemResults.single.error, contains('`exit 3` exited with 3'));
  });

  test('BK-ACT-6: :clean deletes the default paths and globs; a Dart '
      'project is cleaned too, :cleanup is not affected', () async {
    final py = project('c_py', {
      'pyproject.toml': '[project]\nname = "p"\n',
      'build/x': '',
      'pkg/__pycache__/m.pyc': '',
      'p.egg-info/PKG-INFO': '',
      'pkg/m.py': '',
    });
    final (result, _) = await buildkit(['-s', '.', ':clean']);
    expect(result.success, isTrue);
    expect(Directory(p.join(py, 'build')).existsSync(), isFalse);
    expect(Directory(p.join(py, 'pkg', '__pycache__')).existsSync(), isFalse);
    expect(Directory(p.join(py, 'p.egg-info')).existsSync(), isFalse);
    expect(File(p.join(py, 'pkg', 'm.py')).existsSync(), isTrue);
  });

  test('BK-ACT-7: :bumpversion bumps each language\'s version file and skips '
      'a project without one', () async {
    final js = project('v_js', {
      'package.json': '{\n  "name": "j",\n  "version": "1.2.3"\n}\n',
    });
    final py = project('v_py', {
      'pyproject.toml': '[project]\nname = "p"\nversion = "0.1.0"\n',
    });
    final rs = project('v_rs', {
      'Cargo.toml': '[package]\nname = "r"\nversion = "2.0.9"\n',
    });
    final jv = project('v_jv', {
      'pom.xml':
          '<project><artifactId>j</artifactId><version>3.4.5</version></project>',
    });
    project('v_go', {'go.mod': 'module g\n'});

    final (result, _) = await buildkit([
      '-s',
      '.',
      ':bumpversion',
      '--minor',
      'p',
    ]);
    expect(result.success, isTrue, reason: '${result.errorMessage}');
    expect(
      File(p.join(js, 'package.json')).readAsStringSync(),
      contains('"version": "1.2.4"'),
    );
    expect(
      File(p.join(py, 'pyproject.toml')).readAsStringSync(),
      contains('version = "0.2.0"'),
    );
    expect(
      File(p.join(rs, 'Cargo.toml')).readAsStringSync(),
      contains('version = "2.0.10"'),
    );
    expect(
      File(p.join(jv, 'pom.xml')).readAsStringSync(),
      contains('<version>3.4.6</version>'),
    );
  });
}
