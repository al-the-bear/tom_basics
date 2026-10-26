import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/fixtures.dart';
import '../helpers/mock_http_client.dart';

void main() {
  group('GitHubApiClient — Issue Operations', () {
    test('GH-ISS-1: createIssue sends POST and returns created issue [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'POST /repos/owner/repo/issues': MockResponse(
          201,
          createIssueJson(number: 99, title: 'New bug'),
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final issue = await api.createIssue(
        owner: 'owner',
        repo: 'repo',
        title: 'New bug',
        body: 'Description',
        labels: ['new', 'severity:high'],
      );

      expect(issue.number, 99);
      expect(issue.title, 'New bug');
      api.close();
    });

    test('GH-ISS-2: getIssue retrieves issue by number [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'GET /repos/owner/repo/issues/42': MockResponse(
          200,
          createIssueJson(number: 42),
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final issue = await api.getIssue(
        owner: 'owner',
        repo: 'repo',
        number: 42,
      );

      expect(issue.number, 42);
      expect(issue.title, 'Array parser crashes on empty arrays');
      api.close();
    });

    test('GH-ISS-3: getIssue throws GitHubNotFoundException for missing issue [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'GET /repos/owner/repo/issues/999': MockResponse(
          404,
          createErrorJson(message: 'Not Found'),
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      expect(
        () => api.getIssue(owner: 'owner', repo: 'repo', number: 999),
        throwsA(isA<GitHubNotFoundException>()),
      );
      api.close();
    });

    test('GH-ISS-4: updateIssue sends only provided fields [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'PATCH /repos/owner/repo/issues/42': MockResponse(
          200,
          createIssueJson(number: 42, title: 'Updated title'),
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final issue = await api.updateIssue(
        owner: 'owner',
        repo: 'repo',
        number: 42,
        title: 'Updated title',
      );

      expect(issue.title, 'Updated title');
      api.close();
    });

    test('GH-ISS-5: closeIssue sets state to closed [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'PATCH /repos/owner/repo/issues/42': MockResponse(
          200,
          createIssueJson(number: 42, state: 'closed'),
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final issue = await api.closeIssue(
        owner: 'owner',
        repo: 'repo',
        number: 42,
      );

      expect(issue.state, 'closed');
      api.close();
    });

    test('GH-ISS-6: reopenIssue sets state to open [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'PATCH /repos/owner/repo/issues/42': MockResponse(
          200,
          createIssueJson(number: 42, state: 'open'),
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final issue = await api.reopenIssue(
        owner: 'owner',
        repo: 'repo',
        number: 42,
      );

      expect(issue.state, 'open');
      api.close();
    });

    test('GH-ISS-7: listIssues returns filtered list [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'GET /repos/owner/repo/issues': MockResponse(
          200,
          [
            createIssueJson(number: 1, title: 'Issue 1'),
            createIssueJson(number: 2, title: 'Issue 2'),
          ],
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final issues = await api.listIssues(
        owner: 'owner',
        repo: 'repo',
      );

      expect(issues, hasLength(2));
      expect(issues[0].number, 1);
      expect(issues[1].number, 2);
      api.close();
    });

    test('GH-ISS-8: listIssues filters out pull requests [2026-02-13 10:00]', () async {
      final issueJson = createIssueJson(number: 1, title: 'Issue');
      final prJson = {
        ...createIssueJson(number: 2, title: 'PR'),
        'pull_request': {'url': 'https://...'},
      };

      final mockClient = createMockClient({
        'GET /repos/owner/repo/issues': MockResponse(
          200,
          [issueJson, prJson],
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final issues = await api.listIssues(
        owner: 'owner',
        repo: 'repo',
      );

      expect(issues, hasLength(1));
      expect(issues[0].number, 1);
      api.close();
    });

    test('GH-ISS-9: repoSlug form works [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'GET /repos/al-the-bear/tom_issues/issues/42': MockResponse(
          200,
          createIssueJson(number: 42),
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final issue = await api.getIssue(
        repoSlug: 'al-the-bear/tom_issues',
        number: 42,
      );

      expect(issue.number, 42);
      api.close();
    });

    test('GH-ISS-10: invalid repoSlug throws ArgumentError [2026-02-13 10:00]', () async {
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: createMockClient({}),
      );

      expect(
        () => api.getIssue(repoSlug: 'invalid', number: 42),
        throwsA(isA<ArgumentError>()),
      );
      api.close();
    });

    test('GH-ISS-11: missing owner/repo throws ArgumentError [2026-02-13 10:00]', () async {
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: createMockClient({}),
      );

      expect(
        () => api.getIssue(owner: 'owner', number: 42),
        throwsA(isA<ArgumentError>()),
      );
      api.close();
    });

    test('GH-ISS-12: listAllIssues fetches all pages [2026-02-13 10:00]', () async {
      // Page 1 response with Link header pointing to page 2
      final page1Issues = [
        createIssueJson(number: 1),
        createIssueJson(number: 2),
      ];
      final page2Issues = [
        createIssueJson(number: 3),
      ];

      // Use query-specific keys so page 1 and page 2 don't collide
      final mockClient = createMockClient({
        'GET /repos/owner/repo/issues?per_page=100': MockResponse(
          200,
          page1Issues,
          headers: {
            'link': '<https://api.github.com/repos/owner/repo/issues?page=2&per_page=100>; rel="next", '
                '<https://api.github.com/repos/owner/repo/issues?page=2&per_page=100>; rel="last"',
          },
        ),
        'GET /repos/owner/repo/issues?page=2&per_page=100': MockResponse(
          200,
          page2Issues,
        ),
      });
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: mockClient,
        baseUrl: 'https://api.github.com',
      );

      final allIssues = await api.listAllIssues(
        owner: 'owner',
        repo: 'repo',
      );

      expect(allIssues, hasLength(3));
      api.close();
    });
  });
}
