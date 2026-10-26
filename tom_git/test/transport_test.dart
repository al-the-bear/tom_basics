/// The smart HTTP client against the in-memory server, over protocol
/// version 2 and over version 0: list, clone, incremental fetch, push, a lost
/// race, delete, and the failures a caller must be able to tell apart.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:tom_git/testing.dart';
import 'package:tom_git/tom_git.dart';

final author = GitPerson(name: 'T', email: 't@x', seconds: 1700000000);

void main() {
  for (final v2 in [true, false]) {
    final id = v2 ? 'GIT-HTTP-V2' : 'GIT-HTTP-V0';
    group(id, () {
      late GitMemoryServer server;
      late GitHttpRemote remote;
      setUp(() async {
        server = GitMemoryServer(protocolV2: v2, requiredPassword: 'secret');
        await server.seed({'readme.txt': utf8.encode('hello\n')});
        remote = GitHttpRemote(
          server.url,
          client: server.client,
          credentials: (_) async => const GitCredentials.token('secret'),
        );
      });

      test(
        '$id-1: the listing names the branch and the default branch',
        () async {
          final refs = await remote.listRefs();
          expect(refs.protocolVersion, v2 ? 2 : 0);
          expect(refs.defaultBranch, 'main');
          expect(refs.refs.keys, ['refs/heads/main']);
        },
      );

      test('$id-2: a clone reads the file; a second fetch sends only what is '
          'new', () async {
        final repo = GitRepository.memory();
        final first = await repo.fetchBranch(remote, 'main');
        final tree = (await repo.readCommit(first.tip!)).tree;
        expect(
          utf8.decode(
            await repo.readBlob((await repo.entryAt(tree, 'readme.txt'))!.id),
          ),
          'hello\n',
        );
        await server.seed({'second.txt': utf8.encode('2\n')});
        final second = await repo.fetchBranch(remote, 'main');
        expect(second.fetched, isTrue);
        final tree2 = (await repo.readCommit(second.tip!)).tree;
        expect(await repo.entryAt(tree2, 'second.txt'), isNotNull);
        expect(await repo.entryAt(tree2, 'readme.txt'), isNotNull);
        expect((await repo.fetchBranch(remote, 'main')).fetched, isFalse);
      });

      test('$id-3: a push lands, a stale push is a race, a delete removes '
          'the branch', () async {
        final a = GitRepository.memory();
        final b = GitRepository.memory();
        final base = (await a.fetchBranch(remote, 'main')).tip!;
        await b.fetchBranch(remote, 'main');
        Future<GitObjectId> change(GitRepository repo, String text) async {
          final tree = await repo.editTree(
            (await repo.readCommit(base)).tree,
            writes: {'readme.txt': utf8.encode(text)},
          );
          return repo.commit(
            tree: tree,
            parents: [base],
            message: text,
            author: author,
          );
        }

        final ok = await a.pushBranch(
          remote,
          'main',
          await change(a, 'a'),
          remoteTip: base,
        );
        expect(ok.ok, isTrue, reason: '$ok');
        final lost = await b.pushBranch(
          remote,
          'main',
          await change(b, 'b'),
          remoteTip: base,
        );
        expect(lost.isRace, isTrue, reason: '$lost');
        expect(lost.remoteMoved, isTrue);

        final created = await a.pushBranch(remote, 'topic', base);
        expect(created.ok, isTrue);
        final deleted = await a.deleteRemoteBranch(
          remote,
          'topic',
          remoteTip: base,
        );
        expect(deleted.ok, isTrue);
        expect((await remote.listRefs()).refs.keys, ['refs/heads/main']);
      });

      test('$id-4: wrong credentials, a missing repository and an absent '
          'branch are told apart', () async {
        final wrong = GitHttpRemote(
          server.url,
          client: server.client,
          credentials: (_) async => const GitCredentials.token('nope'),
        );
        await expectLater(wrong.listRefs(), throwsA(isA<GitAuthException>()));
        final missing = GitHttpRemote(
          Uri.parse('https://elsewhere.test/x.git'),
          client: server.client,
          credentials: (_) async => const GitCredentials.token('secret'),
        );
        await expectLater(
          missing.listRefs(),
          throwsA(isA<GitRepositoryNotFoundException>()),
        );
        final repo = GitRepository.memory();
        expect((await repo.fetchBranch(remote, 'nope')).tip, isNull);
      });
    });
  }

  test(
    'GIT-HTTP-1: a push to an empty repository creates its first branch',
    () async {
      final server = GitMemoryServer();
      final remote = GitHttpRemote(server.url, client: server.client);
      expect((await remote.listRefs()).refs, isEmpty);
      final repo = GitRepository.memory();
      final tree = await repo.editTree(
        null,
        writes: {
          'a': [1],
        },
      );
      final commit = await repo.commit(
        tree: tree,
        parents: [],
        message: 'm',
        author: author,
      );
      final result = await repo.pushBranch(remote, 'main', commit);
      expect(result.ok, isTrue, reason: '$result');
      expect((await remote.listRefs()).refs['refs/heads/main'], commit);
    },
  );
}
