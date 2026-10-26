/// Every GraphQL call is paced, a query exactly like a mutation — by decision
/// (woneprpd101, option (a)).
///
/// The gate keys on the HTTP verb and GraphQL tunnels reads over POST, so the
/// client cannot tell a query from a mutation, and it does not try. The two
/// alternatives were rejected on the asymmetry of being wrong: sniffing the
/// document for a leading `query` trusts a string the caller writes, and a
/// caller-declared `mutative:` flag is one more argument every call site must
/// get right — either way a mistake under-paces a mutation, and an under-paced
/// mutation earns an account-wide block that outlasts minutes of backoff. An
/// over-paced query is only slow. So a GraphQL-only connector budgets one call
/// per second, and this file holds that from both sides.
///
/// Measured the way the finding was: calls launched in the same tick, and the
/// COMPLETION timestamps compared. No unit test of a single call can see this
/// property, because it lives between calls.
@Timeout(Duration(seconds: 30))
library;

import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/mock_http_client.dart';

/// Short, so the file is fast; real, so completion times mean something.
const _interval = Duration(milliseconds: 150);

GitHubApiClient _client() => GitHubApiClient(
      token: 'test',
      httpClient: createMockClient({
        'POST /graphql': MockResponse(200, {
          'data': {
            'viewer': {'login': 'webwork'},
          },
        }),
      }),
      minMutativeInterval: _interval,
    );

/// Launches [calls] in one tick and returns their completion offsets, in ms.
Future<List<int>> _completions(List<Future<void> Function()> calls) async {
  final clock = Stopwatch()..start();
  final done = <int>[];
  await Future.wait([
    for (final call in calls) call().then((_) => done.add(clock.elapsedMilliseconds)),
  ]);
  return done..sort();
}

void _expectPaced(List<int> done) {
  for (var i = 1; i < done.length; i++) {
    expect(done[i] - done[i - 1],
        greaterThanOrEqualTo(_interval.inMilliseconds - 20),
        reason: 'call ${i + 1} completed ${done[i] - done[i - 1]} ms after '
            'call $i; the gate spaces GraphQL calls by $_interval '
            '(completions: $done)');
  }
}

void main() {
  group('woneprpd101 GraphQL pacing', () {
    test('D101-01: five queries launched together complete strictly spaced '
        '[0930]', () async {
      final client = _client();
      addTearDown(client.close);
      _expectPaced(await _completions([
        for (var i = 0; i < 5; i++)
          () => client.graphql('query { viewer { login } }'),
      ]));
    });

    test('D101-02: and so do mutations — the property the pacing exists for '
        '[0930]', () async {
      final client = _client();
      addTearDown(client.close);
      _expectPaced(await _completions([
        for (var i = 0; i < 5; i++)
          () => client.graphql(
              'mutation { addStar(input: {starrableId: "x"}) { clientMutationId } }'),
      ]));
    });

    test('D101-03: a query cannot jump a mutation queued ahead of it — one '
        'queue for both [0930]', () async {
      final client = _client();
      addTearDown(client.close);
      _expectPaced(await _completions([
        for (var i = 0; i < 6; i++)
          i.isEven
              ? () => client.graphql('mutation { m$i }')
              : () => client.graphql('query { viewer { login } }'),
      ]));
    });
  });
}
