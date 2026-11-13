/// The projects of a workspace as the tools see them (`listProjects`), the
/// machine-readable listing `buildkit :projects --json` prints for the VS Code
/// extension (build_tom build_cleanup8).
///
/// Test IDs: BB-PLS-1..7.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  late Directory ws;

  setUp(() {
    ws = Directory.systemTemp.createTempSync('bb_pls_');
    ws = Directory(ws.resolveSymbolicLinksSync());
  });
  tearDown(() => ws.deleteSync(recursive: true));

  void write(String rel, String text) => File(p.join(ws.path, rel))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  /// A workspace with a Dart package carrying its identity in buildkit.yaml,
  /// a plain Dart app, a Python and a Go project in a container folder, a
  /// skipped project, a fixture project inside a project and a zom_ test
  /// project.
  void standardWorkspace({String master = ''}) {
    write('buildkit_master.yaml', master);
    write('pkgs/core/pubspec.yaml', 'name: tom_core_x\nversion: 1.2.3\n');
    write('pkgs/core/lib/src/a.dart', '');
    write(
      'pkgs/core/buildkit.yaml',
      'project_id: TCX\nname: Tom Core X\ndescription: The core.\n',
    );
    write('pkgs/core/test/fixtures/inner/pubspec.yaml', 'name: inner\n');
    write('apps/tool/pubspec.yaml', 'name: tool_app\n');
    write('apps/tool/bin/tool.dart', 'void main() {}\n');
    write(
      'langs/py/pyproject.toml',
      '[project]\nname = "pyx"\nversion = "0.4.0"\n',
    );
    write('langs/go/go.mod', 'module example.com/a/gox\n');
    write('skipped/pubspec.yaml', 'name: skipped\n');
    write('skipped/buildkit_skip.yaml', '');
    write('zom_fixture/pubspec.yaml', 'name: zom_fixture\n');
    write('docs/README.md', '');
  }

  ProjectTraversalInfo info({bool recursive = false}) => ProjectTraversalInfo(
    scan: ws.path,
    executionRoot: ws.path,
    recursive: recursive,
    buildOrder: false,
  );

  Map<String, ListedProject> byPath(List<ListedProject> list) => {
    for (final e in list) e.path: e,
  };

  test('BB-PLS-1: every project the traversal selects, with its identity '
      'and natures; skipped, nested and zom_ projects are left out', () async {
    standardWorkspace();
    final listed = byPath(await listProjects(info()));
    expect(listed.keys.toSet(), {
      'pkgs/core',
      'apps/tool',
      'langs/py',
      'langs/go',
    });

    final core = listed['pkgs/core']!;
    expect(core.id, 'TCX', reason: 'project_id from buildkit.yaml');
    expect(core.name, 'Tom Core X', reason: 'name from buildkit.yaml');
    expect(core.description, 'The core.');
    expect(core.version, '1.2.3');
    expect(core.language, 'dart');
    expect(core.type, 'dart_package');
    expect(core.natures, containsAll(['dart_package', 'buildkit']));
    expect(core.absolutePath, p.join(ws.path, 'pkgs', 'core'));

    final tool = listed['apps/tool']!;
    expect(tool.id, 'tool_app', reason: 'no buildkit.yaml: the pubspec name');
    expect(tool.name, 'tool_app');
    expect(tool.type, 'dart_console');

    final py = listed['langs/py']!;
    expect(
      (py.id, py.language, py.type, py.version),
      ('pyx', 'python', 'python', '0.4.0'),
    );
    final go = listed['langs/go']!;
    expect((go.name, go.language, go.version), ('gox', 'go', null));
  });

  test(
    'BB-PLS-2: -r also lists the fixture projects inside projects',
    () async {
      standardWorkspace();
      final listed = byPath(await listProjects(info(recursive: true)));
      expect(listed.keys, contains('pkgs/core/test/fixtures/inner'));
    },
  );

  test('BB-PLS-3: listProjectsFor applies the navigation defaults of '
      'buildkit_master.yaml, like a project command; navigationDefaults: '
      'false leaves them out', () async {
    standardWorkspace(master: 'navigation:\n  exclude-projects:\n    - py\n');
    final previous = Directory.current;
    Directory.current = ws;
    try {
      final listed = await listProjectsFor(CliArgs(), executionRoot: ws.path);
      expect(listed.map((e) => e.path).toSet(), {
        'pkgs/core',
        'apps/tool',
        'langs/go',
      });
      final all = await listProjectsFor(
        CliArgs(),
        executionRoot: ws.path,
        navigationDefaults: false,
      );
      expect(all.map((e) => e.path).toSet(), {
        'pkgs/core',
        'apps/tool',
        'langs/py',
        'langs/go',
      }, reason: 'without the navigation defaults every project is listed');
    } finally {
      Directory.current = previous;
    }
  });

  test('BB-PLS-4: TraversalDefaults.load reads the navigation section, null '
      'without a workspace or section', () {
    write(
      'buildkit_master.yaml',
      'navigation:\n  recursive: true\n  exclude:\n    - "build/**"\n',
    );
    final defaults = TraversalDefaults.load(ws.path)!;
    expect(defaults.recursive, isTrue);
    expect(defaults.exclude, ['build/**']);
    File(p.join(ws.path, 'buildkit_master.yaml')).writeAsStringSync('x: 1\n');
    expect(TraversalDefaults.load(ws.path), isNull);
  });

  test('BB-PLS-5: toJson leaves absent fields out', () async {
    standardWorkspace();
    final go = byPath(await listProjects(info()))['langs/go']!;
    final json = go.toJson();
    expect(json.keys, isNot(contains('version')));
    expect(json.keys, isNot(contains('description')));
    expect(json['natures'], ['go']);
    expect(json['path'], 'langs/go');
  });

  test('BB-PLS-6: the primary nature: Flutter before Dart before the other '
      'languages', () {
    final f = FsFolder(path: ws.path);
    final dart = DartProjectFolder(f, projectName: 'd');
    final flutter = FlutterProjectFolder(f, projectName: 'f');
    final js = JavaScriptFolder(f);
    expect(primaryProjectNature([js, dart]), same(dart));
    expect(primaryProjectNature([dart, flutter]), same(flutter));
    expect(primaryProjectNature([GitFolder(f, currentBranch: 'main')]), isNull);
  });

  test('BB-PLS-7: nature names', () {
    final f = FsFolder(path: ws.path);
    expect(
      [
        FlutterProjectFolder(f, projectName: 'a'),
        DartConsoleFolder(f, projectName: 'a'),
        DartPackageFolder(f, projectName: 'a'),
        DartProjectFolder(f, projectName: 'a'),
        TypeScriptFolder(f),
        CppFolder(
          f,
          buildSystem: NativeBuildSystem.make,
          projectFile: 'Makefile',
        ),
        GitFolder(f, currentBranch: 'main'),
        BuildkitFolder(f),
        BuildkitMasterFolder(f),
      ].map(natureName),
      [
        'flutter',
        'dart_console',
        'dart_package',
        'dart',
        'typescript',
        'cpp',
        'git',
        'buildkit',
        'workspace_root',
      ],
    );
  });
}
