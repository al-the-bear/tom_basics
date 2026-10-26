import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/fixtures.dart';
import '../helpers/mock_http_client.dart';

void main() {
  group('GitHubApiClient — Comment Operations', () {
    test('GH-CMT-1: addComment sends POST and returns comment [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'POST /repos/owner/repo/issues/42/comments': MockResponse(
          201,
          createCommentJson(id: 200, body: 'Root cause identified'),
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final comment = await api.addComment(
        owner: 'owner',
        repo: 'repo',
        issueNumber: 42,
        body: 'Root cause identified',
      );

      expect(comment.id, 200);
      expect(comment.body, 'Root cause identified');
      expect(comment.user.login, 'testuser');
      api.close();
    });

    test('GH-CMT-2: listComments returns comments for issue [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'GET /repos/owner/repo/issues/42/comments': MockResponse(
          200,
          [
            createCommentJson(id: 100, body: 'First comment'),
            createCommentJson(id: 101, body: 'Second comment'),
          ],
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final comments = await api.listComments(
        owner: 'owner',
        repo: 'repo',
        issueNumber: 42,
      );

      expect(comments, hasLength(2));
      expect(comments[0].id, 100);
      expect(comments[1].id, 101);
      api.close();
    });

    test('GH-CMT-3: listAllComments handles pagination [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'GET /repos/owner/repo/issues/42/comments?per_page=100': MockResponse(
          200,
          [createCommentJson(id: 100)],
          headers: {
            'link': '<https://api.github.com/repos/owner/repo/issues/42/comments?page=2&per_page=100>; rel="next"',
          },
        ),
        'GET /repos/owner/repo/issues/42/comments?page=2&per_page=100':
            MockResponse(
          200,
          [createCommentJson(id: 101)],
        ),
      });
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: mockClient,
        baseUrl: 'https://api.github.com',
      );

      final comments = await api.listAllComments(
        owner: 'owner',
        repo: 'repo',
        issueNumber: 42,
      );

      expect(comments, hasLength(2));
      api.close();
    });
  });
}
