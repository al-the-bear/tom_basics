/// The in-memory GitHub of `package:tom_github_api/testing.dart`, driven by
/// this package's own client: the double is held to the API it stands in for.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_github_api/testing.dart';
import 'package:tom_github_api/tom_github_api.dart';

GitHubApiClient _client(FakeGitHubServer server) {
  final client = GitHubApiClient(
    token: 'test',
    httpClient: server.client,
    baseUrl: FakeGitHubServer.baseUrl,
    retryPolicy: const GitHubRetryPolicy(maxAttempts: 1),
    minMutativeInterval: Duration.zero,
  );
  addTearDown(client.close);
  return client;
}

void main() {
  test('FAKEGH-1: the server answers for a repository it holds', () async {
    final server = FakeGitHubServer()..repo('acme/handbook');
    final response = await server.client.get(
      Uri.parse('${FakeGitHubServer.baseUrl}/repos/acme/handbook/issues'),
    );
    expect(response.statusCode, 200);
    expect(server.repo('acme/handbook').issues, isEmpty);
  });

  group('FAKEGH-G git data through GitHubApiClient', () {
    test('FAKEGH-G1: a blob, a tree and a commit land as one ref update, '
        'and the fixture reads the file back', () async {
      final server = FakeGitHubServer();
      final head = server.commitFiles('o/r', {'a.txt': 'one'});
      final git = _client(server).git;

      final blob = await git.createBlob(
        owner: 'o',
        repo: 'r',
        bytes: Uint8List.fromList(utf8.encode('two')),
      );
      final base = await git.getCommit(owner: 'o', repo: 'r', sha: head);
      final tree = await git.createTree(
        owner: 'o',
        repo: 'r',
        baseTreeSha: base.treeSha,
        entries: [GitHubTreeEntry(path: 'b.txt', sha: blob)],
      );
      final commit = await git.createCommit(
        owner: 'o',
        repo: 'r',
        message: 'add b',
        treeSha: tree.sha,
        parentShas: [head],
      );
      await git.updateRef(
          owner: 'o', repo: 'r', ref: 'heads/main', sha: commit.sha);

      expect(server.fileAt('o/r', 'a.txt'), 'one');
      expect(server.fileAt('o/r', 'b.txt'), 'two');
      expect(
        (await git.getRef(owner: 'o', repo: 'r', ref: 'heads/main')).sha,
        commit.sha,
      );
    });

    test('FAKEGH-G2: a ref update that is not a fast-forward is refused, '
        'as GitHub refuses it', () async {
      final server = FakeGitHubServer();
      final first = server.commitFiles('o/r', {'a.txt': 'one'});
      server.commitFiles('o/r', {'a.txt': 'competing'});
      final git = _client(server).git;

      final stale = await git.createCommit(
        owner: 'o',
        repo: 'r',
        message: 'stale',
        treeSha: (await git.getCommit(owner: 'o', repo: 'r', sha: first))
            .treeSha,
        parentShas: [first],
      );
      await expectLater(
        git.updateRef(owner: 'o', repo: 'r', ref: 'heads/main', sha: stale.sha),
        throwsA(isA<GitHubException>()
            .having((e) => e.statusCode, 'statusCode', 422)),
      );
      expect(server.fileAt('o/r', 'a.txt'), 'competing');
    });

    test('FAKEGH-G3: identical content has one sha, as git hashes it',
        () async {
      final server = FakeGitHubServer()..repo('o/r');
      final git = _client(server).git;
      Future<String> blob(String text) => git.createBlob(
            owner: 'o',
            repo: 'r',
            bytes: Uint8List.fromList(utf8.encode(text)),
          );
      expect(await blob('same'), await blob('same'));
      expect(await blob('same'), isNot(await blob('other')));
    });

    test('FAKEGH-G4: an unchanged ref read conditionally costs nothing',
        () async {
      final server = FakeGitHubServer();
      server.commitFiles('o/r', {'a.txt': 'one'});
      final git = _client(server).git;

      final first =
          await git.getRefConditional(owner: 'o', repo: 'r', ref: 'heads/main');
      final second = await git.getRefConditional(
        owner: 'o',
        repo: 'r',
        ref: 'heads/main',
        ifNoneMatch: first.etag,
      );
      expect(second.notModified, isTrue);
      expect(server.notModifiedCount, 1);
    });
  });

  group('FAKEGH-I issues through GitHubApiClient', () {
    test('FAKEGH-I1: a created issue is listed and carries the actor',
        () async {
      final server = FakeGitHubServer()..repo('o/r');
      final client = _client(server);

      final created = await client.createIssue(
          repoSlug: 'o/r', title: 'First', body: 'Body');
      final listed = await client.listIssues(repoSlug: 'o/r');

      expect(listed.map((i) => i.number), [created.number]);
      expect(server.repo('o/r').issues[created.number]!.author, server.actor);
    });

    test('FAKEGH-I2: an issue search names is:issue, or it is refused as '
        'GitHub refuses it', () async {
      final server = FakeGitHubServer()..repo('o/r');
      final client = _client(server);
      await client.createIssue(
          repoSlug: 'o/r', title: 'Marked', body: 'marker-1 here');

      await expectLater(
        client.searchIssues(query: 'repo:o/r "marker-1" in:body'),
        throwsA(isA<GitHubException>()
            .having((e) => e.statusCode, 'statusCode', 422)),
      );
      final found = await client.searchIssues(
          query: 'repo:o/r is:issue "marker-1" in:body');
      expect(found.totalCount, 1);
    });
  });

  group('FAKEGH-C canned responses', () {
    test('FAKEGH-C1: a canned primary rate limit reaches the caller as one, '
        'and the next request is served normally', () async {
      final server = FakeGitHubServer()..repo('o/r');
      final reset = DateTime.now().toUtc().add(const Duration(minutes: 5));
      server.canned.add(rateLimited(reset));
      final client = _client(server);

      await expectLater(
        client.listIssues(repoSlug: 'o/r'),
        throwsA(isA<GitHubRateLimitException>()),
      );
      expect(await client.listIssues(repoSlug: 'o/r'), isEmpty);
    });

    test('FAKEGH-C2: a canned 401 reaches the caller as an authentication '
        'failure', () async {
      final server = FakeGitHubServer()..repo('o/r');
      server.canned.add(unauthorized());
      await expectLater(
        _client(server).listIssues(repoSlug: 'o/r'),
        throwsA(isA<GitHubException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });
}
