import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../fixtures/repo_shapes.dart';

/// The combined repository set: `repos.yaml` and the disk, each repository
/// in its class; git mode runs on it when a `repos.yaml` is at or above the
/// start folder (or `--manifest` names one), and project mode skips the
/// upstreams. Every tree is built by the test in a temporary folder, never
/// the live workspace.
///
/// Test IDs: BB-RSET-1..11.

const _sha = '0123456789abcdef0123456789abcdef01234567';

const _manifest =
    '''
version: 1
root: {url: https://example.com/root.git, branch: main}
repos:
  - {path: apps/a, url: https://example.com/a.git, kind: code, branch: main}
  - {path: ws, url: https://example.com/ws.git, kind: code, branch: develop}
  - {path: ws/inner, url: https://example.com/inner.git, kind: code, branch: main}
  - {path: xternal/f, url: https://example.com/f.git, kind: fork, branch: tom/1.0-fixes}
  - {path: _ai, url: https://example.com/state.git, kind: ai, branch: main}
  - {path: tom_binaries, url: https://example.com/bin.git, kind: binaries, branch: main}
  - {path: c/up, url: https://example.com/up.git, kind: upstream, pin: $_sha, hosts: []}
  - {path: elsewhere, url: https://example.com/else.git, kind: code, branch: main, hosts: [bigbeast]}
  - {path: gone, url: https://example.com/gone.git, kind: code, branch: main, hosts: [mbp]}
links:
  - {path: ws/_ai, target: ../_ai}
unmanaged:
  - {path: testclone}
''';

const _quests = '''
quests:
  - {id: folderquest, type: folder}
  - {id: q1, type: repo, url: https://example.com/q1.git, branch: dev}
  - {id: q2, type: multi, repo: quests}
repos:
  quests: {url: https://example.com/quests.git}
''';

/// A tool with one git-mode command that records where it ran.
const _tool = ToolDefinition(
  name: 'rstool',
  description: 'Tool for the repository set tests',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.all,
  globalOptions: [
    OptionDefinition.flag(
      name: 'workspace-recursion',
      abbr: 'w',
      description: 'Also run in nested workspaces',
    ),
  ],
  commands: [
    CommandDefinition(
      name: 'look',
      description: 'Records each repository',
      requiresTraversal: true,
      supportsGitTraversal: true,
      supportsProjectTraversal: false,
      worksWithNatures: {FsFolder},
    ),
  ],
);

class _Recorder extends CommandExecutor {
  _Recorder(this.calls);
  final List<String> calls;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final repo = context.repo;
    calls.add('${context.path}|${repo?.kindName}|${repo?.expectedBranch}');
    return ItemResult.success(path: context.path, name: context.name);
  }
}

void main() {
  late Directory root;
  late String previousCwd;

  String abs(String rel) =>
      rel == '.' ? root.path : p.join(root.path, p.joinAll(rel.split('/')));
  void repo(String rel) => makeRepo(root.path, rel, RepoShape.clones);
  void file(String rel, [String text = '']) => File(abs(rel))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  /// The tree of the tests: every class of § 1.2.
  void tree() {
    repo('.');
    file('repos.yaml', _manifest);
    file('buildkit_master.yaml');
    for (final r in [
      'apps/a',
      'ws',
      'ws/inner',
      'xternal/f',
      '_ai',
      'tom_binaries',
      'c/up',
      'testclone',
      'stray',
      '_ai/quests/q1',
      '_ai/quests/q2',
      '_ai/quests/unlisted',
      'ztmp/copy',
      'apps/a/node_modules/dep',
    ]) {
      repo(r);
    }
    // A nested workspace that is a repository, and a test fixture workspace
    // inside it that is none.
    file('ws/buildkit_master.yaml');
    file('ws/test/fixtures/fx/buildkit_master.yaml');
    file('ws/test/fixtures/fx/pkg/pubspec.yaml', 'name: fx_pkg\n');
    // A build skip marker no longer hides a repository from git mode.
    file('xternal/f/buildkit_skip.yaml');
    // Tool-owned clones: a run worktree, a bare multi-quest clone.
    file('.worktrees/run1/.git', 'gitdir: /elsewhere/.git/worktrees/run1\n');
    file('_ai/.quest-repos/quests.git/HEAD', 'ref: refs/heads/main\n');
    file('_ai/quests.yaml', _quests);
    // The workspace folder's _ai is a link: never walked.
    Link(abs('ws/_ai')).createSync('../_ai');
  }

  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('bb_rset_')
          .resolveSymbolicLinksSync(),
    );
    previousCwd = Directory.current.path;
  });
  tearDown(() {
    Directory.current = previousCwd;
    root.deleteSync(recursive: true);
  });

  Map<String, RepoSetMember> byRel(RepoSet set) => {
    for (final m in set.members) m.relPath.isEmpty ? '.' : m.relPath: m,
  };

  test('BB-RSET-1: every clone on disk and every entry for this host, each '
      'in its class, with its expected branch [2026-11-24]', () {
    tree();
    final set = RepoSet.discover(abs('apps/a'), host: 'mbp')!;
    expect(set.root, root.path);
    final m = byRel(set);
    expect(m.keys.toSet(), {
      '.',
      'apps/a',
      'ws',
      'ws/inner',
      'xternal/f',
      '_ai',
      'tom_binaries',
      'c/up',
      'testclone',
      'stray',
      '_ai/quests/q1',
      '_ai/quests/q2',
      '_ai/quests/unlisted',
      '.worktrees/run1',
      '_ai/.quest-repos/quests.git',
      'gone',
    }, reason: 'ztmp, node_modules and the _ai link are never looked at');
    expect(m['.']!.isRoot, isTrue);
    expect(m['.']!.kindName, 'root');
    expect(m['.']!.expectedBranch, 'main');
    expect(m['ws']!.expectedBranch, 'develop');
    expect(m['xternal/f']!.kind, RepoKind.fork);
    expect(m['xternal/f']!.expectedBranch, 'tom/1.0-fixes');
    expect(m['_ai']!.kind, RepoKind.ai);
    expect(m['tom_binaries']!.kind, RepoKind.binaries);
    expect(m['c/up']!.kind, RepoKind.upstream);
    expect(m['c/up']!.pin, _sha);
    expect(m['c/up']!.expectedBranch, isNull);
    expect(m['testclone']!.repoClass, RepoClass.unmanaged);
    expect(m['stray']!.repoClass, RepoClass.unknown);
    expect(m['_ai/quests/q1']!.repoClass, RepoClass.questClone);
    expect(m['_ai/quests/q1']!.expectedBranch, 'dev');
    expect(m['_ai/quests/q1']!.url, 'https://example.com/q1.git');
    expect(m['_ai/quests/q2']!.expectedBranch, 'quest/q2');
    expect(m['_ai/quests/q2']!.url, 'https://example.com/quests.git');
    expect(m['_ai/quests/unlisted']!.repoClass, RepoClass.questClone);
    expect(m['_ai/quests/unlisted']!.expectedBranch, isNull);
    expect(m['.worktrees/run1']!.repoClass, RepoClass.toolOwned);
    expect(m['_ai/.quest-repos/quests.git']!.repoClass, RepoClass.toolOwned);
    expect(m['gone']!.repoClass, RepoClass.missing);
    expect(m['gone']!.onDisk, isFalse);
  });

  test('BB-RSET-2: host filtering: only this host\'s entries are missing; '
      'an on-demand entry on disk is an entry [2026-11-24]', () {
    tree();
    final mbp = byRel(RepoSet.discover(root.path, host: 'mbp')!);
    expect(mbp.containsKey('elsewhere'), isFalse);
    expect(mbp['gone']!.repoClass, RepoClass.missing);
    final bigbeast = byRel(RepoSet.discover(root.path, host: 'bigbeast')!);
    expect(bigbeast['elsewhere']!.repoClass, RepoClass.missing);
    expect(bigbeast.containsKey('gone'), isFalse);
    expect(bigbeast['c/up']!.repoClass, RepoClass.entry);
  });

  test('BB-RSET-3: the git set: the root, code, fork, ai and binaries '
      'entries and the quest clones; upstreams, unmanaged, tool-owned, '
      'unknown and missing ones left out [2026-11-24]', () {
    tree();
    final set = RepoSet.discover(root.path, host: 'mbp')!;
    final whole = set.scope(root.path, stopAtWorkspaces: false).members;
    expect(
      {for (final m in whole) m.relPath.isEmpty ? '.' : m.relPath},
      {
        '.',
        'apps/a',
        'ws',
        'ws/inner',
        'xternal/f',
        '_ai',
        'tom_binaries',
        '_ai/quests/q1',
        '_ai/quests/q2',
        '_ai/quests/unlisted',
      },
    );
  });

  test('BB-RSET-4: a nested workspace that is a repository is a boundary '
      'named for -w; a workspace inside a repository is none [2026-11-24]', () {
    tree();
    final set = RepoSet.discover(root.path, host: 'mbp')!;
    final scope = set.scope(root.path);
    expect(scope.nestedWorkspaces, [abs('ws')]);
    expect(
      scope.members.map((m) => m.relPath),
      isNot(anyOf(contains('ws'), contains('ws/inner'))),
    );
    final inWs = set.scope(abs('ws'));
    expect(inWs.members.map((m) => m.relPath), ['ws', 'ws/inner']);
    expect(inWs.nestedWorkspaces, isEmpty, reason: 'fx is in no repository');
  });

  test('BB-RSET-5: git mode with -w runs every repository of the git set '
      'exactly once, each with its entry [2026-11-24]', () async {
    tree();
    final calls = <String>[];
    final runIn = <String>[];
    late ToolRunner Function(StringSink) runner;
    Future<ProcessResult> workspaceRunner(
      String binary,
      List<String> args,
      String dir,
    ) async {
      runIn.add(p.relative(dir, from: root.path));
      final outer = Directory.current;
      Directory.current = dir;
      try {
        final r = await runner(StringBuffer()).run(args);
        return ProcessResult(0, r.success ? 0 : 1, '', '');
      } finally {
        Directory.current = outer;
      }
    }

    runner = (sink) => ToolRunner(
      tool: _tool,
      output: sink,
      executors: {'look': _Recorder(calls)},
      workspaceRunner: workspaceRunner,
    );
    Directory.current = root.path;
    final result = await IOOverrides.runZoned(
      () => runner(StringBuffer()).run(['-i', '-w', ':look']),
      stderr: () => _Sink(),
    );
    expect(result.success, isTrue);
    expect(runIn, ['ws'], reason: 'fx (inside ws) is never run by -w');
    final rels = [
      for (final c in calls) p.relative(c.split('|').first, from: root.path),
    ];
    expect(rels.toSet().length, rels.length, reason: 'each repository once');
    expect(rels.toSet(), {
      '.',
      'apps/a',
      'ws',
      'ws/inner',
      'xternal/f',
      '_ai',
      'tom_binaries',
      '_ai/quests/q1',
      '_ai/quests/q2',
      '_ai/quests/unlisted',
    });
    expect(calls, contains('${abs('xternal/f')}|fork|tom/1.0-fixes'));
    expect(calls, contains('${root.path}|root|main'));
  });

  test('BB-RSET-6: %{repo.*} placeholders of a repository of the set; '
      'unresolved outside git mode or without a pin [2026-11-24]', () {
    tree();
    final set = RepoSet.discover(root.path, host: 'mbp')!;
    String resolve(String rel, String placeholder) {
      final folder = FsFolder(path: abs(rel))..repo = set.memberAt(abs(rel));
      return ExecutePlaceholderResolver.resolvePlaceholder(
        placeholder,
        ExecutePlaceholderContext(rootPath: root.path, folder: folder),
      );
    }

    expect(resolve('xternal/f', 'repo.kind'), 'fork');
    expect(resolve('xternal/f', 'repo.branch'), 'tom/1.0-fixes');
    expect(resolve('xternal/f', 'repo.url'), 'https://example.com/f.git');
    expect(resolve('xternal/f', 'repo.path'), 'xternal/f');
    expect(resolve('xternal/f', 'repo.class'), 'entry');
    expect(resolve('c/up', 'repo.pin'), _sha);
    expect(resolve('.', 'repo.path'), '.');
    expect(resolve('_ai/quests/q2', 'repo.kind'), 'questClone');
    expect(resolve('xternal/f', 'repo.exists'), 'true');
    expect(
      () => resolve('xternal/f', 'repo.pin'),
      throwsA(isA<UnresolvedPlaceholderException>()),
    );
    final plain = ExecutePlaceholderContext(
      rootPath: root.path,
      folder: FsFolder(path: abs('apps/a')),
    );
    expect(
      ExecutePlaceholderResolver.resolvePlaceholder('repo.exists', plain),
      'false',
    );
    expect(
      () => ExecutePlaceholderResolver.resolvePlaceholder('repo.kind', plain),
      throwsA(isA<UnresolvedPlaceholderException>()),
    );
  });

  test('BB-RSET-7: project mode skips every upstream without a marker '
      'file [2026-11-24]', () async {
    tree();
    file('c/pubspec.yaml', 'name: c_tool\n');
    file('c/up/pubspec.yaml', 'name: upstream_pkg\n');
    file('c/up/sub/pubspec.yaml', 'name: upstream_sub\n');
    file('c/own/pubspec.yaml', 'name: own_pkg\n');
    final folders = await FolderScanner(
      skipPaths: upstreamPaths(abs('c')),
    ).scan(abs('c'), recursive: true);
    final rels = {for (final f in folders) p.relative(f.path, from: root.path)};
    expect(rels, containsAll(['c', 'c/own']));
    expect(rels.where((r) => r.startsWith('c/up')), isEmpty);

    final traversed = <String>[];
    await BuildBase.traverse(
      info: ProjectTraversalInfo(
        executionRoot: abs('c'),
        scan: abs('c'),
        recursive: true,
      ),
      worksWithNatures: {DartProjectFolder},
      run: (ctx) async {
        traversed.add(p.relative(ctx.path, from: root.path));
        return true;
      },
    );
    expect(traversed, containsAll(['c', 'c/own']));
    expect(traversed.where((r) => r.startsWith('c/up')), isEmpty);
  });

  test('BB-RSET-8: without repos.yaml git mode walks the folders as before: '
      'skip markers still hide a repository [2026-11-24]', () async {
    repo('.');
    repo('a');
    repo('b');
    file('b/buildkit_skip.yaml');
    expect(RepoSet.discover(root.path), isNull);
    expect(upstreamPaths(root.path), isEmpty);
    final seen = <String>[];
    await IOOverrides.runZoned(
      () => BuildBase.traverse(
        info: GitTraversalInfo(
          executionRoot: root.path,
          gitMode: GitTraversalMode.innerFirst,
        ),
        worksWithNatures: {FsFolder},
        run: (ctx) async {
          seen.add(p.relative(ctx.path, from: root.path));
          expect(ctx.repo, isNull);
          return true;
        },
      ),
      stderr: () => _Sink(),
    );
    expect(seen.toSet(), {'.', 'a'});
  });

  test('BB-RSET-9: --manifest names a repos.yaml kept elsewhere; the '
      'parser takes it before or after the command [2026-11-24]', () async {
    repo('.');
    repo('apps/a');
    final elsewhere = Directory.systemTemp.createTempSync('bb_rset_manifest_');
    addTearDown(() => elsewhere.deleteSync(recursive: true));
    final manifest = File(p.join(elsewhere.path, 'repos.yaml'))
      ..writeAsStringSync(_manifest);
    expect(RepoSet.discover(root.path), isNull);
    final set = RepoSet.discover(
      root.path,
      manifestPath: manifest.path,
      host: 'mbp',
    )!;
    expect(set.root, root.path);
    expect(byRel(set)['apps/a']!.kind, RepoKind.code);

    final parser = CliArgParser(toolDefinition: _tool);
    for (final args in [
      ['--manifest', manifest.path, '-i', ':look'],
      ['-i', ':look', '--manifest=${manifest.path}'],
    ]) {
      final cli = parser.parse(args);
      expect(cli.manifest, manifest.path, reason: '$args');
      expect(
        cli.toGitTraversalInfo(executionRoot: root.path)!.manifestPath,
        manifest.path,
      );
    }
    expect(CliArgs(manifest: 'x').copyWith().manifest, 'x');
  });

  test('BB-RSET-11: a run started inside an unmanaged clone or a scratch '
      'folder below the root is a tree of its own: no set from the root\'s '
      'repos.yaml [2026-11-24]', () {
    tree();
    repo('testclone/inner');
    repo('apps/a/.dart_tool/fixture');
    repo('ztmp/copy/sub');
    for (final start in [
      'testclone',
      'testclone/inner',
      'apps/a/.dart_tool/fixture',
      'ztmp/copy',
    ]) {
      expect(RepoSet.discover(abs(start)), isNull, reason: start);
    }
    expect(RepoSet.discover(abs('apps/a')), isNotNull);
    expect(
      RepoSet.discover(abs('stray')),
      isNotNull,
      reason: 'an unknown clone is part of the tree',
    );
  });

  test('BB-RSET-10: an invalid repos.yaml is reported, naming every '
      'problem [2026-11-24]', () {
    repo('.');
    file(
      'repos.yaml',
      'version: 1\nroot: {url: https://example.com/r.git, branch: main}\n'
          'repos:\n  - {path: a, url: nope, kind: code, branch: main}\n'
          '  - {path: a, url: https://example.com/a.git, kind: weird}\n',
    );
    expect(
      () => RepoSet.discover(root.path),
      throwsA(
        isA<ReposManifestException>().having(
          (e) => e.problems.join('\n'),
          'problems',
          allOf(contains('`url` is not valid'), contains('unknown kind')),
        ),
      ),
    );
  });

  test('BB-RSET-12: an entry\'s and the root\'s description are read; an '
      'empty one is a problem, a missing one is not [2026-11-25]', () {
    final m = ReposManifest.parse(
      'version: 1\n'
      'root: {url: https://example.com/r.git, branch: main, '
      'description: "The root."}\n'
      'repos:\n'
      '  - {path: a, url: https://example.com/a.git, kind: code, '
      'branch: main, description: "Code, with a comma."}\n'
      '  - {path: b, url: https://example.com/b.git, kind: code, '
      'branch: main}\n',
    );
    expect(m.rootDescription, 'The root.');
    expect(m.entries.first.description, 'Code, with a comma.');
    expect(m.entries.last.description, isNull);
    expect(
      () => ReposManifest.parse(
        'version: 1\nroot: {url: https://example.com/r.git, branch: main, '
        'other: x}\nrepos:\n'
        '  - {path: a, url: https://example.com/a.git, kind: code, '
        'branch: main, description: ""}\n',
      ),
      throwsA(
        isA<ReposManifestException>().having(
          (e) => e.problems.join('\n'),
          'problems',
          allOf(
            contains('`description` must be one non-empty line'),
            isNot(contains('other')),
          ),
        ),
      ),
    );
  });

  test('BB-RSET-13: an unknown key at any level, and a newer version, are '
      'notes, not errors: the file is read [2026-11-25]', () {
    final m = ReposManifest.parse(
      'version: 2\n'
      'future: {anything: 1}\n'
      'root: {url: https://example.com/r.git, branch: main, owner: me}\n'
      'repos:\n'
      '  - {path: a, url: https://example.com/a.git, kind: code, '
      'branch: main, team: core, labels: [x, y]}\n'
      'links:\n'
      '  - {path: l, target: a, mode: rel}\n'
      'unmanaged:\n'
      '  - {path: u, tool: scratch}\n',
    );
    expect(m.entries.single.path, 'a');
    expect(m.entries.single.branch, 'main');
    expect(m.links.single.target, 'a');
    expect(m.unmanaged, ['u']);
    expect(m.notes, [
      '(top): unknown key `future` (ignored)',
      'version: 2 is newer than this reader (1): read as version 1',
      'root: unknown key `owner` (ignored)',
      'repos/0: unknown key `team` (ignored)',
      'repos/0: unknown key `labels` (ignored)',
      'links/0: unknown key `mode` (ignored)',
      'unmanaged/0: unknown key `tool` (ignored)',
    ]);
    expect(
      ReposManifest.parse(
        'version: 1\nroot: {url: https://example.com/r.git, branch: main}\n'
        'repos: []\n',
      ).notes,
      isEmpty,
    );
    expect(
      () => ReposManifest.parse(
        'version: 0\nroot: {url: https://example.com/r.git, branch: main}\n'
        'repos: []\n',
      ),
      throwsA(isA<ReposManifestException>()),
      reason: 'a version below 1 is no format',
    );
  });
}

/// A [Stdout] stand-in that drops what is written.
class _Sink implements Stdout {
  @override
  void write(Object? object) {}

  @override
  void writeln([Object? object = '']) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
