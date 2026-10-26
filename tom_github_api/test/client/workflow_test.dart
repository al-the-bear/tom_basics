import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/mock_http_client.dart';

void main() {
  group('GitHubApiClient — Workflow Operations', () {
    test('GH-WFL-1: dispatchWorkflow sends POST to workflow endpoint [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'POST /repos/owner/repo/actions/workflows/nightly_tests.yml/dispatches':
            MockResponse(204, ''),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      // Should not throw
      await api.dispatchWorkflow(
        owner: 'owner',
        repo: 'repo',
        workflowId: 'nightly_tests.yml',
        ref: 'main',
      );
      api.close();
    });

    test('GH-WFL-2: dispatchWorkflow with inputs [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'POST /repos/owner/repo/actions/workflows/build.yml/dispatches':
            MockResponse(204, ''),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      await api.dispatchWorkflow(
        owner: 'owner',
        repo: 'repo',
        workflowId: 'build.yml',
        inputs: {'target': 'linux'},
      );
      api.close();
    });

    test('GH-WFL-3: dispatchWorkflow throws on 404 [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'POST /repos/owner/repo/actions/workflows/missing.yml/dispatches':
            MockResponse(404, {'message': 'Not Found'}),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      expect(
        () => api.dispatchWorkflow(
          owner: 'owner',
          repo: 'repo',
          workflowId: 'missing.yml',
        ),
        throwsA(isA<GitHubNotFoundException>()),
      );
      api.close();
    });
  });
}
