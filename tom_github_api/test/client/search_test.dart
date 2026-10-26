import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/fixtures.dart';
import '../helpers/mock_http_client.dart';

void main() {
  group('GitHubApiClient — Search Operations', () {
    test('GH-SRC-1: searchIssues returns search results [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'GET /search/issues': MockResponse(
          200,
          createSearchResultJson(
            totalCount: 2,
            items: [
              createIssueJson(number: 42, title: 'Match 1'),
              createIssueJson(number: 56, title: 'Match 2'),
            ],
          ),
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final result = await api.searchIssues(
        query: 'repo:owner/repo RangeError',
      );

      expect(result.totalCount, 2);
      expect(result.items, hasLength(2));
      expect(result.incompleteResults, isFalse);
      api.close();
    });

    test('GH-SRC-2: searchIssues handles empty results [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'GET /search/issues': MockResponse(
          200,
          createSearchResultJson(totalCount: 0, items: []),
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final result = await api.searchIssues(query: 'nonexistent');

      expect(result.totalCount, 0);
      expect(result.items, isEmpty);
      api.close();
    });
  });
}
