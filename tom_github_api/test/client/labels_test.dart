import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/fixtures.dart';
import '../helpers/mock_http_client.dart';

void main() {
  group('GitHubApiClient — Label Operations', () {
    test('GH-LBL-1: createLabel sends POST and returns label [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'POST /repos/owner/repo/labels': MockResponse(
          201,
          createLabelJson(name: 'new', color: '0000ff'),
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final label = await api.createLabel(
        owner: 'owner',
        repo: 'repo',
        name: 'new',
        color: '0000ff',
        description: 'Issue just filed',
      );

      expect(label.name, 'new');
      expect(label.color, '0000ff');
      api.close();
    });

    test('GH-LBL-2: createLabel throws GitHubValidationException on duplicate [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'POST /repos/owner/repo/labels': MockResponse(
          422,
          createErrorJson(
            message: 'Validation Failed',
            errors: [
              {'resource': 'Label', 'code': 'already_exists', 'field': 'name'}
            ],
          ),
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      expect(
        () => api.createLabel(
          owner: 'owner',
          repo: 'repo',
          name: 'new',
          color: '0000ff',
        ),
        throwsA(isA<GitHubValidationException>()),
      );
      api.close();
    });

    test('GH-LBL-3: listLabels returns all labels [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'GET /repos/owner/repo/labels': MockResponse(
          200,
          [
            createLabelJson(name: 'new', color: '0000ff'),
            createLabelJson(name: 'bug', color: 'ff0000'),
          ],
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final labels = await api.listLabels(
        owner: 'owner',
        repo: 'repo',
      );

      expect(labels, hasLength(2));
      expect(labels[0].name, 'new');
      expect(labels[1].name, 'bug');
      api.close();
    });

    test('GH-LBL-4: updateLabel sends PATCH [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'PATCH /repos/owner/repo/labels/old-name': MockResponse(
          200,
          createLabelJson(name: 'new-name', color: '00ff00'),
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final label = await api.updateLabel(
        owner: 'owner',
        repo: 'repo',
        name: 'old-name',
        newName: 'new-name',
        color: '00ff00',
      );

      expect(label.name, 'new-name');
      api.close();
    });

    test('GH-LBL-5: deleteLabel sends DELETE [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'DELETE /repos/owner/repo/labels/old-label': MockResponse(204, ''),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      // Should not throw
      await api.deleteLabel(
        owner: 'owner',
        repo: 'repo',
        name: 'old-label',
      );
      api.close();
    });

    test('GH-LBL-6: addLabelsToIssue returns updated label list [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'POST /repos/owner/repo/issues/42/labels': MockResponse(
          200,
          [
            createLabelJson(name: 'new', color: '0000ff'),
            createLabelJson(name: 'severity:high', color: 'ff8800'),
          ],
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      final labels = await api.addLabelsToIssue(
        owner: 'owner',
        repo: 'repo',
        issueNumber: 42,
        labels: ['severity:high'],
      );

      expect(labels, hasLength(2));
      api.close();
    });

    test('GH-LBL-7: removeLabelFromIssue sends DELETE [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'DELETE /repos/owner/repo/issues/42/labels/new': MockResponse(200, ''),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      // Should not throw
      await api.removeLabelFromIssue(
        owner: 'owner',
        repo: 'repo',
        issueNumber: 42,
        label: 'new',
      );
      api.close();
    });
  });
}
