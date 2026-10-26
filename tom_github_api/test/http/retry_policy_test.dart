import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/mock_http_client.dart';

/// Seconds-since-epoch [offset] from now, as GitHub sends it.
int _resetIn(Duration offset) =>
    (DateTime.now().toUtc().add(offset).millisecondsSinceEpoch / 1000).round();

http.Response _response(int status, Map<String, String> headers,
        {String body = '{}'}) =>
    http.Response(body, status, headers: headers);

/// The body GitHub sends when a *secondary* rate limit trips. The message is
/// the only signal: the headers are indistinguishable from an authorization
/// failure, because the primary quota is untouched.
const _secondaryBody = '{"message":"You have exceeded a secondary rate limit. '
    'Please wait a few minutes before trying again.",'
    '"documentation_url":"https://docs.github.com/rest/overview/'
    'rate-limits-for-the-rest-api"}';

/// A client whose issue-creation endpoint always succeeds, so the only thing
/// left to observe is what it asked to wait for.
GitHubApiClient _issueClient(
  List<Duration> slept, {
  Duration interval = const Duration(seconds: 1),
}) =>
    GitHubApiClient(
      token: 'test',
      httpClient: createMockClient({
        'POST /repos/o/r/issues': MockResponse(201, {
          'number': 7,
          'title': 'Webwork section',
          'state': 'open',
          'user': {'login': 'webwork', 'id': 1},
          'created_at': '2026-08-09T09:00:00Z',
          'updated_at': '2026-08-09T09:00:00Z',
          'html_url': 'https://github.com/o/r/issues/7',
        }),
      }),
      retryPolicy: GitHubRetryPolicy(sleep: (d) async => slept.add(d)),
      minMutativeInterval: interval,
    );

/// A pinned jitter sample. `0` adds nothing, so a wait comes out exactly as
/// the policy chose it.
double _noJitter() => 0;

/// The largest sample the source can return, so a spread is at its widest.
double _fullJitter() => 1;

void main() {
  group('GitHubRetryPolicy.delayFor', () {
    // Jitter off, so each test below asserts the wait it is *about* rather
    // than that wait plus a random spread. Which wait is chosen and how far it
    // is then spread are two claims, and mixing them would leave neither
    // provable; the spread has its own group at the end of this file.
    const policy = GitHubRetryPolicy(jitter: _noJitter);

    test('waits until reset when the primary rate limit is exhausted', () {
      final delay = policy.delayFor(
        _response(403, {
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '${_resetIn(const Duration(seconds: 30))}',
        }),
        1,
      );
      expect(delay, isNotNull);
      expect(delay!.inSeconds, inInclusiveRange(25, 31));
    });

    test('honours retry-after for a secondary rate limit', () {
      final delay = policy.delayFor(
        _response(429, {'x-ratelimit-remaining': '4321', 'retry-after': '17'}),
        1,
      );
      expect(delay, const Duration(seconds: 17));
    });

    test('does not retry a 403 that still has quota — that is authorization',
        () {
      final delay = policy.delayFor(
        _response(403, {'x-ratelimit-remaining': '4321'}),
        1,
      );
      expect(delay, isNull);
    });

    test('backs off on a secondary rate limit that sends no retry-after', () {
      // The case a large issue flush actually meets. GitHub's secondary limits
      // (~80 content-creating requests/minute) frequently answer without a
      // `retry-after`, and the headers are then identical to an authorization
      // failure — so without reading the body this is a refusal, and D11 §7.3
      // propagates a refusal instead of waiting it out.
      expect(
        policy.delayFor(
          _response(403, {'x-ratelimit-remaining': '4321'},
              body: _secondaryBody),
          1,
        ),
        const Duration(seconds: 60),
      );
      expect(
        policy.delayFor(
          _response(429, {'x-ratelimit-remaining': '4321'},
              body: _secondaryBody),
          2,
        ),
        const Duration(seconds: 120),
      );
    });

    test('prefers an explicit retry-after over the secondary default', () {
      expect(
        policy.delayFor(
          _response(403, {'x-ratelimit-remaining': '4321', 'retry-after': '5'},
              body: _secondaryBody),
          1,
        ),
        const Duration(seconds: 5),
      );
    });

    test('waits a secondary limit out past the general maxDelay ceiling', () {
      // 60 s doubling reaches 240 s on the third attempt — past `maxDelay`,
      // but a secondary limit has a ceiling of its own. The two situations are
      // not alike: a primary reset an hour out is something the caller may want
      // to hear about, whereas a secondary limit clears on its own and there is
      // nothing better to do than wait. Measured against a real repository, a
      // 50-section create-flush was still blocked after the three minutes the
      // general ceiling allowed, and the flush failed for want of patience.
      expect(
        policy.delayFor(
          _response(403, {'x-ratelimit-remaining': '4321'},
              body: _secondaryBody),
          3,
        ),
        const Duration(seconds: 240),
      );
    });

    test('gives up once a secondary wait passes maxSecondaryDelay', () {
      const impatient =
          GitHubRetryPolicy(maxSecondaryDelay: Duration(minutes: 2));
      expect(
        impatient.delayFor(
          _response(403, {'x-ratelimit-remaining': '4321'},
              body: _secondaryBody),
          3,
        ),
        isNull,
      );
    });

    test('does not wait out a content-creation block — waiting is futile', () {
      // Two different 403s hide behind the same "secondary rate limit"
      // wording. The ordinary one clears in about a minute and is worth
      // waiting for. The abuse-detection block — "temporarily blocked from
      // content creation" — was measured still in force fifteen minutes after
      // an unpaced burst earned it, so spending the whole seven-minute
      // secondary budget on it only delays the refusal the caller is going to
      // get anyway. D11 §7.3 journals the work; the user is better told now.
      expect(
        policy.delayFor(
          _response(403, {'x-ratelimit-remaining': '4321'},
              body: '{"message":"You have exceeded a secondary rate limit and '
                  'have been temporarily blocked from content creation. '
                  'Please retry your request again later."}'),
          1,
        ),
        isNull,
      );
    });

    test('reads the secondary signal out of a non-JSON body too', () {
      // GitHub occasionally answers with an HTML error page. Parsing the body
      // as JSON first would turn the one recoverable case into a refusal.
      expect(
        policy.delayFor(
          _response(403, const {},
              body: '<html>You have exceeded a secondary rate limit.</html>'),
          1,
        ),
        const Duration(seconds: 60),
      );
    });

    test('backs off exponentially on 5xx', () {
      expect(policy.delayFor(_response(500, {}), 1),
          const Duration(seconds: 1));
      expect(policy.delayFor(_response(502, {}), 2),
          const Duration(seconds: 2));
      expect(policy.delayFor(_response(503, {}), 3),
          const Duration(seconds: 4));
    });

    test('does not retry client errors that mean something', () {
      expect(policy.delayFor(_response(404, {}), 1), isNull);
      expect(policy.delayFor(_response(409, {}), 1), isNull);
      expect(policy.delayFor(_response(422, {}), 1), isNull);
    });

    test('gives up once maxAttempts is reached', () {
      expect(policy.delayFor(_response(500, {}), policy.maxAttempts), isNull);
    });

    test('refuses to sleep past maxDelay rather than hanging the app', () {
      final delay = policy.delayFor(
        _response(403, {
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '${_resetIn(const Duration(hours: 1))}',
        }),
        1,
      );
      expect(delay, isNull);
    });

    test('GitHubRetryPolicy.none never waits', () {
      expect(GitHubRetryPolicy.none.delayFor(_response(500, {}), 1), isNull);
    });
  });

  group('GitHubHttpClient retry integration', () {
    test('retries a 500 and returns the eventual success', () async {
      final slept = <Duration>[];
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(
          const {},
          sequences: {
            'GET /repos/o/r/git/ref/heads/main': [
              MockResponse(500, {'message': 'boom'}),
              MockResponse(200, {
                'ref': 'refs/heads/main',
                'object': {'sha': 'abc123'},
              }),
            ],
          },
        ),
        retryPolicy: GitHubRetryPolicy(sleep: (d) async => slept.add(d)),
      );
      addTearDown(client.close);

      final ref = await client.git.getRef(owner: 'o', repo: 'r', ref: 'heads/main');
      expect(ref.sha, 'abc123');
      expect(slept, [const Duration(seconds: 1)]);
    });

    test('waits out a secondary rate limit on the *issues* endpoints', () async {
      // The retry lives on the one `_send` every verb funnels through, so it
      // covers the issues API exactly as it covers git data. Asserted rather
      // than assumed because the two are reached through different API
      // objects, and "the retry policy only governs git data" is a plausible
      // enough reading of the code to be worth closing.
      final slept = <Duration>[];
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(
          const {},
          sequences: {
            'POST /repos/o/r/issues': [
              MockResponse(
                403,
                {'message': 'You have exceeded a secondary rate limit.'},
                headers: const {'x-ratelimit-remaining': '4321'},
              ),
              MockResponse(201, {
                'number': 7,
                'title': 'Webwork section',
                'state': 'open',
                'user': {'login': 'webwork', 'id': 1},
                'created_at': '2026-08-09T09:00:00Z',
                'updated_at': '2026-08-09T09:00:00Z',
                'html_url': 'https://github.com/o/r/issues/7',
              }),
            ],
          },
        ),
        retryPolicy: GitHubRetryPolicy(
          jitter: _noJitter,
          sleep: (d) async => slept.add(d),
        ),
      );
      addTearDown(client.close);

      final issue =
          await client.createIssue(owner: 'o', repo: 'r', title: 'Webwork section');
      expect(issue.number, 7);
      expect(slept, [const Duration(seconds: 60)]);
    });

    test('paces successive mutations by minMutativeInterval', () async {
      // GitHub's own guidance, and the cheapest way to avoid the secondary
      // limit that a create-flush otherwise earns: at least a second between
      // content-changing requests. Asserted on the *requested* wait rather
      // than on elapsed time — the injected sleep does not advance the clock,
      // which is exactly why each of the three POSTs asks for its own gap.
      final slept = <Duration>[];
      final client = _issueClient(slept);
      addTearDown(client.close);

      for (var i = 0; i < 3; i++) {
        await client.createIssue(owner: 'o', repo: 'r', title: 'section $i');
      }

      expect(slept, hasLength(2));
      for (final wait in slept) {
        expect(wait.inMilliseconds, inInclusiveRange(900, 1000));
      }
    });

    test('serialises mutations started in the same tick', () async {
      // The other half of GitHub's rule — "and do not make them concurrently".
      // Three unawaited creates that raced would each find no previous
      // mutation and so ask for no gap at all; queued, the second and third
      // each pay one. The sleep count is the observable difference.
      final slept = <Duration>[];
      final client = _issueClient(slept);
      addTearDown(client.close);

      await Future.wait([
        for (var i = 0; i < 3; i++)
          client.createIssue(owner: 'o', repo: 'r', title: 'section $i'),
      ]);

      expect(slept, hasLength(2));
    });

    test('does not pace reads — only mutations earn the secondary limit',
        () async {
      final slept = <Duration>[];
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient({
          'GET /repos/o/r/git/ref/heads/main': MockResponse(200, {
            'ref': 'refs/heads/main',
            'object': {'sha': 'abc123'},
          }),
        }),
        retryPolicy: GitHubRetryPolicy(sleep: (d) async => slept.add(d)),
      );
      addTearDown(client.close);

      for (var i = 0; i < 3; i++) {
        await client.git.getRef(owner: 'o', repo: 'r', ref: 'heads/main');
      }

      expect(slept, isEmpty);
    });

    test('Duration.zero disables the pacing entirely', () async {
      final slept = <Duration>[];
      final client = _issueClient(slept, interval: Duration.zero);
      addTearDown(client.close);

      for (var i = 0; i < 3; i++) {
        await client.createIssue(owner: 'o', repo: 'r', title: 'section $i');
      }

      expect(slept, isEmpty);
    });

    test('surfaces the error once the policy stops retrying', () async {
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient({
          'GET /repos/o/r/git/ref/heads/main':
              MockResponse(500, {'message': 'boom'}),
        }),
        retryPolicy: GitHubRetryPolicy(
          maxAttempts: 2,
          sleep: (_) async {},
        ),
      );
      addTearDown(client.close);

      expect(
        () => client.git.getRef(owner: 'o', repo: 'r', ref: 'heads/main'),
        throwsA(isA<GitHubException>()),
      );
    });
  });

  group('secondary-limit jitter', () {
    const spread = GitHubRetryPolicy(jitter: _fullJitter);

    test('spreads a secondary backoff so a fleet does not retry in lockstep',
        () {
      // A secondary limit is the one failure several clients meet at the same
      // instant for the same reason — it is earned by the account's aggregate
      // request rate. Identical inputs then produce identical waits, and the
      // synchronised retry re-earns the limit with the same burst that earned
      // it. At the widest sample the 60 s backoff becomes 75 s; what matters is
      // that two clients drawing different samples land at different instants.
      expect(
        spread.delayFor(
          _response(403, {'x-ratelimit-remaining': '4321'},
              body: _secondaryBody),
          1,
        ),
        const Duration(seconds: 75),
      );
    });

    test('spreads a retry-after too — GitHub states it to every client alike',
        () {
      expect(
        spread.delayFor(
          _response(429, {'x-ratelimit-remaining': '4321', 'retry-after': '20'}),
          1,
        ),
        const Duration(seconds: 25),
      );
    });

    test('never shortens a wait, at any sample', () {
      // The waits jitter is applied to are floors, not estimates: a
      // `Retry-After` is GitHub's own instruction, and the fallback backoff is
      // already the shortest wait believed to clear the limit. A jitter that
      // subtracted would move clients to *before* the limit lifts — turning
      // de-synchronisation into a guaranteed second refusal for every client it
      // moved earlier.
      const unjittered = GitHubRetryPolicy(jitter: _noJitter);
      for (final sample in [0.0, 0.01, 0.5, 0.99, 1.0]) {
        final policy = GitHubRetryPolicy(jitter: () => sample);
        for (var attempt = 1; attempt <= 3; attempt++) {
          final base = unjittered.delayFor(
            _response(403, {'x-ratelimit-remaining': '4321'},
                body: _secondaryBody),
            attempt,
          );
          final spreadDelay = policy.delayFor(
            _response(403, {'x-ratelimit-remaining': '4321'},
                body: _secondaryBody),
            attempt,
          );
          expect(spreadDelay, isNotNull);
          expect(spreadDelay!, greaterThanOrEqualTo(base!));
        }
      }
    });

    test('clamps a spread that overshoots the ceiling rather than refusing it',
        () {
      // The ceiling has already been consulted about the unspread wait, so a
      // spread that overshoots means "wait the maximum" — never "give up on a
      // wait that was acceptable a line ago". 240 s is inside a 250 s ceiling;
      // spread it and it would reach 300 s.
      const tight = GitHubRetryPolicy(
        jitter: _fullJitter,
        maxSecondaryDelay: Duration(seconds: 250),
      );
      expect(
        tight.delayFor(
          _response(403, {'x-ratelimit-remaining': '4321'},
              body: _secondaryBody),
          3,
        ),
        const Duration(seconds: 250),
      );
    });

    test('leaves the primary limit alone — its reset is a fact, not a guess',
        () {
      // Jitter exists for a wait that is a guess about a shared resource. A
      // primary reset is a stated instant after which quota genuinely exists,
      // so every client arriving at it together is harmless — and spreading it
      // would only make each of them wait longer than GitHub asked.
      final delay = spread.delayFor(
        _response(403, {
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '${_resetIn(const Duration(seconds: 30))}',
        }),
        1,
      );
      expect(delay, isNotNull);
      expect(delay!.inSeconds, inInclusiveRange(25, 31));
    });

    test('leaves transient 5xx backoff alone', () {
      // A 5xx is one server's problem, not the account's rate — clients that
      // meet it meet it independently, so there is no lockstep to break.
      expect(spread.delayFor(_response(500, {}), 1), const Duration(seconds: 1));
      expect(spread.delayFor(_response(503, {}), 3), const Duration(seconds: 4));
    });

    test('jitterFraction: 0 disables the spread entirely', () {
      const none = GitHubRetryPolicy(jitterFraction: 0, jitter: _fullJitter);
      expect(
        none.delayFor(
          _response(403, {'x-ratelimit-remaining': '4321'},
              body: _secondaryBody),
          1,
        ),
        const Duration(seconds: 60),
      );
    });
  });
}
