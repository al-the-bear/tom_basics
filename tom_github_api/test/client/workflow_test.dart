import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/mock_http_client.dart';

void main() {
  group('GitHubApiClient — Workflow Operations', () {
    test(
      'GH-WFL-1: dispatchWorkflow sends POST to workflow endpoint [2026-02-13 10:00]',
      () async {
        final mockClient = createMockClient({
          'POST /repos/owner/repo/actions/workflows/nightly_tests.yml/dispatches':
              MockResponse(204, ''),
        });
        final api = GitHubApiClient(
          token: 'test-token',
          httpClient: mockClient,
        );

        // Should not throw
        await api.dispatchWorkflow(
          owner: 'owner',
          repo: 'repo',
          workflowId: 'nightly_tests.yml',
          ref: 'main',
        );
        api.close();
      },
    );

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

    test(
      'GH-WFL-3: dispatchWorkflow throws on 404 [2026-02-13 10:00]',
      () async {
        final mockClient = createMockClient({
          'POST /repos/owner/repo/actions/workflows/missing.yml/dispatches':
              MockResponse(404, {'message': 'Not Found'}),
        });
        final api = GitHubApiClient(
          token: 'test-token',
          httpClient: mockClient,
        );

        expect(
          () => api.dispatchWorkflow(
            owner: 'owner',
            repo: 'repo',
            workflowId: 'missing.yml',
          ),
          throwsA(isA<GitHubNotFoundException>()),
        );
        api.close();
      },
    );

    test('GH-WFL-4: actionsEnabled reads the repository\'s Actions permission '
        '[2026-11-17]', () async {
      final mockClient = createMockClient({
        'GET /repos/owner/off/actions/permissions': MockResponse(200, {
          'enabled': false,
        }),
        'GET /repos/owner/on/actions/permissions': MockResponse(200, {
          'enabled': true,
          'allowed_actions': 'all',
        }),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);
      expect(await api.actionsEnabled(repoSlug: 'owner/off'), isFalse);
      expect(await api.actionsEnabled(repoSlug: 'owner/on'), isTrue);
      api.close();
    });

    test('GH-WFL-5: latestWorkflowRun and getWorkflowRun read a run '
        '[2026-11-17]', () async {
      final run = {
        'id': 42,
        'status': 'completed',
        'conclusion': 'success',
        'created_at': '2026-11-17T10:00:00Z',
        'html_url': 'https://github.com/owner/repo/actions/runs/42',
        'event': 'workflow_dispatch',
      };
      final mockClient = createMockClient({
        'GET /repos/owner/repo/actions/workflows/nightly_tests.yml/runs':
            MockResponse(200, {
              'total_count': 1,
              'workflow_runs': [run],
            }),
        'GET /repos/owner/repo/actions/runs/42': MockResponse(200, run),
        'GET /repos/owner/none/actions/workflows/nightly_tests.yml/runs':
            MockResponse(200, {'total_count': 0, 'workflow_runs': []}),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);
      final latest = await api.latestWorkflowRun(
        repoSlug: 'owner/repo',
        workflowId: 'nightly_tests.yml',
      );
      expect(latest!.id, 42);
      expect(latest.isCompleted, isTrue);
      expect(latest.conclusion, 'success');
      expect(latest.createdAt, DateTime.utc(2026, 11, 17, 10));
      expect(
        (await api.getWorkflowRun(repoSlug: 'owner/repo', runId: 42)).htmlUrl,
        'https://github.com/owner/repo/actions/runs/42',
      );
      expect(
        await api.latestWorkflowRun(
          repoSlug: 'owner/none',
          workflowId: 'nightly_tests.yml',
        ),
        isNull,
      );
      api.close();
    });
  });
}
