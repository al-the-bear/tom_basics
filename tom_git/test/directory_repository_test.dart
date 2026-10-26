/// A bare repository on disk: what this library writes it reads back after
/// reopening, it reads a pack and index git wrote, refs take git's lock, and
/// — where a git binary happens to exist — git accepts what it wrote.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_git/io.dart';
import 'package:tom_git/tom_git.dart';

final author = GitPerson(name: 'T', email: 't@x', seconds: 1700000000);
final expected =
    jsonDecode(File('test/fixtures/delta.json').readAsStringSync()) as Map;

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('tom_git_dir_'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test(
    'GIT-DIR-1: a commit written to disk reads back after reopening',
    () async {
      final path = p.join(scratch.path, 'repo.git');
      final repo = gitOpenDirectory(path, create: true);
      final tree = await repo.editTree(
        null,
        writes: {'doc/a.txt': utf8.encode('hello')},
      );
      final commit = await repo.commit(
        tree: tree,
        parents: [],
        message: 'first',
        author: author,
      );
      await repo.refs.write('refs/heads/main', commit);

      final again = gitOpenDirectory(path);
      final tip = (await again.refs.read('refs/heads/main'))!;
      final entry = await again.entryAt(
        (await again.readCommit(tip)).tree,
        'doc/a.txt',
      );
      expect(utf8.decode(await again.readBlob(entry!.id)), 'hello');
      expect(
        File(p.join(path, 'HEAD')).readAsStringSync(),
        'ref: refs/heads/main\n',
      );
    },
  );

  test('GIT-DIR-2: a pack git wrote is read through its index, the delta '
      'resolved', () async {
    final path = p.join(scratch.path, 'fromgit.git');
    gitOpenDirectory(path, create: true);
    File(
      'test/fixtures/delta.pack',
    ).copySync(p.join(path, 'objects/pack/pack-x.pack'));
    File(
      'test/fixtures/delta.idx',
    ).copySync(p.join(path, 'objects/pack/pack-x.idx'));
    final repo = gitOpenDirectory(path);
    final old = await repo.readBlob(
      GitObjectId.fromHex(expected['docOld'] as String),
    );
    expect(old.length, expected['docOldLength']);
    final head = await repo.readCommit(
      GitObjectId.fromHex(expected['head'] as String),
    );
    expect(head.tree.hex, expected['headTree']);
  });

  test(
    'GIT-DIR-3: a received pack is kept with its index and found again',
    () async {
      final path = p.join(scratch.path, 'packs.git');
      final repo = gitOpenDirectory(path, create: true);
      final blob = GitObject.blob(utf8.encode('in a pack'));
      await repo.objects.writePack(gitWritePack([blob]));
      final packs = Directory(
        p.join(path, 'objects/pack'),
      ).listSync().map((e) => p.extension(e.path)).toList()..sort();
      expect(packs, ['.idx', '.pack']);
      expect(
        (await gitOpenDirectory(path).objects.read(blob.id))!.content,
        utf8.encode('in a pack'),
      );
    },
  );

  test('GIT-DIR-4: a ref update against a stale expectation is refused, and '
      'a held lock refuses a second writer', () async {
    final path = p.join(scratch.path, 'refs.git');
    final repo = gitOpenDirectory(path, create: true);
    final a = await repo.objects.write(GitObject.blob([1]));
    final b = await repo.objects.write(GitObject.blob([2]));
    await repo.refs.write('refs/heads/x', a, expected: GitObjectId.zero);
    await expectLater(
      repo.refs.write('refs/heads/x', b, expected: GitObjectId.zero),
      throwsA(isA<GitRefConflict>()),
    );
    await repo.refs.write('refs/heads/x', b, expected: a);
    File(p.join(path, 'refs/heads/x.lock')).writeAsStringSync('');
    await expectLater(
      repo.refs.write('refs/heads/x', a, expected: b),
      throwsA(isA<GitRefConflict>()),
    );
    File(p.join(path, 'refs/heads/x.lock')).deleteSync();
    expect((await repo.refs.list('refs/heads/')).keys, ['refs/heads/x']);
    await repo.refs.delete('refs/heads/x');
    expect(await repo.refs.read('refs/heads/x'), isNull);
  });

  test(
    'GIT-DIR-5: git itself accepts what this library wrote',
    () async {
      final path = p.join(scratch.path, 'compat.git');
      final repo = gitOpenDirectory(path, create: true);
      final tree = await repo.editTree(
        null,
        writes: {
          'a.txt': utf8.encode('one\n'),
          'dir/b.txt': utf8.encode('two\n'),
        },
      );
      final c1 = await repo.commit(
        tree: tree,
        parents: [],
        message: 'first',
        author: author,
      );
      await repo.objects.writePack(
        gitWritePack(await repo.objectsToSend([c1])),
      );
      await repo.refs.write('refs/heads/main', c1);
      final fsck = await Process.run('git', [
        '--git-dir',
        path,
        'fsck',
        '--strict',
      ]);
      expect(fsck.exitCode, 0, reason: '${fsck.stdout}${fsck.stderr}');
      final show = await Process.run('git', [
        '--git-dir',
        path,
        'show',
        'main:dir/b.txt',
      ]);
      expect(show.stdout, 'two\n');
    },
    skip: _gitOnPath() ? false : 'no git binary on PATH to compare with',
  );
}

bool _gitOnPath() {
  for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
    if (dir.isNotEmpty && File(p.join(dir, 'git')).existsSync()) return true;
  }
  return false;
}
