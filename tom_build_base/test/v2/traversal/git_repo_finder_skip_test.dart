import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../fixtures/repo_shapes.dart';

/// Git mode (`-i` / `-o`) skips what project mode skips: hidden folders and
/// every name in `kAlwaysSkipDirectories` (`ztmp`, `_ai`, `build`, ...), the
/// folders holding `tom_skip.yaml` or `buildkit_skip.yaml` with everything
/// below them (a repository holding a marker is not listed either), and a
/// nested workspace (`buildkit_master.yaml`) other than the execution root's
/// own. `--no-skip` lists the marked folders and nested workspaces, never the
/// always-skipped ones; a run rooted in a nested workspace (`-R`) lists its
/// repositories. Every test runs on both shapes of nested repositories:
/// submodule checkouts and independent clones.
///
/// Test IDs: BB-GSK-1..6.

void main() {
  for (final shape in RepoShape.values) {
    group('repositories as ${shape.name}', () => _tests(shape));
  }
}

void _tests(RepoShape shape) {
  late Directory root;

  setUp(() {
    root = Directory(
      Directory.systemTemp.createTempSync('bb_gsk_').resolveSymbolicLinksSync(),
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A repository at [rel] in this run's [shape].
  void repo(String rel) => makeRepo(root.path, rel, shape);

  void file(String rel) => File(p.join(root.path, rel))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('');

  Future<Set<String>> found({
    bool ignoreSkipMarkers = false,
    String? at,
  }) async {
    final start = at == null ? root.path : p.join(root.path, at);
    final repos = await GitRepoFinder(
      ignoreSkipMarkers: ignoreSkipMarkers,
    ).findAll(start);
    return {for (final r in repos) p.relative(r.path, from: root.path)};
  }

  test('BB-GSK-1: the always-skipped folders and hidden folders hold no '
      'listed repository [2026-11-17]', () async {
    repo('.');
    repo('tom_ai/basics');
    for (final skipped in kAlwaysSkipDirectories) {
      repo('$skipped/inside');
    }
    repo('.hidden/inside');
    repo('pkg/ztmp/publish_stage/copy');
    expect(await found(), {'.', 'tom_ai/basics'});
    expect(await found(ignoreSkipMarkers: true), {
      '.',
      'tom_ai/basics',
    }, reason: '--no-skip opens skip markers, not the always-skipped folders');
  });

  test('BB-GSK-2: a symlinked _ai is not followed [2026-11-17]', () async {
    repo('.');
    repo('elsewhere/agent_state');
    Link(
      p.join(root.path, '_ai'),
    ).createSync(p.join(root.path, 'elsewhere', 'agent_state'));
    expect(await found(), {'.', 'elsewhere/agent_state'});
  });

  test(
    'BB-GSK-3: tom_skip.yaml and buildkit_skip.yaml skip the folder and '
    'everything below it, a marked repository included [2026-11-17]',
    () async {
      repo('.');
      repo('tools/kept');
      file('legacy/tom_skip.yaml');
      repo('legacy/old_tool');
      repo('xternal/fork');
      file('xternal/fork/buildkit_skip.yaml');
      repo('xternal/fork/nested');
      repo('xternal/other_fork');
      expect(await found(), {'.', 'tools/kept', 'xternal/other_fork'});
    },
  );

  test('BB-GSK-4: --no-skip lists the marked folders [2026-11-17]', () async {
    repo('.');
    file('legacy/tom_skip.yaml');
    repo('legacy/old_tool');
    repo('xternal/fork');
    file('xternal/fork/buildkit_skip.yaml');
    expect(await found(ignoreSkipMarkers: true), {
      '.',
      'legacy/old_tool',
      'xternal/fork',
    });
  });

  test('BB-GSK-5: a nested workspace stops the walk; the execution root\'s '
      'own buildkit_master.yaml does not; -R into it lists its repositories; '
      '--no-skip walks into it [2026-11-17]', () async {
    repo('.');
    file('buildkit_master.yaml');
    repo('apps/app');
    repo('sub_ws');
    file('sub_ws/buildkit_master.yaml');
    repo('sub_ws/inner');
    expect(await found(), {'.', 'apps/app'});
    expect(await found(at: 'sub_ws'), {'sub_ws', 'sub_ws/inner'});
    expect(await found(ignoreSkipMarkers: true), {
      '.',
      'apps/app',
      'sub_ws',
      'sub_ws/inner',
    });
  });

  test('BB-GSK-6: --no-skip reaches git mode through the parser and '
      'BuildBase.traverse [2026-11-17]', () async {
    repo('.');
    repo('xternal/fork');
    file('xternal/fork/buildkit_skip.yaml');
    Future<Set<String>> traversed(List<String> args) async {
      final cli = CliArgParser().parse(args);
      final info = cli.toGitTraversalInfo(executionRoot: root.path)!;
      final seen = <String>{};
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          seen.add(p.relative(ctx.path, from: root.path));
          return true;
        },
      );
      return seen;
    }

    expect(await traversed(['-i']), {'.'});
    expect(await traversed(['-i', '--no-skip']), {'.', 'xternal/fork'});
  });
}
