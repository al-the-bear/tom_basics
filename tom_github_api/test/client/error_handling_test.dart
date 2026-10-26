import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/fixtures.dart';
import '../helpers/mock_http_client.dart';

void main() {
  group('Error Handling', () {
    test('GH-ERR-1: 401 throws GitHubAuthException [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'GET /repos/owner/repo/issues/1': MockResponse(
          401,
          createErrorJson(message: 'Bad credentials'),
        ),
      });
      final api = GitHubApiClient(token: 'bad-token', httpClient: mockClient);

      expect(
        () => api.getIssue(owner: 'owner', repo: 'repo', number: 1),
        throwsA(isA<GitHubAuthException>()),
      );
      api.close();
    });

    test('GH-ERR-2: 403 with rate limit remaining=0 throws GitHubRateLimitException [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'GET /repos/owner/repo/issues/1': MockResponse.withRateLimit(
          403,
          createErrorJson(message: 'API rate limit exceeded'),
          remaining: 0,
          resetEpoch: 1739350000,
        ),
      });
      // Backoff is exercised in test/http/retry_policy_test.dart; here we are
      // asserting the error mapping, so waiting out the retries buys nothing.
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: mockClient,
        retryPolicy: GitHubRetryPolicy.none,
      );

      expect(
        () => api.getIssue(owner: 'owner', repo: 'repo', number: 1),
        throwsA(isA<GitHubRateLimitException>()),
      );
      api.close();
    });

    test('GH-ERR-3: 403 without rate limit exhaustion throws GitHubAuthException [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'GET /repos/owner/repo/issues/1': MockResponse.withRateLimit(
          403,
          createErrorJson(message: 'Forbidden'),
          remaining: 4999,
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      expect(
        () => api.getIssue(owner: 'owner', repo: 'repo', number: 1),
        throwsA(isA<GitHubAuthException>()),
      );
      api.close();
    });

    test(
        'GH-ERR-3b: a secondary rate limit is its own exception, not an '
        'authorization failure [0809]', () async {
      // The headers are byte-for-byte an authorization failure — the primary
      // quota is untouched — so the body message is the only signal. Calling
      // it `GitHubAuthException` sent a caller looking at its token for
      // something that was in fact "you are going too fast".
      final mockClient = createMockClient({
        'POST /repos/owner/repo/issues': MockResponse.withRateLimit(
          403,
          createErrorJson(
            message: 'You have exceeded a secondary rate limit. '
                'Please wait a few minutes before trying again.',
          ),
          remaining: 4321,
        ),
      });
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: mockClient,
        retryPolicy: GitHubRetryPolicy.none,
      );
      addTearDown(api.close);

      await expectLater(
        api.createIssue(owner: 'owner', repo: 'repo', title: 't'),
        throwsA(isA<GitHubSecondaryRateLimitException>()
            .having((e) => e.blockedFromContentCreation, 'blocked', isFalse)),
      );
    });

    test(
        'GH-ERR-3c: the content-creation block is distinguished from the '
        'ordinary secondary limit [0809]', () async {
      // Measured: the ordinary limit clears in about a minute, while the
      // abuse-detection block was still in force fifteen minutes later. A
      // caller that cannot tell them apart either gives up too early on the
      // first or waits pointlessly on the second.
      final mockClient = createMockClient({
        'POST /repos/owner/repo/issues': MockResponse.withRateLimit(
          403,
          createErrorJson(
            message: 'You have exceeded a secondary rate limit and have been '
                'temporarily blocked from content creation. Please retry your '
                'request again later.',
          ),
          remaining: 4321,
        ),
      });
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: mockClient,
        retryPolicy: GitHubRetryPolicy.none,
      );
      addTearDown(api.close);

      await expectLater(
        api.createIssue(owner: 'owner', repo: 'repo', title: 't'),
        throwsA(isA<GitHubSecondaryRateLimitException>()
            .having((e) => e.blockedFromContentCreation, 'blocked', isTrue)),
      );
    });

    test('GH-ERR-4: 404 throws GitHubNotFoundException [2026-02-13 10:00]', () async {
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

    test('GH-ERR-5: 422 throws GitHubValidationException with errors [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'POST /repos/owner/repo/issues': MockResponse(
          422,
          createErrorJson(
            message: 'Validation Failed',
            errors: [
              {'resource': 'Issue', 'code': 'missing_field', 'field': 'title'}
            ],
          ),
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      try {
        await api.createIssue(
          owner: 'owner',
          repo: 'repo',
          title: '',
        );
        fail('Should have thrown');
      } on GitHubValidationException catch (e) {
        expect(e.statusCode, 422);
        expect(e.errors, isNotNull);
        expect(e.errors, hasLength(1));
      }
      api.close();
    });

    test('GH-ERR-6: 500 throws generic GitHubException [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'GET /repos/owner/repo/issues/1': MockResponse(
          500,
          createErrorJson(message: 'Internal Server Error'),
        ),
      });
      final api = GitHubApiClient(
        token: 'test-token',
        httpClient: mockClient,
        retryPolicy: GitHubRetryPolicy.none,
      );

      expect(
        () => api.getIssue(owner: 'owner', repo: 'repo', number: 1),
        throwsA(isA<GitHubException>()),
      );
      api.close();
    });

    test('GH-ERR-7: rate limit info tracked from response headers [2026-02-13 10:00]', () async {
      final mockClient = createMockClient({
        'GET /repos/owner/repo/issues/42': MockResponse.withRateLimit(
          200,
          createIssueJson(number: 42),
          limit: 5000,
          remaining: 4998,
          resetEpoch: 1739350000,
        ),
      });
      final api = GitHubApiClient(token: 'test-token', httpClient: mockClient);

      await api.getIssue(owner: 'owner', repo: 'repo', number: 42);

      expect(api.lastRateLimit, isNotNull);
      expect(api.lastRateLimit!.limit, 5000);
      expect(api.lastRateLimit!.remaining, 4998);
      api.close();
    });
  });

  group('GitHubException factory', () {
    test('GH-ERR-8: fromResponse creates correct exception type [2026-02-13 10:00]', () {
      final e404 = GitHubException.fromResponse(
        404,
        {'message': 'Not Found'},
      );
      expect(e404, isA<GitHubNotFoundException>());

      final e401 = GitHubException.fromResponse(
        401,
        {'message': 'Bad credentials'},
      );
      expect(e401, isA<GitHubAuthException>());

      final e422 = GitHubException.fromResponse(
        422,
        {
          'message': 'Validation Failed',
          'errors': [
            {'resource': 'Label', 'code': 'already_exists'}
          ]
        },
      );
      expect(e422, isA<GitHubValidationException>());
      expect((e422 as GitHubValidationException).errors, hasLength(1));

      final e500 = GitHubException.fromResponse(
        500,
        {'message': 'Server Error'},
      );
      expect(e500, isA<GitHubException>());
      expect(e500, isNot(isA<GitHubNotFoundException>()));
    });

    test('GH-ERR-9: 403 with rate-limit remaining=0 creates rate limit exception [2026-02-13 10:00]', () {
      final e = GitHubException.fromResponse(
        403,
        {'message': 'API rate limit exceeded'},
        headers: {
          'x-ratelimit-limit': '5000',
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '1739350000',
        },
      );
      expect(e, isA<GitHubRateLimitException>());
      expect((e as GitHubRateLimitException).rateLimit.isExceeded, isTrue);
    });
  });
}
