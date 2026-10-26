/// Editing a tree without a working tree, committing, and choosing what a
/// push must send.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:tom_git/tom_git.dart';

final author = GitPerson(name: 'T', email: 't@x', seconds: 1700000000);

void main() {
  late GitRepository repo;
  setUp(() => repo = GitRepository.memory());

  Future<String> text(GitObjectId tree, String path) async =>
      utf8.decode(await repo.readBlob((await repo.entryAt(tree, path))!.id));

  test('GIT-REPO-1: writes land at their paths and untouched subtrees keep '
      'their ids', () async {
    final t1 = await repo.editTree(
      null,
      writes: {'a/one.txt': utf8.encode('1'), 'b/two.txt': utf8.encode('2')},
    );
    final t2 = await repo.editTree(
      t1,
      writes: {'a/one.txt': utf8.encode('1b')},
    );
    expect(await text(t2, 'a/one.txt'), '1b');
    expect(await text(t2, 'b/two.txt'), '2');
    expect(
      (await repo.entryAt(t2, 'b'))!.id,
      (await repo.entryAt(t1, 'b'))!.id,
      reason: 'b was not on a changed path',
    );
    expect(await repo.entryAt(t2, 'c/missing'), isNull);
  });

  test('GIT-REPO-2: deletes remove a file or a whole folder, and a folder '
      'left empty disappears', () async {
    final t1 = await repo.editTree(
      null,
      writes: {
        'doc/a.txt': [1],
        'doc/b.txt': [2],
        'keep.txt': [3],
      },
    );
    final t2 = await repo.editTree(t1, deletes: {'doc/a.txt', 'doc/b.txt'});
    expect(await repo.entryAt(t2, 'doc'), isNull);
    final t3 = await repo.editTree(t1, deletes: {'doc'});
    expect(await repo.entryAt(t3, 'doc'), isNull);
    expect(await repo.entryAt(t3, 'keep.txt'), isNotNull);
    final t4 = await repo.editTree(
      t1,
      deletes: {'doc'},
      writes: {
        'doc/new.txt': [4],
      },
    );
    expect(
      (await repo.listFiles(t4, 'doc')).map((e) => e.path),
      ['new.txt'],
      reason: 'a delete then a write under the same folder leaves the write',
    );
  });

  test('GIT-REPO-3: listing a folder walks it recursively with relative '
      'paths', () async {
    final t = await repo.editTree(
      null,
      writes: {
        'c/x.txt': [1],
        'c/sub/y.txt': [2],
        'other.txt': [3],
      },
    );
    expect(
      [for (final e in await repo.listFiles(t, 'c')) e.path],
      ['sub/y.txt', 'x.txt'],
    );
    expect(await repo.listFiles(t, 'other.txt'), isEmpty);
  });

  test('GIT-REPO-4: a push sends only what the remote does not have', () async {
    final t1 = await repo.editTree(
      null,
      writes: {
        'a/one.txt': [1],
        'b/two.txt': [2],
      },
    );
    final c1 = await repo.commit(
      tree: t1,
      parents: [],
      message: 'one',
      author: author,
    );
    final t2 = await repo.editTree(
      t1,
      writes: {
        'a/one.txt': [9],
      },
    );
    final c2 = await repo.commit(
      tree: t2,
      parents: [c1],
      message: 'two',
      author: author,
    );
    final send = await repo.objectsToSend([c2], excluded: [c1]);
    final kinds = [for (final o in send) o.type.typeName]..sort();
    // The commit, the new root tree, the new tree `a` and the new blob — not
    // `b` and not its blob.
    expect(kinds, ['blob', 'commit', 'tree', 'tree']);
    final all = await repo.objectsToSend([c2]);
    expect(all.length, greaterThan(send.length));
  });
}
