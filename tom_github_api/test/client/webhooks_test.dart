import 'dart:convert';

import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/mock_http_client.dart';

void main() {
  test('createWebhook posts an inactive hook and models the reply', () async {
    Map<String, dynamic>? sent;
    final api = GitHubApiClient(
      token: 't',
      httpClient: createMockClient({
        'POST /repos/o/r/hooks': MockResponse(201, {
          'id': 7, 'active': false, 'events': ['issues'],
        }),
      }, onRequest: (r) => sent = r.body.isEmpty ? null : (r.body.startsWith('{') ? _decode(r.body) : null)),
      minMutativeInterval: Duration.zero,
    );
    final hook = await api.createWebhook(
      owner: 'o', repo: 'r', url: 'https://example.invalid/x',
      events: const ['issues'], active: false,
    );
    expect(hook.id, 7);
    expect(hook.active, isFalse);
    expect(hook.events, ['issues']);
    expect(sent?['name'], 'web');
    expect(sent?['active'], false);
    expect((sent?['config'] as Map)['url'], 'https://example.invalid/x');
  });

  test('a 422 is a GitHubException carrying the status and message', () async {
    final api = GitHubApiClient(
      token: 't',
      httpClient: createMockClient({
        'POST /repos/o/r/hooks': MockResponse(422, {'message': 'Validation Failed'}),
      }),
      minMutativeInterval: Duration.zero,
    );
    await expectLater(
      api.createWebhook(owner: 'o', repo: 'r', url: 'u', events: const ['projects_v2_item']),
      throwsA(isA<GitHubException>()
          .having((e) => e.statusCode, 'status', 422)
          .having((e) => e.message, 'message', contains('Validation'))),
    );
  });

  test('deleteWebhook deletes by id', () async {
    String? path;
    final api = GitHubApiClient(
      token: 't',
      httpClient: createMockClient({
        'DELETE /repos/o/r/hooks/7': MockResponse(204, null),
      }, onRequest: (r) => path = '${r.method} ${r.url.path}'),
      minMutativeInterval: Duration.zero,
    );
    await api.deleteWebhook(owner: 'o', repo: 'r', id: 7);
    expect(path, 'DELETE /repos/o/r/hooks/7');
  });
}

Map<String, dynamic> _decode(String body) =>
    jsonDecode(body) as Map<String, dynamic>;
