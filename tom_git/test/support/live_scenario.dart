/// One scenario run against every real server: list, clone, commit, push,
/// lose a race, delete. Each run uses a branch of its own and removes it.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:tom_git/tom_git.dart';

final _author = GitPerson.now('tom_git live', 'tom_git@example.invalid');

void liveScenario(
  String id, {
  required Uri url,
  required GitCredentialsProvider credentials,
  String? expectDefaultBranch,
}) {
  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  final branch = 'tom-git-live/$stamp';
  late GitHttpRemote remote;
  GitObjectId? created;

  setUpAll(() => remote = GitHttpRemote(url, credentials: credentials));
  tearDownAll(() async {
    // The branch goes whatever happened above.
    final tip = (await remote.listRefs()).refs['refs/heads/$branch'];
    if (tip != null) {
      await GitRepository.memory().deleteRemoteBranch(
        remote,
        branch,
        remoteTip: tip,
      );
    }
    remote.close();
  });

  test('$id-1: the refs list names the default branch', () async {
    final refs = await remote.listRefs();
    expect(refs.defaultBranch, isNotNull);
    if (expectDefaultBranch != null) {
      expect(refs.defaultBranch, expectDefaultBranch);
    }
    expect(refs.refs['refs/heads/${refs.defaultBranch}'], isNotNull);
  });

  test(
    '$id-2: a clone of the default branch reads its commit and tree',
    () async {
      final repo = GitRepository.memory();
      final refs = await remote.listRefs();
      final fetched = await repo.fetchBranch(
        remote,
        refs.defaultBranch!,
        refs: refs,
      );
      expect(fetched.fetched, isTrue);
      final commit = await repo.readCommit(fetched.tip!);
      expect(await repo.listFiles(commit.tree, ''), isNotEmpty);
      final again = await repo.fetchBranch(remote, refs.defaultBranch!);
      expect(again.fetched, isFalse, reason: 'the tip was already here');
    },
  );

  test('$id-3: a commit pushed to a new branch is read back by a second '
      'clone', () async {
    final a = GitRepository.memory();
    final refs = await remote.listRefs();
    final base = (await a.fetchBranch(
      remote,
      refs.defaultBranch!,
      refs: refs,
    )).tip!;
    final baseTree = (await a.readCommit(base)).tree;
    final tree = await a.editTree(
      baseTree,
      writes: {
        'tom_git_live/$stamp.txt': utf8.encode('written by tom_git $stamp\n'),
      },
    );
    final commit = await a.commit(
      tree: tree,
      parents: [base],
      message: 'tom_git live $stamp',
      author: _author,
    );
    final result = await a.pushBranch(remote, branch, commit);
    expect(result.ok, isTrue, reason: '$result');
    created = commit;

    final b = GitRepository.memory();
    final tip = (await b.fetchBranch(remote, branch)).tip;
    expect(tip, commit);
    final entry = await b.entryAt(
      (await b.readCommit(tip!)).tree,
      'tom_git_live/$stamp.txt',
    );
    expect(
      utf8.decode(await b.readBlob(entry!.id)),
      'written by tom_git $stamp\n',
    );
  });

  test('$id-4: a push from a stale clone loses the race and says so', () async {
    final tip = created;
    expect(tip, isNotNull, reason: 'needs the branch from $id-3');
    final a = GitRepository.memory();
    final b = GitRepository.memory();
    await a.fetchBranch(remote, branch);
    await b.fetchBranch(remote, branch);

    Future<GitObjectId> change(GitRepository repo, String text) async {
      final tree = await repo.editTree(
        (await repo.readCommit(tip!)).tree,
        writes: {'tom_git_live/$stamp.txt': utf8.encode(text)},
      );
      return repo.commit(
        tree: tree,
        parents: [tip],
        message: text,
        author: _author,
      );
    }

    final first = await a.pushBranch(
      remote,
      branch,
      await change(a, 'a\n'),
      remoteTip: tip,
    );
    expect(first.ok, isTrue, reason: '$first');
    final second = await b.pushBranch(
      remote,
      branch,
      await change(b, 'b\n'),
      remoteTip: tip,
    );
    expect(second.ok, isFalse);
    expect(second.isRace, isTrue, reason: '$second');
  });

  test('$id-5: deleting the branch removes it', () async {
    final repo = GitRepository.memory();
    final tip = (await remote.listRefs()).refs['refs/heads/$branch'];
    expect(tip, isNotNull);
    final result = await repo.deleteRemoteBranch(
      remote,
      branch,
      remoteTip: tip!,
    );
    expect(result.ok, isTrue, reason: '$result');
    expect((await remote.listRefs()).refs['refs/heads/$branch'], isNull);
  });
}
