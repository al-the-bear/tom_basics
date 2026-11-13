// Groups are derived from the directory walk (build_tom build_cleanup4,
// decision (c)): every git repository is a group, and a `buildkit_group.yaml`
// marks any other directory as one. Nothing keeps a list of them.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
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
    Directory(p.join(ws, '.git')).createSync(recursive: true);
    Directory(p.join(ws, 'repo_a', '.git')).createSync(recursive: true);
    project('repo_a/pkg1');
    file('repo_a/area/buildkit_group.yaml', 'name: tools\n');
    project('repo_a/area/pkg2');
    file('repo_a/plain/buildkit_group.yaml');
    project('repo_a/plain/pkg5');
    // A submodule checkout: `.git` is a file.
    file('nested/repo_b/.git', 'gitdir: ../../.git/modules/repo_b\n');
    project('nested/repo_b/pkg3');
    project('loose/pkg4');
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

  test('BB-GRP-2: a submodule checkout (.git file) is a group, also by its '
      'root-relative path', () async {
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
    expect((await select([])).$1, ['pkg1', 'pkg2', 'pkg3', 'pkg4', 'pkg5']);
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
}
