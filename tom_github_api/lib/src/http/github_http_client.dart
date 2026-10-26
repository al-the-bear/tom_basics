import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../github_exception.dart';
import '../models/github_conditional.dart';
import '../models/github_rate_limit.dart';
import 'github_retry_policy.dart';

/// Internal HTTP wrapper that adds authentication, content headers,
/// rate limit tracking, retry/backoff, and error handling to all GitHub API
/// requests.
class GitHubHttpClient {
  /// Media type that makes the contents and blobs endpoints return the file
  /// body itself instead of a JSON envelope with a base64 field. Required for
  /// anything over 1 MB, and cheaper for everything else.
  static const rawMediaType = 'application/vnd.github.raw';

  final String _token;
  final http.Client _httpClient;
  final String _baseUrl;
  final GitHubRetryPolicy _retry;

  /// Smallest gap between two content-changing requests.
  ///
  /// GitHub's own guidance, and the cheapest way to stay under its secondary
  /// limits: "wait at least one second between mutative requests, and do not
  /// make them concurrently". Both halves matter and both are enforced here —
  /// mutations are serialised as well as spaced. Measured: 237 issues created
  /// at roughly a second apart drew two throttles and completed, while a burst
  /// of 100 content-creating requests earned a block that outlasted several
  /// minutes of backoff. Backing off is the recovery; pacing is what makes the
  /// recovery rare.
  ///
  /// **A GraphQL query is paced exactly like a mutation, by decision.** GraphQL
  /// tunnels reads over POST, so the verb cannot tell them apart, and this
  /// client does not try: sniffing the document trusts a string the caller
  /// writes, and a caller-declared flag is one more argument to get wrong —
  /// either mistake under-paces a mutation, which earns a block that outlasts
  /// minutes of backoff, while an over-paced query is only slow. A
  /// GraphQL-only caller therefore budgets one call per second.
  /// `test/client/graphql_pacing_test.dart` holds both sides.
  ///
  /// `Duration.zero` disables both the spacing and the serialisation — for a
  /// test, or for a caller that has a better idea of the budget than this
  /// client does.
  final Duration minMutativeInterval;

  GitHubRateLimit? _lastRateLimit;

  int _requests = 0;
  int _notModified = 0;

  /// Completes when the mutative request currently in flight has finished.
  /// Chained rather than flagged, so overlapping callers queue instead of
  /// racing.
  Future<void> _mutationGate = Future<void>.value();
  DateTime? _lastMutationAt;

  GitHubHttpClient({
    required String token,
    required http.Client httpClient,
    required String baseUrl,
    GitHubRetryPolicy retryPolicy = const GitHubRetryPolicy(),
    this.minMutativeInterval = const Duration(seconds: 1),
  })  : _token = token,
        _httpClient = httpClient,
        _baseUrl = baseUrl,
        _retry = retryPolicy;

  /// Rate limit info from the most recent response.
  GitHubRateLimit? get lastRateLimit => _lastRateLimit;

  GitHubRateLimit? _lastGraphQlRateLimit;

  /// The **points** budget the last GraphQL reply reported, or null if this
  /// client has made none.
  ///
  /// Separate from [lastRateLimit] because they are different currencies — see
  /// `_updateRateLimit`. A caller that wants the *cost of one document* reads
  /// `GitHubGraphQlResponse.cost` instead; this is what the account has left,
  /// and it is the only reading available for a mutation, since GitHub's
  /// `rateLimit` field does not exist on `Mutation`.
  GitHubRateLimit? get lastGraphQlRateLimit => _lastGraphQlRateLimit;

  /// How many HTTP requests THIS client has issued, and how many came back
  /// `304 Not Modified`.
  ///
  /// Per client instance, deliberately. The obvious alternative — reading the
  /// rate-limit counter [lastRateLimit] reports — is a per-TOKEN number, so
  /// two suites sharing a token (or one suite running its files concurrently,
  /// which `dart test` does by default) read each other's traffic and a
  /// "this cost nothing" assertion becomes a race. Counting here is the only
  /// place the question "how much did MY client spend" has an answer.
  ///
  /// [requests] counts requests ISSUED, so a retried request counts twice.
  /// That is the truthful number for a cost question: the retry was a second
  /// round trip whatever the first one's status was.
  ///
  /// [notModified] is what makes the cheapness assertable without touching a
  /// quota counter at all: GitHub does not charge a conditional request that
  /// it answers `304`, so `requests == notModified` over a stretch of polling
  /// *is* "this polling was free", stated in terms this client can observe.
  ({int requests, int notModified}) get requestCounts =>
      (requests: _requests, notModified: _notModified);

  /// Zero both counters — for a test that wants to measure one stretch of
  /// traffic rather than everything since construction.
  void resetRequestCounts() {
    _requests = 0;
    _notModified = 0;
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  // --- JSON verbs -------------------------------------------------------

  /// GET request, returning parsed JSON.
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    final response = await getRaw(path, queryParams: queryParams);
    return _decodeObject(response);
  }

  /// GET request returning the raw [http.Response] (for pagination).
  Future<http.Response> getRaw(
    String path, {
    Map<String, String>? queryParams,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = _buildUri(path, queryParams);
    final headers = {..._headers, ...?extraHeaders};
    final response = await _send(() => _httpClient.get(uri, headers: headers));
    _checkForErrors(response);
    return response;
  }

  /// GET request from a full URL (for following pagination links).
  Future<http.Response> getUrl(String url) async {
    final uri = Uri.parse(url);
    final response = await _send(() => _httpClient.get(uri, headers: _headers));
    _checkForErrors(response);
    return response;
  }

  /// GET request whose body is a JSON array (e.g. a directory listing).
  Future<List<dynamic>> getList(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    final response = await getRaw(path, queryParams: queryParams);
    if (response.body.isEmpty) return const [];
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// POST request, returning parsed JSON.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async =>
      _decodeObject(await postRaw(path, body: body));

  /// POST request returning raw [http.Response] (for array responses).
  Future<http.Response> postRaw(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _sendBody('POST', path, body);
    _checkForErrors(response);
    return response;
  }

  /// PATCH request, returning parsed JSON.
  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _sendBody('PATCH', path, body);
    _checkForErrors(response);
    return _decodeObject(response);
  }

  /// PUT request, returning parsed JSON. Used by the contents API.
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _sendBody('PUT', path, body);
    _checkForErrors(response);
    return _decodeObject(response);
  }

  /// DELETE request. Returns void.
  Future<void> delete(String path) async {
    final uri = _buildUri(path);
    final response =
        await _sendMutation(() => _httpClient.delete(uri, headers: _headers));
    _checkForErrors(response);
  }

  /// DELETE request carrying a JSON body — the contents API needs the blob
  /// sha and commit message in the body of a DELETE.
  Future<Map<String, dynamic>> deleteWithBody(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _sendBody('DELETE', path, body);
    _checkForErrors(response);
    return _decodeObject(response);
  }

  /// POST request that expects 204 No Content (e.g., workflow dispatch).
  Future<void> postNoContent(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _sendBody('POST', path, body);
    _checkForErrors(response);
  }

  // --- Conditional / binary ---------------------------------------------

  /// Conditional JSON GET. A `304` is reported as
  /// [GitHubConditional.unmodified] rather than an error.
  Future<GitHubConditional<Map<String, dynamic>>> getConditional(
    String path, {
    Map<String, String>? queryParams,
    String? ifNoneMatch,
  }) async {
    final uri = _buildUri(path, queryParams);
    final headers = {
      ..._headers,
      if (ifNoneMatch != null) 'If-None-Match': ifNoneMatch,
    };
    final response = await _send(() => _httpClient.get(uri, headers: headers));
    if (response.statusCode == 304) {
      return GitHubConditional.unmodified(etag: ifNoneMatch);
    }
    _checkForErrors(response);
    return GitHubConditional.modified(
      _decodeObject(response),
      etag: response.headers['etag'],
    );
  }

  /// Conditional JSON GET of an **array** endpoint (a comment thread, a
  /// label list). The object form above decodes a map and would refuse a
  /// list; this is the same request with the other decoding, and the same
  /// `304` accounting.
  Future<GitHubConditional<List<dynamic>>> getConditionalList(
    String path, {
    Map<String, String>? queryParams,
    String? ifNoneMatch,
  }) async {
    final uri = _buildUri(path, queryParams);
    final headers = {
      ..._headers,
      if (ifNoneMatch != null) 'If-None-Match': ifNoneMatch,
    };
    final response = await _send(() => _httpClient.get(uri, headers: headers));
    if (response.statusCode == 304) {
      return GitHubConditional.unmodified(etag: ifNoneMatch);
    }
    _checkForErrors(response);
    return GitHubConditional.modified(
      jsonDecode(response.body) as List<dynamic>,
      etag: response.headers['etag'],
    );
  }

  /// GET the response body as bytes, without JSON decoding.
  ///
  /// [accept] defaults to [rawMediaType] so file content comes back verbatim;
  /// that is the only form that works above the 1 MB base64 ceiling.
  Future<GitHubConditional<Uint8List>> getBytes(
    String path, {
    String accept = rawMediaType,
    String? ifNoneMatch,
  }) async {
    final uri = _buildUri(path);
    final headers = {
      ..._headers,
      'Accept': accept,
      if (ifNoneMatch != null) 'If-None-Match': ifNoneMatch,
    };
    final response = await _send(() => _httpClient.get(uri, headers: headers));
    if (response.statusCode == 304) {
      return GitHubConditional.unmodified(etag: ifNoneMatch);
    }
    _checkForErrors(response);
    return GitHubConditional.modified(
      Uint8List.fromList(response.bodyBytes),
      etag: response.headers['etag'],
    );
  }

  void close() {
    _httpClient.close();
  }

  // --- Internals ---

  /// Issues a request, waiting out rate limits and transient 5xx per the
  /// retry policy. Returns the last response whatever its status — throwing is
  /// the caller's decision, because a `304` and a `409` are both meaningful.
  Future<http.Response> _send(Future<http.Response> Function() issue) async {
    var attempt = 0;
    while (true) {
      attempt++;
      final response = await issue();
      // Counted here rather than at the call sites because this is the one
      // place every request passes through — mutations included, since
      // `_sendMutation` delegates here once it has waited its turn.
      _requests++;
      if (response.statusCode == 304) _notModified++;
      _updateRateLimit(response);
      if (response.statusCode < 400) return response;
      final delay = _retry.delayFor(response, attempt);
      if (delay == null) return response;
      await _retry.sleep(delay);
    }
  }

  /// Like [_send], but for a request that changes something.
  ///
  /// Serialises against every other mutation this client makes and leaves at
  /// least [minMutativeInterval] between them. See that field for why.
  Future<http.Response> _sendMutation(
      Future<http.Response> Function() issue) {
    if (minMutativeInterval == Duration.zero) return _send(issue);

    final previous = _mutationGate;
    final done = Completer<void>();
    // Published before the first `await`, so a caller that starts a second
    // mutation in the same microtask queues behind this one rather than
    // alongside it.
    _mutationGate = done.future;

    return previous.then((_) async {
      final last = _lastMutationAt;
      if (last != null) {
        final since = DateTime.now().difference(last);
        if (since < minMutativeInterval) {
          await _retry.sleep(minMutativeInterval - since);
        }
      }
      try {
        return await _send(issue);
      } finally {
        // From completion, not from dispatch: the interval GitHub cares about
        // is between requests arriving, and a slow request has already
        // supplied part of the gap.
        _lastMutationAt = DateTime.now();
        done.complete();
      }
    });
  }

  Future<http.Response> _sendBody(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) {
    final uri = _buildUri(path);
    final headers = {..._headers, 'Content-Type': 'application/json'};
    final encoded = body != null ? jsonEncode(body) : null;
    return _sendMutation(() {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (encoded != null) request.body = encoded;
      return _httpClient.send(request).then(http.Response.fromStream);
    });
  }

  Uri _buildUri(String path, [Map<String, String>? queryParams]) {
    final base = _baseUrl.endsWith('/') ? _baseUrl : '$_baseUrl/';
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final uri = Uri.parse('$base$cleanPath');
    if (queryParams != null && queryParams.isNotEmpty) {
      return uri.replace(queryParameters: queryParams);
    }
    return uri;
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    if (response.body.isEmpty) return {};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void _checkForErrors(http.Response response) {
    if (response.statusCode >= 400) {
      _throwException(response);
    }
  }

  Never _throwException(http.Response response) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = {'message': response.body};
    }
    throw GitHubException.fromResponse(
      response.statusCode,
      body,
      headers: response.headers,
      rawBody: response.body,
    );
  }

  /// Records the budget the response reported, **in its own currency**.
  ///
  /// REST and GraphQL both answer `x-ratelimit-*`, and they do not mean the
  /// same thing: REST bills 5000 **requests** an hour, GraphQL bills 5000
  /// **points**, where one point covers roughly a hundred nodes. One field for
  /// both would let a REST caller read a GraphQL reply's points as requests
  /// and conclude the account had spent far less than it had — silently, and
  /// only after a GraphQL call had happened to run in between.
  ///
  /// Routed on the request's own URL rather than on a flag threaded down from
  /// the call site, so a future GraphQL caller cannot forget to set it.
  void _updateRateLimit(http.Response response) {
    final headers = response.headers;
    if (!headers.containsKey('x-ratelimit-limit')) return;
    final limit = GitHubRateLimit.fromHeaders(headers);
    if (response.request?.url.path.endsWith('/graphql') ?? false) {
      _lastGraphQlRateLimit = limit;
    } else {
      _lastRateLimit = limit;
    }
  }
}

/// Parse the `Link` header from a paginated response.
///
/// Returns a map of rel -> url, e.g. `{'next': '...', 'last': '...'}`.
Map<String, String> parseLinkHeader(String? linkHeader) {
  if (linkHeader == null || linkHeader.isEmpty) return {};
  final links = <String, String>{};
  for (final part in linkHeader.split(',')) {
    final match = RegExp(r'<([^>]+)>;\s*rel="([^"]+)"').firstMatch(part.trim());
    if (match != null) {
      links[match.group(2)!] = match.group(1)!;
    }
  }
  return links;
}
