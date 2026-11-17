import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// `--modules` / `--skip-modules` select repositories by path, so independent
/// clones (a `.git` directory, no submodule name) are selected like submodule
/// checkouts:
/// - a name or path is compared with whole path segments, case-insensitive
///   (`tom_basics` does not select `tom_basics_console`; `xternal/tom_dcli`
///   selects that run of segments);
/// - a repository id from `tom_repository.yaml` selects the folder holding
///   that file and everything below it, whatever its configured `name:`;
/// - a submodule checkout's `submoduleName` is an extra match.
///
/// `isSubmodule` is information only: true when `.git` is a file (a
/// submodule checkout or a worktree).
///
/// Test IDs: BB-MOD-1..6.

void main() {
  late Directory root;

  setUp(() {
    root = Directory(
      Directory.systemTemp.createTempSync('bb_mod_').resolveSymbolicLinksSync(),
    );
    RepositoryIdLookup.clearCache(executionRoot: root.path);
  });
  tearDown(() {
    RepositoryIdLookup.clearCache(executionRoot: root.path);
    root.deleteSync(recursive: true);
  });

  /// An independent clone at [rel]: a `.git` directory, gitignored in its
  /// parent repository as the new tree has it.
  void clone(String rel) {
    Directory(p.join(root.path, rel, '.git')).createSync(recursive: true);
    final parent = File(
      p.join(p.dirname(p.join(root.path, rel)), '.gitignore'),
    );
    if (parent.parent.path != p.join(root.path, rel)) {
      parent.writeAsStringSync('${p.basename(rel)}/\n', mode: FileMode.append);
    }
  }

  void repositoryYaml(String rel, String id, String name) => File(
    p.join(root.path, rel, 'tom_repository.yaml'),
  ).writeAsStringSync('repository_id: $id\nname: $name\n');

  Future<List<FsFolder>> repos() async => GitRepoFinder().findAll(root.path);

  Future<Set<String>> select({
    List<String> modules = const [],
    List<String> skipModules = const [],
  }) async {
    final info = GitTraversalInfo(
      executionRoot: root.path,
      gitMode: GitTraversalMode.innerFirst,
      modules: modules,
      skipModules: skipModules,
    );
    final kept = FilterPipeline().applyGitFilters(await repos(), info);
    return {for (final f in kept) p.relative(f.path, from: root.path)};
  }

  void tree() {
    Directory(p.join(root.path, '.git')).createSync();
    clone('tom_ai/basics');
    clone('tom_ai/basics_console');
    clone('tom_ai/tom_basics');
    clone('tom_ai/tom_basics_console');
    clone('tom_ai/xternal/tom_dcli');
    clone('app_webwork');
    repositoryYaml('tom_ai/basics', 'BAS', 'basics');
    repositoryYaml('app_webwork', 'WEBWK', 'webwork');
  }

  test('BB-MOD-1: --modules <name> selects an independent clone by its '
      'folder name [2026-11-17]', () async {
    tree();
    expect(await select(modules: ['basics']), {'tom_ai/basics'});
    expect(await select(modules: ['TOM_DCLI']), {'tom_ai/xternal/tom_dcli'});
  });

  test(
    'BB-MOD-2: names are compared with whole path segments [2026-11-17]',
    () async {
      tree();
      expect(await select(modules: ['tom_basics']), {'tom_ai/tom_basics'});
      expect(await select(modules: ['xternal/tom_dcli']), {
        'tom_ai/xternal/tom_dcli',
      });
      expect(await select(modules: ['xternal']), {'tom_ai/xternal/tom_dcli'});
      expect(await select(modules: ['dcli']), isEmpty);
      expect(
        await select(skipModules: ['tom_basics']),
        isNot(contains('tom_ai/tom_basics')),
      );
      expect(
        await select(skipModules: ['tom_basics']),
        contains('tom_ai/tom_basics_console'),
      );
    },
  );

  test(
    'BB-MOD-3: --modules <ID> selects the repository holding its '
    'tom_repository.yaml, whatever its configured name [2026-11-17]',
    () async {
      tree();
      expect(await select(modules: ['BAS']), {'tom_ai/basics'});
      expect(await select(modules: ['webwk']), {'app_webwork'});
      expect(await select(modules: ['webwork']), {
        'app_webwork',
      }, reason: 'the configured name still selects its repository');
    },
  );

  test('BB-MOD-4: --skip-modules by name and by ID [2026-11-17]', () async {
    tree();
    final all = await select();
    expect(
      await select(skipModules: ['basics']),
      all.difference({'tom_ai/basics'}),
    );
    expect(
      await select(skipModules: ['WEBWK']),
      all.difference({'app_webwork'}),
    );
  });

  test('BB-MOD-5: a submodule checkout also matches by its submodule name '
      '[2026-11-17]', () async {
    Directory(
      p.join(root.path, '.git', 'modules', 'renamed_module'),
    ).createSync(recursive: true);
    Directory(
      p.join(root.path, 'libs', 'checkout'),
    ).createSync(recursive: true);
    File(
      p.join(root.path, 'libs', 'checkout', '.git'),
    ).writeAsStringSync('gitdir: ../../.git/modules/renamed_module\n');
    final detected = NatureDetector().detectNatures(
      FsFolder(path: p.join(root.path, 'libs', 'checkout')),
    );
    final git = detected.whereType<GitFolder>().single;
    expect(git.isSubmodule, isTrue);
    expect(git.submoduleName, 'renamed_module');
    final folder = FsFolder(path: git.path)..natures.addAll(detected);
    final info = GitTraversalInfo(
      executionRoot: root.path,
      gitMode: GitTraversalMode.innerFirst,
      modules: ['renamed_module'],
    );
    expect(FilterPipeline().applyGitFilters([folder], info), [folder]);
  });

  test('BB-MOD-6: isSubmodule is true when .git is a file, false for a '
      '.git directory [2026-11-17]', () {
    clone('independent');
    Directory(p.join(root.path, 'worktree')).createSync();
    File(
      p.join(root.path, 'worktree', '.git'),
    ).writeAsStringSync('gitdir: /elsewhere/.git/worktrees/w\n');
    expect(
      GitFolder.isSubmoduleFolder(p.join(root.path, 'independent')),
      isFalse,
    );
    expect(GitFolder.isSubmoduleFolder(p.join(root.path, 'worktree')), isTrue);
  });
}
