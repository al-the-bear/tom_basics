import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/mock_http_client.dart';

void main() {
  group('credential()', () {
    test('a classic PAT: login from the body, scopes from the header', () async {
      final api = GitHubApiClient(
        token: 't',
        httpClient: createMockClient({
          'GET /user': MockResponse(200, {'login': 'alexis', 'id': 1},
              headers: {'x-oauth-scopes': 'gist, notifications, Project, repo'}),
        }),
      );
      final credential = await api.credential();
      expect(credential.login, 'alexis');
      expect(credential.isFineGrained, isFalse);
      expect(credential.scopes, ['gist', 'notifications', 'project', 'repo']);
      expect(credential.describe(), contains('classic PAT'));
    });

    test('a classic PAT with no scopes at all is still classic', () async {
      final api = GitHubApiClient(
        token: 't',
        httpClient: createMockClient({
          'GET /user': MockResponse(200, {'login': 'alexis', 'id': 1},
              headers: {'x-oauth-scopes': ''}),
        }),
      );
      final credential = await api.credential();
      expect(credential.isFineGrained, isFalse);
      expect(credential.scopes, isEmpty);
    });

    test('no x-oauth-scopes header reads as fine-grained — the branch nobody '
        'has met, stated as inference', () async {
      final api = GitHubApiClient(
        token: 't',
        httpClient: createMockClient({
          'GET /user': MockResponse(200, {'login': 'alexis', 'id': 1}),
        }),
      );
      final credential = await api.credential();
      expect(credential.isFineGrained, isTrue);
      expect(credential.scopes, isEmpty);
      expect(credential.describe(), contains('fine-grained'));
    });

    test('fromHeaders matches the header case-insensitively', () {
      final credential = GitHubCredential.fromHeaders(
        const {'X-OAuth-Scopes': 'REPO'},
        login: 'x',
      );
      expect(credential.scopes, ['repo']);
    });
  });
}
