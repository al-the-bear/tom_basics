import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

/// Creates a mock HTTP client that returns predefined responses.
///
/// Usage:
/// ```dart
/// final client = createMockClient({
///   'GET /repos/owner/repo/issues/42': MockResponse(
///     200, issueJson,
///   ),
/// });
/// ```
/// [onRequest] sees every request before its response is chosen — the only way
/// to assert on what was *sent*, which for the git data API (tree entries,
/// commit parents, ref updates) is the whole point of the test.
/// [sequences] answers the same key differently on successive calls, which is
/// what a retry or a compare-and-swap race looks like from the client side. The
/// last element repeats once the list is exhausted.
///
/// Every response carries its `request`, as a real one does. `BaseClient` sets
/// it in production, so a mock that omitted it was not merely thinner — it was
/// **unfaithful**, and it hid behaviour that reads the field: the client routes
/// a reply's rate-limit budget by the URL it came from, because REST and
/// GraphQL answer the same headers in different currencies (woneprpc78).
http.Client createMockClient(
  Map<String, MockResponse> responses, {
  MockResponse? defaultResponse,
  void Function(http.Request request)? onRequest,
  Map<String, List<MockResponse>>? sequences,
}) {
  final calls = <String, int>{};
  return http_testing.MockClient((request) async {
    onRequest?.call(request);
    final key = '${request.method} ${request.url.path}';

    final sequence = sequences?[key];
    if (sequence != null && sequence.isNotEmpty) {
      final index = calls[key] ?? 0;
      calls[key] = index + 1;
      final mock = sequence[index.clamp(0, sequence.length - 1)];
      return http.Response(
        mock.body is String ? mock.body as String : jsonEncode(mock.body),
        mock.statusCode,
        headers: mock.headers,
        request: request,
      );
    }

    // Try exact match first
    var mock = responses[key];

    // Try with query parameters
    if (mock == null) {
      final keyWithQuery = request.url.query.isNotEmpty
          ? '$key?${request.url.query}'
          : key;
      mock = responses[keyWithQuery];
    }

    // Try pattern matching (for paths with dynamic segments)
    if (mock == null) {
      for (final entry in responses.entries) {
        if (_pathMatches(entry.key, key)) {
          mock = entry.value;
          break;
        }
      }
    }

    mock ??= defaultResponse ??
        MockResponse(404, {'message': 'Not Found: $key'});

    return http.Response(
      mock.body is String ? mock.body as String : jsonEncode(mock.body),
      mock.statusCode,
      headers: mock.headers,
      request: request,
    );
  });
}

bool _pathMatches(String pattern, String actual) {
  // Simple pattern matching: the pattern key format is "METHOD /path"
  // For now, exact match only
  return pattern == actual;
}

/// A predefined response for the mock HTTP client.
class MockResponse {
  final int statusCode;
  final dynamic body; // String or Map/List (will be JSON-encoded)
  final Map<String, String> headers;

  MockResponse(
    this.statusCode,
    this.body, {
    Map<String, String>? headers,
  }) : headers = {
          'content-type': 'application/json',
          ...?headers,
        };

  /// Create a response with standard rate limit headers.
  MockResponse.withRateLimit(
    this.statusCode,
    this.body, {
    int limit = 5000,
    int remaining = 4999,
    int resetEpoch = 0,
    Map<String, String>? extraHeaders,
  }) : headers = {
          'content-type': 'application/json',
          'x-ratelimit-limit': limit.toString(),
          'x-ratelimit-remaining': remaining.toString(),
          'x-ratelimit-reset': resetEpoch.toString(),
          ...?extraHeaders,
        };
}
