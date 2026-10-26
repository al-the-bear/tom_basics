import 'dart:convert';

import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/mock_http_client.dart';

/// The repository payload GitHub answers `GET /repos/{owner}/{repo}` with,
/// reduced to the fields the client reads.
Map<String, dynamic> repoJson({
  String fullName = 'al-the-bear/tom_kdbx',
  String name = 'tom_kdbx',
  String owner = 'al-the-bear',
  int id = 1155216085,
  String defaultBranch = 'main',
  String nodeId = 'R_kgDORmxJ1Q',
  bool fork = true,
}) =>
    {
      'id': id,
      'full_name': fullName,
      'name': name,
      'owner': {'login': owner},
      'default_branch': defaultBranch,
      'node_id': nodeId,
      'fork': fork,
    };

void main() {
  group('GitHubApiClient — Repository Operations', () {
    test('GH-REPO-1: getRepository returns the typed repository [2026-08-02 10:00]',
        () async {
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: createMockClient({
          'GET /repos/al-the-bear/tom_kdbx': MockResponse(200, repoJson()),
        }),
      );

      final repo = await api.getRepository(repoSlug: 'al-the-bear/tom_kdbx');

      expect(repo.id, 1155216085);
      expect(repo.fullName, 'al-the-bear/tom_kdbx');
      expect(repo.name, 'tom_kdbx');
      expect(repo.owner, 'al-the-bear');
      expect(repo.defaultBranch, 'main');
      expect(repo.nodeId, 'R_kgDORmxJ1Q');
      expect(repo.isFork, isTrue);
      api.close();
    });

    test(
        'GH-REPO-2: a rename redirect answers with the current name, not the one asked for [2026-08-02 10:00]',
        () async {
      // This is the whole reason the model surfaces `full_name`. GitHub keeps a
      // redirect from a repository's pre-rename name, so the request succeeds
      // and the caller sees a 200 — the *only* signal that the name is stale is
      // that the answer disagrees with the question.
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: createMockClient({
          'GET /repos/al-the-bear/tom_kdbx.dart': MockResponse(
            200,
            repoJson(fullName: 'al-the-bear/tom_kdbx', name: 'tom_kdbx'),
          ),
        }),
      );

      final repo =
          await api.getRepository(repoSlug: 'al-the-bear/tom_kdbx.dart');

      expect(repo.fullName, isNot('al-the-bear/tom_kdbx.dart'));
      expect(repo.fullName, 'al-the-bear/tom_kdbx');
      api.close();
    });

    test('GH-REPO-3: getDefaultBranch reads through getRepository [2026-08-02 10:00]',
        () async {
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: createMockClient({
          'GET /repos/owner/repo':
              MockResponse(200, repoJson(defaultBranch: 'trunk')),
        }),
      );

      expect(await api.getDefaultBranch(owner: 'owner', repo: 'repo'), 'trunk');
      api.close();
    });

    test('GH-REPO-4: getRepositoryNodeId reads through getRepository [2026-08-02 10:00]',
        () async {
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: createMockClient({
          'GET /repos/owner/repo':
              MockResponse(200, repoJson(nodeId: 'R_kgDOabcdef')),
        }),
      );

      expect(
        await api.getRepositoryNodeId(owner: 'owner', repo: 'repo'),
        'R_kgDOabcdef',
      );
      api.close();
    });

    test('GH-REPO-5: a missing repository surfaces as a not-found exception [2026-08-02 10:00]',
        () async {
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: createMockClient({
          'GET /repos/owner/gone': MockResponse(404, {'message': 'Not Found'}),
        }),
      );

      await expectLater(
        api.getRepository(owner: 'owner', repo: 'gone'),
        throwsA(isA<GitHubNotFoundException>()),
      );
      api.close();
    });
  });

  group('GitHubApiClient — Repository Lifecycle', () {
    test(
        'GH-REPO-6: createUserRepository posts to the user endpoint and defaults '
        'to an empty private repository [2026-09-05 10:00]', () async {
      // The body is the subject, not the response. `auto_init: false` is what
      // leaves the repository with no commits and therefore no refs — the state
      // GitHub refuses every git-data write against, and the only state in
      // which a first-run bootstrap is exercised at all. A default that
      // initialized the repository would make this method useless for the one
      // job it was added for, silently.
      Map<String, dynamic>? sent;
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: createMockClient(
          {
            'POST /user/repos': MockResponse(
              201,
              repoJson(fullName: 'octocat/scratch', name: 'scratch',
                  owner: 'octocat', fork: false),
            ),
          },
          onRequest: (request) =>
              sent = jsonDecode(request.body) as Map<String, dynamic>,
        ),
      );

      final created = await api.createUserRepository(name: 'scratch');

      expect(sent, {'name': 'scratch', 'private': true, 'auto_init': false});
      expect(created.fullName, 'octocat/scratch');
      expect(created.defaultBranch, 'main');
      api.close();
    });

    test(
        'GH-REPO-7: createUserRepository carries description and the '
        'non-default flags [2026-09-05 10:00]', () async {
      Map<String, dynamic>? sent;
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: createMockClient(
          {'POST /user/repos': MockResponse(201, repoJson())},
          onRequest: (request) =>
              sent = jsonDecode(request.body) as Map<String, dynamic>,
        ),
      );

      await api.createUserRepository(
        name: 'scratch',
        description: 'throwaway',
        private: false,
        autoInit: true,
      );

      expect(sent, {
        'name': 'scratch',
        'description': 'throwaway',
        'private': false,
        'auto_init': true,
      });
      api.close();
    });

    test('GH-REPO-8: deleteRepository issues a DELETE on the repository '
        '[2026-09-05 10:00]', () async {
      var deleted = <String>[];
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: createMockClient(
          {'DELETE /repos/octocat/scratch': MockResponse(204, '')},
          onRequest: (request) =>
              deleted.add('${request.method} ${request.url.path}'),
        ),
      );

      await api.deleteRepository(repoSlug: 'octocat/scratch');

      expect(deleted, ['DELETE /repos/octocat/scratch']);
      api.close();
    });

    test(
        'GH-REPO-9: deleting a repository the token may not delete surfaces as '
        'an exception, not a silent success [2026-09-05 10:00]', () async {
      // A classic PAT carrying `repo` can *create* a repository and cannot
      // delete one — `delete_repo` is a separate scope. So the asymmetric case
      // is the realistic one, and a caller that cannot see the refusal leaves
      // litter behind believing it cleaned up.
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: createMockClient({
          'DELETE /repos/octocat/scratch': MockResponse(
            403,
            {'message': 'Must have admin rights to Repository.'},
          ),
        }),
      );

      await expectLater(
        api.deleteRepository(repoSlug: 'octocat/scratch'),
        throwsA(isA<GitHubException>()),
      );
      api.close();
    });
  });
}
