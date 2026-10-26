/// `getConditionalList` — the array form of the conditional GET, with the
/// same `304` accounting. A comment thread is a list, and the object form
/// refuses one.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tom_github_api/src/http/github_http_client.dart';

void main() {
  test('a 200 decodes the array and carries the ETag', () async {
    final client = GitHubHttpClient(
      token: 't',
      baseUrl: 'https://api.example',
      httpClient: MockClient((request) async {
        expect(request.headers['If-None-Match'], isNull);
        return http.Response(jsonEncode([{'id': 1}, {'id': 2}]), 200,
            headers: {'etag': 'W/"abc"'});
      }),
    );
    final result = await client.getConditionalList('/x');
    expect(result.notModified, isFalse);
    expect(result.value, hasLength(2));
    expect(result.etag, 'W/"abc"');
    expect(client.requestCounts, (requests: 1, notModified: 0));
  });

  test('a 304 is unmodified, keeps the tag, and is counted', () async {
    final client = GitHubHttpClient(
      token: 't',
      baseUrl: 'https://api.example',
      httpClient: MockClient((request) async {
        expect(request.headers['If-None-Match'], 'W/"abc"');
        return http.Response('', 304, headers: {'etag': 'W/"abc"'});
      }),
    );
    final result =
        await client.getConditionalList('/x', ifNoneMatch: 'W/"abc"');
    expect(result.notModified, isTrue);
    expect(result.value, isNull);
    expect(result.etag, 'W/"abc"');
    expect(client.requestCounts, (requests: 1, notModified: 1));
  });
}
