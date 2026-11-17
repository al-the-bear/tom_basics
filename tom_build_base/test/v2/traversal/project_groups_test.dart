// Groups are derived from the directory walk (build_tom build_cleanup4,
// decision (c)): every git repository is a group, and a `buildkit_group.yaml`
// marks any other directory as one. Nothing keeps a list of them. Every test
// runs on both shapes of nested repositories: submodule checkouts (a `.git`
// file) and independent clones (a `.git` folder its parent ignores).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../fixtures/repo_shapes.dart';

void main() {
  for (final shape in RepoShape.values) {
    group('repositories as ${shape.name}', () => _tests(shape));
  }
}

void _tests(RepoShape shape) {
  late Directory tmp;
  late String ws;

  void file(String rel, [String text = '']) => File(p.join(ws, rel))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);
  void project(String rel) =>
      file('$rel/pubspec.yaml', 'name: ${p.basename(rel)}\n');

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bb_groups_');
    ws = p.join(tmp.path, 'ws');
    file('buildkit_master.yaml');
    makeRepo(ws, '.', shape);
    makeRepo(ws, 'repo_a', shape);
    project('repo_a/pkg1');
    file('repo_a/area/buildkit_group.yaml', 'name: tools\n');
    project('repo_a/area/pkg2');
    file('repo_a/plain/buildkit_group.yaml');
    project('repo_a/plain/pkg5');
    makeRepo(ws, 'nested/repo_b', shape);
    project('nested/repo_b/pkg3');
    project('loose/pkg4');
    // The tom_ai folder of the new tree: a plain folder (no repository)
    // marked as the group tom_ai, holding a repository.
    file('tom_ai/buildkit_group.yaml', 'name: tom_ai\n');
    makeRepo(ws, 'tom_ai/basics', shape);
    project('tom_ai/basics/pkg6');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(List<String>, ProcessingResult)> select(List<String> groups) async {
    final names = <String>[];
    final result = await BuildBase.traverse(
      info: ProjectTraversalInfo(executionRoot: ws, scan: ws, groups: groups),
      requiredNatures: {DartProjectFolder},
      run: (ctx) async {
        names.add(ctx.name);
        return true;
      },
    );
    return (names..sort(), result);
  }

  test('BB-GRP-1: a git repository is a group, named by its folder', () async {
    expect((await select(['repo_a'])).$1, ['pkg1', 'pkg2', 'pkg5']);
  });

  test('BB-GRP-2: a nested repository is a group, also by its root-relative '
      'path', () async {
    expect((await select(['repo_b'])).$1, ['pkg3']);
    expect((await select(['nested/repo_b'])).$1, ['pkg3']);
  });

  test('BB-GRP-3: buildkit_group.yaml marks a group, named by its name: or '
      'else its folder', () async {
    expect((await select(['tools'])).$1, ['pkg2']);
    expect((await select(['plain'])).$1, ['pkg5']);
    expect(
      (await select(['area'])).$1,
      isEmpty,
      reason: 'a named group is known by its name',
    );
  });

  test('BB-GRP-4: several groups select their union', () async {
    expect((await select(['tools', 'repo_b'])).$1, ['pkg2', 'pkg3']);
  });

  test('BB-GRP-5: without --group every project is selected', () async {
    expect((await select([])).$1, [
      'pkg1',
      'pkg2',
      'pkg3',
      'pkg4',
      'pkg5',
      'pkg6',
    ]);
  });

  test('BB-GRP-6: a group that matches no project is reported and nothing '
      'runs', () async {
    final (names, result) = await select(['tools', 'nope']);
    expect(names, isEmpty);
    expect(result.unmatchedGroups, ['nope']);
    expect(
      describeUnmatchedGroups(['nope'], scanRoot: ws),
      contains("--group selector matched no project: 'nope'"),
    );
  });

  test('BB-GRP-7: --group parses as a global option, before or after the '
      'command, comma-separated or repeated', () {
    final parser = CliArgParser();
    expect(parser.parse(['--group', 'a,b', ':cmd']).groups, ['a', 'b']);
    expect(parser.parse([':cmd', '--group', 'a', '--group', 'c']).groups, [
      'a',
      'c',
    ]);
    expect(
      parser
          .parse(['--group', 'a', ':cmd'])
          .toProjectTraversalInfo(executionRoot: ws)
          .groups,
      ['a'],
    );
  });

  test('BB-GRP-8: buildkit_group.yaml with name: tom_ai in a plain folder is '
      'the group tom_ai; the repository inside is a group too '
      '[2026-11-17]', () async {
    expect(Directory(p.join(ws, 'tom_ai', '.git')).existsSync(), isFalse);
    expect(File(p.join(ws, 'tom_ai', '.git')).existsSync(), isFalse);
    expect((await select(['tom_ai'])).$1, ['pkg6']);
    expect((await select(['basics'])).$1, ['pkg6']);
    expect((await select(['tom_ai/basics'])).$1, ['pkg6']);
  });
}
