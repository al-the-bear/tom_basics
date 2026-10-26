/// woneprpc78 — the public GraphQL entry point.
///
/// The client has posted GraphQL since `transferIssue` landed, through a
/// private `_http.post('/graphql', …)` that only that method could reach.
/// Everything else in the workspace that needed GraphQL stood up its own
/// `http.Client` — a second place handling auth, retries and the rate-limit
/// headers — and the `github-projects` connector reserved in D15 §11.4 cannot
/// be built on REST at all, Projects classic having been sunset on 2025-04-01.
///
/// The shapes asserted here are **wire-established** by `woneprpb22`, not
/// guessed. GitHub answers `200` for every GraphQL error class, so a client
/// that keys on an HTTP status or a message substring is reading the wrong
/// thing; `path` is the discriminator.
library;

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/fixtures.dart';
import '../helpers/mock_http_client.dart';

/// A repository payload with every field `GitHubRepository.fromJson` needs.
///
/// Spelled out here rather than imported from `repository_test.dart`: a test
/// file is not a helper, and reaching into a sibling's private fixture is how
/// two suites come to share a shape neither of them owns.
Map<String, dynamic> _repoJson({
  String fullName = 'o/other',
  String name = 'other',
  String owner = 'o',
  int id = 2,
  String nodeId = 'R_kw2',
}) =>
    {
      'id': id,
      'full_name': fullName,
      'name': name,
      'owner': {'login': owner},
      'default_branch': 'main',
      'node_id': nodeId,
      'fork': false,
      'private': false,
      'html_url': 'https://github.com/\$fullName',
    };

/// A `rateLimit` block as GitHub returns one.
Map<String, dynamic> _rateLimit({int cost = 1, int remaining = 4999}) => {
      'limit': 5000,
      'cost': cost,
      'remaining': remaining,
      'nodeCount': cost * 100,
      'resetAt': '2026-09-22T12:00:00Z',
    };

void main() {
  group('GitHubApiClient.graphql — woneprpc78', () {
    test(
        'GH-GQL-1: posts the document, variables and operation, and returns '
        'the decoded data [0922]', () async {
      http.Request? sent;
      final api = GitHubApiClient(
        token: 't',
        httpClient: createMockClient(
          {
            'POST /graphql': MockResponse(200, {
              'data': {
                'viewer': {'login': 'alexis'}
              },
            }),
          },
          onRequest: (request) => sent = request,
        ),
      );

      final response = await api.graphql(
        r'query Who($n: Int!) { viewer { login } }',
        variables: {'n': 1},
        operationName: 'Who',
      );

      expect(response.data?['viewer']['login'], 'alexis');
      expect(response.hasErrors, isFalse);
      // The body, because a query sent without its variables fails on the
      // wire in a way no amount of response assertion would catch.
      expect(sent!.body, contains('"operationName":"Who"'));
      expect(sent!.body, contains('"variables":{"n":1}'));
      api.close();
    });

    test(
        'GH-GQL-2: a FIELD-scoped error is returned beside its partial data, '
        'not thrown [0922]', () async {
      // §1's measurement: the siblings of a failed field still resolve, so
      // throwing would discard the half that worked.
      final api = GitHubApiClient(
        token: 't',
        httpClient: createMockClient({
          'POST /graphql': MockResponse(200, {
            'data': {
              'viewer': {'login': 'alexis'},
              'bad': null,
            },
            'errors': [
              {
                'type': 'NOT_FOUND',
                'path': ['bad'],
                'message': 'Could not resolve to a node',
              },
            ],
          }),
        }),
      );

      final response = await api.graphql('query { viewer { login } bad: node }');

      expect(response.data?['viewer']['login'], 'alexis',
          reason: 'the sibling resolved and must survive');
      expect(response.fieldErrors, hasLength(1));
      expect(response.queryErrors, isEmpty);
      expect(response.fieldErrors.single.type, 'NOT_FOUND');
      expect(response.fieldErrors.single.path, ['bad']);
      api.close();
    });

    test(
        'GH-GQL-3: a QUERY-fatal error throws, carrying the errors [0922]',
        () async {
      // `INSUFFICIENT_SCOPES` is the measured case: no `data` key at all and
      // no `path`. There is nothing to return.
      final api = GitHubApiClient(
        token: 't',
        httpClient: createMockClient({
          'POST /graphql': MockResponse(200, {
            'errors': [
              {
                'type': 'INSUFFICIENT_SCOPES',
                'message': 'Your token has not been granted the scopes '
                    'necessary to perform this action',
              },
            ],
          }),
        }),
      );

      await expectLater(
        api.graphql('query { viewer { login } }'),
        throwsA(isA<GitHubGraphQlException>()
            .having((e) => e.statusCode, 'statusCode', 200)
            .having((e) => e.errors, 'errors', hasLength(1))
            .having((e) => e.message, 'message',
                contains('INSUFFICIENT_SCOPES'))),
      );
      api.close();
    });

    test(
        'GH-GQL-4: an explicit `"data": null` throws too — nothing resolved is '
        'nothing resolved [0922]', () async {
      // The other half of GH-GQL-3, and the reason the constructor does not
      // keep the two apart: a document whose ROOT field failed answers
      // `"data": null` with a path-bearing error. A caller has as little to
      // read as in the fatal case, so carrying the distinction would be
      // carrying a fact with no consumer.
      final api = GitHubApiClient(
        token: 't',
        httpClient: createMockClient({
          'POST /graphql': MockResponse(200, {
            'data': null,
            'errors': [
              {
                'type': 'NOT_FOUND',
                'path': ['node'],
                'message': 'Could not resolve to a node',
              },
            ],
          }),
        }),
      );

      await expectLater(
        api.graphql('query { node(id: "nope") { id } }'),
        throwsA(isA<GitHubGraphQlException>()),
      );
      api.close();
    });

    test(
        'GH-GQL-5: the GraphQL POINT budget does not overwrite the REST '
        'REQUEST budget [0922]', () async {
      // The hazard the two fields exist for. Both surfaces answer
      // `x-ratelimit-*` and they are different currencies — 5000 requests an
      // hour against 5000 points, where one point covers ~100 nodes. One field
      // for both would let a REST caller read a GraphQL reply's points as
      // requests, silently, and only after a GraphQL call had run in between.
      final api = GitHubApiClient(
        token: 't',
        httpClient: createMockClient({
          'GET /repos/o/r': MockResponse(
            200,
            _repoJson(fullName: 'o/r', name: 'r', id: 1, nodeId: 'R_kw1'),
            headers: {
              'x-ratelimit-limit': '5000',
              'x-ratelimit-remaining': '4321',
              'x-ratelimit-reset': '1790000000',
            },
          ),
          'POST /graphql': MockResponse(
            200,
            {
              'data': {'rateLimit': _rateLimit(cost: 7, remaining: 4993)}
            },
            headers: {
              'x-ratelimit-limit': '5000',
              'x-ratelimit-remaining': '4993',
              'x-ratelimit-reset': '1790000000',
            },
          ),
        }),
      );

      await api.getRepository(owner: 'o', repo: 'r');
      expect(api.lastRateLimit?.remaining, 4321);
      expect(api.lastGraphQlRateLimit, isNull,
          reason: 'no GraphQL call has been made yet');

      final response = await api.graphql('query { rateLimit { cost } }');

      expect(api.lastGraphQlRateLimit?.remaining, 4993);
      expect(api.lastRateLimit?.remaining, 4321,
          reason: 'THE POINT: the REST budget is untouched by a GraphQL call');
      // And the document's own cost, which is a different question again —
      // what this query asked for, rather than what the account has left.
      expect(response.cost?.cost, 7);
      expect(response.cost?.nodeCount, 700);
      api.close();
    });

    test(
        'GH-GQL-6: a document that does not ask for `rateLimit` reports no '
        'cost, rather than a zero [0922]', () async {
      final api = GitHubApiClient(
        token: 't',
        httpClient: createMockClient({
          'POST /graphql': MockResponse(200, {
            'data': {
              'viewer': {'login': 'alexis'}
            }
          }),
        }),
      );
      final response = await api.graphql('query { viewer { login } }');
      expect(response.cost, isNull,
          reason: 'a cost of zero would assert the query was free');
      api.close();
    });

    test(
        'GH-GQL-7: transferIssue goes through the public entry point [0922]',
        () async {
      // Not a refactor detail: it is what makes the mutation a caller of the
      // same surface every other consumer uses, so an error-class change is
      // one edit rather than two.
      final bodies = <String>[];
      final api = GitHubApiClient(
        token: 't',
        minMutativeInterval: Duration.zero,
        httpClient: createMockClient(
          {
            'GET /repos/o/r/issues/7':
                MockResponse(200, createIssueJson(number: 7, nodeId: 'I_kw1')),
            'GET /repos/o/other': MockResponse(200, _repoJson()),
            'POST /graphql': MockResponse(200, {
              'data': {
                'transferIssue': {
                  'issue': {'number': 99}
                }
              }
            }),
          },
          onRequest: (request) {
            if (request.url.path.endsWith('/graphql')) bodies.add(request.body);
          },
        ),
      );

      expect(
        await api.transferIssue(
            owner: 'o', repo: 'r', number: 7, targetRepoSlug: 'o/other'),
        99,
      );
      expect(bodies, hasLength(1));
      expect(bodies.single, contains(r'$issueId'));
      expect(bodies.single, contains('"issueId":"I_kw1"'),
          reason: 'variables travel through the entry point, not inlined');
      api.close();
    });

    test(
        'GH-GQL-8: a transfer that GitHub refuses per-field is still a failed '
        'transfer [0922]', () async {
      // The one place a field-scoped error must NOT be handed back as partial
      // success: the mutation has exactly one field, so a failure of it is a
      // failure of the document however GitHub chose to report it.
      final api = GitHubApiClient(
        token: 't',
        minMutativeInterval: Duration.zero,
        httpClient: createMockClient({
          'GET /repos/o/r/issues/7':
              MockResponse(200, createIssueJson(number: 7, nodeId: 'I_kw1')),
          'GET /repos/o/other': MockResponse(200, _repoJson()),
          'POST /graphql': MockResponse(200, {
            'data': {'transferIssue': null},
            'errors': [
              {
                'type': 'FORBIDDEN',
                'path': ['transferIssue'],
                'message': 'must have admin access',
              },
            ],
          }),
        }),
      );

      await expectLater(
        api.transferIssue(
            owner: 'o', repo: 'r', number: 7, targetRepoSlug: 'o/other'),
        throwsA(isA<GitHubException>()
            .having((e) => e.message, 'message', contains('admin access'))),
      );
      api.close();
    });
  });
}
