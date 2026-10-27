/// A repository somebody works in, opened from the folder they picked: a
/// working repository through its `.git`, a bare one directly, a linked
/// worktree through its `.git` file — and which branches are checked out,
/// since writing one of those would leave a working tree behind its branch.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_git/io.dart';
import 'package:tom_git/tom_git.dart';

final author = GitPerson(name: 'T', email: 't@x', seconds: 1700000000);

/// One commit holding `a.txt` on [branch] of [repo].
Future<GitObjectId> _commit(GitRepository repo, String branch) async {
  final tree = await repo.editTree(
    null,
    writes: {'a.txt': utf8.encode('hello')},
  );
  final commit = await repo.commit(
    tree: tree,
    parents: [],
    message: 'first',
    author: author,
  );
  await repo.refs.write('refs/heads/$branch', commit);
  return commit;
}

/// A working repository at [folder]: `.git` holding a repository whose
/// config says it is not bare, with [branch] checked out.
Future<void> _working(String folder, {String branch = 'main'}) async {
  final gitDir = p.join(folder, '.git');
  final repo = gitOpenDirectory(gitDir, create: true, defaultBranch: branch);
  File(p.join(gitDir, 'config')).writeAsStringSync(
    '[core]\n\trepositoryformatversion = 0\n\tbare = false\n',
  );
  await _commit(repo, branch);
}

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('tom_git_local_'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test('GIT-LOCAL-1: a working repository opens through its .git folder, '
      'with its checked-out branch', () async {
    final folder = p.join(scratch.path, 'notes');
    await _working(folder, branch: 'trunk');

    final local = GitLocalRepository.open(folder);
    expect(local.isBare, isFalse);
    expect(local.gitDir, p.join(folder, '.git'));
    expect(local.headBranch(), 'trunk');
    expect(local.checkedOutBranches(), {'trunk'});
    expect(await local.repository.refs.read('refs/heads/trunk'), isNotNull);
  });

  test('GIT-LOCAL-2: a bare repository opens directly; its HEAD names the '
      'default branch and nothing is checked out', () async {
    final folder = p.join(scratch.path, 'store.git');
    await _commit(gitOpenDirectory(folder, create: true), 'main');

    final local = GitLocalRepository.open(folder);
    expect(local.isBare, isTrue);
    expect(local.headBranch(), 'main');
    expect(local.checkedOutBranches(), isEmpty);
  });

  test(
    'GIT-LOCAL-3: the .git folder picked itself is the working '
    'repository it belongs to, when its config says it is not bare',
    () async {
      final folder = p.join(scratch.path, 'notes');
      await _working(folder);

      final local = GitLocalRepository.open(p.join(folder, '.git'));
      expect(local.isBare, isFalse);
      expect(local.checkedOutBranches(), {'main'});
    },
  );

  test('GIT-LOCAL-4: a linked worktree opens through its .git file; objects '
      'and branches are the main repository\'s, and every worktree\'s branch '
      'counts as checked out', () async {
    final main = p.join(scratch.path, 'main');
    await _working(main);
    final repo = GitLocalRepository.open(main).repository;
    await _commit(repo, 'feature');

    // What `git worktree add ../feature feature` leaves behind.
    final linkedGitDir = p.join(main, '.git', 'worktrees', 'feature');
    Directory(linkedGitDir).createSync(recursive: true);
    File(
      p.join(linkedGitDir, 'HEAD'),
    ).writeAsStringSync('ref: refs/heads/feature\n');
    File(p.join(linkedGitDir, 'commondir')).writeAsStringSync('../..\n');
    final worktree = p.join(scratch.path, 'feature');
    Directory(worktree).createSync();
    File(p.join(worktree, '.git')).writeAsStringSync('gitdir: $linkedGitDir\n');

    final local = GitLocalRepository.open(worktree);
    expect(local.isBare, isFalse);
    expect(local.headBranch(), 'feature');
    expect(local.checkedOutBranches(), {'main', 'feature'});
    expect(await local.repository.refs.read('refs/heads/main'), isNotNull);

    // Seen from the main repository, the linked worktree's branch is
    // checked out too.
    expect(GitLocalRepository.open(main).checkedOutBranches(), {
      'main',
      'feature',
    });
  });

  test('GIT-LOCAL-5: a relative gitdir in a .git file is relative to the '
      'worktree', () async {
    final main = p.join(scratch.path, 'main');
    await _working(main);
    final linkedGitDir = p.join(main, '.git', 'worktrees', 'w');
    Directory(linkedGitDir).createSync(recursive: true);
    File(p.join(linkedGitDir, 'HEAD')).writeAsStringSync('ref: refs/heads/w\n');
    File(p.join(linkedGitDir, 'commondir')).writeAsStringSync('../..\n');
    final worktree = p.join(scratch.path, 'w');
    Directory(worktree).createSync();
    File(
      p.join(worktree, '.git'),
    ).writeAsStringSync('gitdir: ../main/.git/worktrees/w\n');

    expect(GitLocalRepository.open(worktree).headBranch(), 'w');
  });

  test('GIT-LOCAL-6: a detached HEAD names no branch', () async {
    final folder = p.join(scratch.path, 'notes');
    await _working(folder);
    final local = GitLocalRepository.open(folder);
    final tip = await local.repository.refs.read('refs/heads/main');
    File(p.join(folder, '.git', 'HEAD')).writeAsStringSync('${tip!.hex}\n');

    expect(local.headBranch(), isNull);
    expect(local.checkedOutBranches(), isEmpty);
  });

  test('GIT-LOCAL-7: a folder that holds no repository is refused, naming '
      'it', () {
    final folder = p.join(scratch.path, 'plain');
    Directory(folder).createSync();
    expect(
      () => GitLocalRepository.open(folder),
      throwsA(
        isA<GitNotARepositoryException>().having((e) => e.path, 'path', folder),
      ),
    );
  });

  test('GIT-LOCAL-8: HEAD is read when asked, so a checkout made since the '
      'repository was opened is seen', () async {
    final folder = p.join(scratch.path, 'notes');
    await _working(folder);
    final local = GitLocalRepository.open(folder);
    File(
      p.join(folder, '.git', 'HEAD'),
    ).writeAsStringSync('ref: refs/heads/other\n');
    expect(local.headBranch(), 'other');
    expect(local.checkedOutBranches(), {'other'});
  });
}
