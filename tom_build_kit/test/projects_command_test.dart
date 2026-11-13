/// `:projects`: the projects buildkit works on, as a table or one JSON
/// document (build_tom build_cleanup8; the VS Code extension reads the JSON).
///
/// Test IDs: BK-PRJ-1..5.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/src/v2/buildkit_executors.dart';
import 'package:tom_build_kit/src/v2/buildkit_tool.dart';
import 'package:tom_build_kit/src/v2/executors/projects_executor.dart';

void main() {
  late Directory ws;

  setUp(() {
    ws = Directory.systemTemp.createTempSync('bk_projects_');
    ws = Directory(ws.resolveSymbolicLinksSync());
    void write(String rel, String text) => File(p.join(ws.path, rel))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
    write('buildkit_master.yaml', '');
    write('pkgs/core/pubspec.yaml', 'name: core_x\nversion: 2.0.0\n');
    write('pkgs/core/lib/src/a.dart', '');
    write('pkgs/core/buildkit.yaml', 'project_id: CX\nname: Core X\n');
    write('pkgs/core/test/fixture/pubspec.yaml', 'name: fixture\n');
    write('rt/py/pyproject.toml', '[project]\nname = "pyrt"\n');
    write('skipped/pubspec.yaml', 'name: skipped\n');
    write('skipped/buildkit_skip.yaml', '');
  });
  tearDown(() => ws.deleteSync(recursive: true));

  Future<(ToolResult, String)> buildkit(List<String> args) async {
    final out = StringBuffer();
    final previous = Directory.current;
    Directory.current = ws;
    try {
      final result = await ToolRunner(
        tool: buildkitTool,
        executors: {
          ...createBuildkitExecutors(),
          'projects': ProjectsExecutor(out: out),
        },
        output: StringBuffer(),
      ).run(args);
      return (result, out.toString());
    } finally {
      Directory.current = previous;
    }
  }

  test('BK-PRJ-1: --json prints one document: every project with identity, '
      'language and natures', () async {
    final (result, text) = await buildkit([':projects', '--json']);
    expect(result.success, isTrue, reason: result.errorMessage);
    final doc = jsonDecode(text) as Map<String, dynamic>;
    expect(doc['formatVersion'], projectsJsonFormatVersion);
    expect(doc['tool'], 'buildkit');
    expect(doc['root'], ws.path);
    expect(doc['count'], 2);
    final byPath = {
      for (final e in (doc['projects'] as List).cast<Map<String, dynamic>>())
        e['path']: e,
    };
    expect(byPath.keys.toSet(), {'pkgs/core', 'rt/py'});
    expect(byPath['pkgs/core'], {
      'id': 'CX',
      'name': 'Core X',
      'path': 'pkgs/core',
      'absolutePath': p.join(ws.path, 'pkgs', 'core'),
      'language': 'dart',
      'type': 'dart_package',
      'natures': ['dart_package', 'buildkit'],
      'version': '2.0.0',
    });
    expect(byPath['rt/py']!['language'], 'python');
  });

  test('BK-PRJ-2: the selection options of every project command apply '
      '(-r, -p, --exclude-projects)', () async {
    final (_, recursive) = await buildkit(['-r', ':projects', '--json']);
    expect([
      for (final e in jsonDecode(recursive)['projects']) e['path'],
    ], contains('pkgs/core/test/fixture'));
    final (_, selected) = await buildkit(['-p', 'CX', ':projects', '--json']);
    expect([for (final e in jsonDecode(selected)['projects']) e['id']], ['CX']);
    final (_, excluded) = await buildkit([
      '--exclude-projects',
      'py',
      ':projects',
      '--json',
    ]);
    expect(jsonDecode(excluded)['count'], 1);
  });

  test('BK-PRJ-3: without --json a table and the count', () async {
    final (result, text) = await buildkit([':projects']);
    expect(result.success, isTrue);
    expect(text, contains('pkgs/core'));
    expect(text, contains('CX'));
    expect(text.trim().split('\n').last, '2 project(s)');
  });

  test('BK-PRJ-4: with -R from another directory the listing is of that '
      'root', () async {
    final out = StringBuffer();
    final result = await ToolRunner(
      tool: buildkitTool,
      executors: {
        ...createBuildkitExecutors(),
        'projects': ProjectsExecutor(out: out),
      },
      output: StringBuffer(),
    ).run(['-R', ws.path, '-s', ws.path, ':projects', '--json']);
    expect(result.success, isTrue, reason: result.errorMessage);
    expect(jsonDecode(out.toString())['count'], 2);
  });

  test('BK-PRJ-5: --all leaves out the navigation excludes of '
      'buildkit_master.yaml', () async {
    File(
      p.join(ws.path, 'buildkit_master.yaml'),
    ).writeAsStringSync("navigation:\n  exclude:\n    - 'rt/**'\n");
    final (_, defaults) = await buildkit([':projects', '--json']);
    expect(jsonDecode(defaults)['count'], 1);
    expect(jsonDecode(defaults)['all'], isFalse);
    final (_, all) = await buildkit([':projects', '--all', '--json']);
    expect(jsonDecode(all)['count'], 2);
    expect(jsonDecode(all)['all'], isTrue);
  });
}
