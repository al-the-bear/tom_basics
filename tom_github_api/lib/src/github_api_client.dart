import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api/github_contents_api.dart';
import 'api/github_git_api.dart';
import 'github_exception.dart';
import 'http/github_http_client.dart';
import 'http/github_retry_policy.dart';
import 'models/github_conditional.dart';
import 'models/github_credential.dart';
import 'models/github_webhook.dart';
import 'models/github_comment.dart';
import 'models/github_issue.dart';
import 'models/github_graphql.dart';
import 'models/github_label.dart';
import 'models/github_rate_limit.dart';
import 'models/github_repository.dart';
import 'models/github_search_result.dart';

/// Main client for the GitHub REST API v3.
///
/// Provides typed access to Issues, Labels, Comments, Search, and
/// Workflow operations, plus repository [contents] and low-level [git] data.
/// All operations require authentication via a Personal Access Token or an
/// OAuth token (see `GitHubDeviceFlow`).
///
/// ```dart
/// final client = GitHubApiClient(token: 'ghp_...');
/// try {
///   final issue = await client.getIssue(
///     owner: 'al-the-bear', repo: 'tom_issues', number: 42);
///   print(issue.title);
/// } finally {
///   client.close();
/// }
/// ```
class GitHubApiClient {
  final GitHubHttpClient _http;

  /// Repository contents — single-path read/write, one commit per write.
  late final GitHubContentsApi contents = GitHubContentsApi(_http);

  /// Low-level git data — refs, commits, trees and blobs. Use this, not
  /// [contents], when several files must change in one commit.
  late final GitHubGitApi git = GitHubGitApi(_http);

  /// [minMutativeInterval] is the smallest gap this client leaves between two
  /// content-changing requests; it also serialises them. See
  /// [GitHubHttpClient.minMutativeInterval] — the short version is that it is
  /// GitHub's own rule, and that observing it is what keeps a large flush from
  /// earning a secondary-limit block it then has to wait out.
  GitHubApiClient({
    required String token,
    http.Client? httpClient,
    String baseUrl = 'https://api.github.com',
    GitHubRetryPolicy retryPolicy = const GitHubRetryPolicy(),
    Duration minMutativeInterval = const Duration(seconds: 1),
  }) : _http = GitHubHttpClient(
          token: token,
          httpClient: httpClient ?? http.Client(),
          baseUrl: baseUrl,
          retryPolicy: retryPolicy,
          minMutativeInterval: minMutativeInterval,
        );

  /// Rate limit info from the most recent API call.
  GitHubRateLimit? get lastRateLimit => _http.lastRateLimit;

  /// The **points** budget the last GraphQL reply reported (woneprpc78).
  ///
  /// A second field rather than a wider one, because REST and GraphQL bill in
  /// different currencies — 5000 requests an hour against 5000 points, where
  /// one point covers roughly a hundred nodes. Folding them together would let
  /// a REST caller read a GraphQL reply's points as requests, and only after a
  /// GraphQL call had happened to run in between.
  GitHubRateLimit? get lastGraphQlRateLimit => _http.lastGraphQlRateLimit;

  /// This client's own request tally — see
  /// [GitHubHttpClient.requestCounts] for why it is per instance rather than
  /// read off the per-token rate-limit counter.
  ({int requests, int notModified}) get requestCounts => _http.requestCounts;

  /// Zero the tally, to measure one stretch of traffic.
  void resetRequestCounts() => _http.resetRequestCounts();

  /// The repository itself.
  ///
  /// GitHub answers a request for a **renamed** repository's old name by
  /// redirecting, so a call that succeeds does not establish that the name you
  /// asked for is the name the repository has. Compare
  /// [GitHubRepository.fullName] against what you asked for when that
  /// distinction matters — as it does for anything that records a repository
  /// name durably.
  Future<GitHubRepository> getRepository({
    String? repoSlug,
    String? owner,
    String? repo,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    return GitHubRepository.fromJson(await _http.get('/repos/$o/$r'));
  }

  /// The repository's default branch — the branch a locator falls back to
  /// when it names none.
  Future<String> getDefaultBranch({
    String? repoSlug,
    String? owner,
    String? repo,
  }) async =>
      (await getRepository(repoSlug: repoSlug, owner: owner, repo: repo))
          .defaultBranch;

  /// Creates a repository owned by the **authenticated user**.
  ///
  /// The name says `user` because the endpoint does: `POST /user/repos` has no
  /// owner parameter, so the token's own account is the owner and nothing else
  /// can be. Creating one inside an organization is a different endpoint
  /// (`POST /orgs/{org}/repos`) with a different permission model, and giving
  /// this method an optional `org:` would let a caller ask for something it
  /// cannot do.
  ///
  /// [autoInit] false leaves the repository with **no commits and therefore no
  /// refs**, which is the state GitHub refuses every git-data write against —
  /// the state a first-run bootstrap has to survive, and the reason this method
  /// exists at all.
  ///
  /// Permission: a fine-grained PAT needs Administration: write; a **classic**
  /// PAT needs `repo`. Note that `repo` alone does *not* carry deletion — see
  /// [deleteRepository].
  Future<GitHubRepository> createUserRepository({
    required String name,
    String? description,
    bool private = true,
    bool autoInit = false,
  }) async =>
      GitHubRepository.fromJson(await _http.post('/user/repos', body: {
        'name': name,
        if (description != null) 'description': description,
        'private': private,
        'auto_init': autoInit,
      }));

  /// Deletes a repository. **Irreversible.**
  ///
  /// Permission: a fine-grained PAT needs Administration: write; a **classic**
  /// PAT needs the separate `delete_repo` scope, which `repo` does not imply.
  /// That asymmetry is worth knowing before you automate a create: a classic
  /// token carrying only `repo` will create a throwaway repository quite
  /// happily and then fail to remove it.
  Future<void> deleteRepository({
    String? repoSlug,
    String? owner,
    String? repo,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    await _http.delete('/repos/$o/$r');
  }

  /// Release HTTP client resources.
  void close() => _http.close();

  // --- Helper ---

  (String, String) _parseSlug(String? repoSlug, String? owner, String? repo) {
    if (repoSlug != null) {
      final parts = repoSlug.split('/');
      if (parts.length != 2) {
        throw ArgumentError('repoSlug must be "owner/repo", got: $repoSlug');
      }
      return (parts[0], parts[1]);
    }
    if (owner != null && repo != null) return (owner, repo);
    throw ArgumentError('Either repoSlug or both owner and repo must be set');
  }

  // ===================================================================
  // ISSUE OPERATIONS
  // ===================================================================

  /// Create a new issue.
  Future<GitHubIssue> createIssue({
    String? repoSlug,
    String? owner,
    String? repo,
    required String title,
    String? body,
    List<String>? labels,
    String? assignee,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    final json = await _http.post(
      '/repos/$o/$r/issues',
      body: {
        'title': title,
        if (body != null) 'body': body,
        if (labels != null) 'labels': labels,
        if (assignee != null) 'assignee': assignee,
      },
    );
    return GitHubIssue.fromJson(json);
  }

  /// Get a single issue by number.
  Future<GitHubIssue> getIssue({
    String? repoSlug,
    String? owner,
    String? repo,
    required int number,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    final json = await _http.get('/repos/$o/$r/issues/$number');
    return GitHubIssue.fromJson(json);
  }

  /// Update an existing issue. Only non-null fields are sent.
  Future<GitHubIssue> updateIssue({
    String? repoSlug,
    String? owner,
    String? repo,
    required int number,
    String? title,
    String? body,
    String? state,
    List<String>? labels,
    String? assignee,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (body != null) data['body'] = body;
    if (state != null) data['state'] = state;
    if (labels != null) data['labels'] = labels;
    if (assignee != null) data['assignee'] = assignee;

    final json = await _http.patch('/repos/$o/$r/issues/$number', body: data);
    return GitHubIssue.fromJson(json);
  }

  /// Close an issue (convenience for updateIssue with state: 'closed').
  Future<GitHubIssue> closeIssue({
    String? repoSlug,
    String? owner,
    String? repo,
    required int number,
  }) {
    return updateIssue(
      repoSlug: repoSlug,
      owner: owner,
      repo: repo,
      number: number,
      state: 'closed',
    );
  }

  /// Reopen an issue (convenience for updateIssue with state: 'open').
  Future<GitHubIssue> reopenIssue({
    String? repoSlug,
    String? owner,
    String? repo,
    required int number,
  }) {
    return updateIssue(
      repoSlug: repoSlug,
      owner: owner,
      repo: repo,
      number: number,
      state: 'open',
    );
  }

  /// Move an issue to another repository, returning its **new number**.
  ///
  /// GraphQL rather than REST because GitHub never shipped a REST transfer
  /// endpoint. Transfer is not cosmetic: the target repository assigns a fresh
  /// issue number, and **labels that do not exist in the target are dropped**,
  /// while the body is copied verbatim. Any scheme that keys an issue by its
  /// number or by a label alone does not survive it.
  // --- GraphQL ---

  /// Posts a GraphQL document and returns what came back (woneprpc78).
  ///
  /// The REST surface cannot reach everything GitHub offers — Projects v2 is
  /// GraphQL-only, REST Projects classic having been sunset on 2025-04-01 — so
  /// this is an entry point rather than a convenience. Before it, the only
  /// GraphQL in this client was the private post behind [transferIssue], and
  /// every other caller in the workspace stood up a second `http.Client`: a
  /// second place handling auth, retries and the rate-limit headers.
  ///
  /// **Field-scoped errors are returned, not thrown.** GitHub answers `200`
  /// for all three error classes, and a `NOT_FOUND` on one field leaves every
  /// sibling resolved (wire-measured by `woneprpb22`); throwing would discard
  /// the half that worked. A caller reads
  /// [GitHubGraphQlResponse.fieldErrors] and decides.
  ///
  /// **A query-fatal error throws.** When nothing resolved — GitHub omits the
  /// `data` key altogether for `INSUFFICIENT_SCOPES`, the measured case, and
  /// answers it null when the root field itself failed — there is nothing to
  /// return, and handing back a response whose `data` is null would leave
  /// every caller to re-derive the distinction that `path` already makes.
  ///
  /// [expectErrors] is deliberately **not** a parameter. A flag that suppresses
  /// errors is a flag somebody sets once and forgets, and the shape above
  /// already gives a caller both halves: partial data with its errors beside
  /// it, or a throw when there is no data at all.
  Future<GitHubGraphQlResponse> graphql(
    String query, {
    Map<String, dynamic>? variables,
    String? operationName,
  }) async {
    final json = await _http.post('/graphql', body: {
      'query': query,
      if (variables != null) 'variables': variables,
      if (operationName != null) 'operationName': operationName,
    });
    final response = GitHubGraphQlResponse.fromJson(json);
    if (response.data == null) {
      throw GitHubGraphQlException(
        // `200` is not a placeholder: GraphQL reports every one of these over
        // a successful HTTP response, and recording the transport status
        // honestly keeps the field meaning "what GitHub answered".
        statusCode: 200,
        message: response.errors.isEmpty
            ? 'GraphQL returned no data and no errors'
            : 'GraphQL query failed: ${response.errors.join('; ')}',
        errors: response.errors,
        responseBody: json,
      );
    }
    return response;
  }

  Future<int> transferIssue({
    String? repoSlug,
    String? owner,
    String? repo,
    required int number,
    required String targetRepoSlug,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    final issue = await getIssue(owner: o, repo: r, number: number);
    final issueId = issue.nodeId;
    if (issueId == null) {
      // `statusCode: 200` throughout this method is not a placeholder: every
      // failure below arrives over a successful HTTP response. GraphQL reports
      // mutation errors in a 200 body, and a REST payload missing `node_id`
      // is a 200 too. Recording the transport status honestly keeps the field
      // meaning "what GitHub answered", and the message carries the diagnosis.
      throw GitHubException(
        statusCode: 200,
        message: 'Issue $o/$r#$number carries no node_id; cannot transfer it',
      );
    }
    final (targetOwner, targetRepo) = _parseSlug(targetRepoSlug, null, null);
    final targetId = await getRepositoryNodeId(
      owner: targetOwner,
      repo: targetRepo,
    );

    // Through the public entry point, so this method is a caller of the same
    // surface every other GraphQL consumer uses rather than the one place
    // that knew how to post one.
    final response = await graphql(
      'mutation(\$issueId: ID!, \$repositoryId: ID!) {'
      ' transferIssue(input: {issueId: \$issueId,'
      ' repositoryId: \$repositoryId}) {'
      ' issue { number } } }',
      variables: {'issueId': issueId, 'repositoryId': targetId},
    );
    // Any error at all is fatal *to a transfer*, field-scoped or not: the
    // mutation has exactly one field, so a failure of it is a failure of the
    // document however GitHub chose to report it.
    if (response.hasErrors) {
      throw GitHubException(
        statusCode: 200,
        message: 'Transfer of $o/$r#$number to $targetRepoSlug failed: '
            '${response.errors.join('; ')}',
        responseBody: response.data,
      );
    }
    final transferred =
        (response.data?['transferIssue'] as Map<String, dynamic>?)?['issue']
            as Map<String, dynamic>?;
    final newNumber = transferred?['number'];
    if (newNumber is! int) {
      throw GitHubException(
        statusCode: 200,
        message: 'Transfer of $o/$r#$number to $targetRepoSlug returned no '
            'new issue number',
        responseBody: response.data,
      );
    }
    return newNumber;
  }

  /// The GraphQL global node id of a repository.
  Future<String> getRepositoryNodeId({
    String? repoSlug,
    String? owner,
    String? repo,
  }) async =>
      (await getRepository(repoSlug: repoSlug, owner: owner, repo: repo))
          .nodeId;

  /// List issues with optional filters. Returns a single page.
  Future<List<GitHubIssue>> listIssues({
    String? repoSlug,
    String? owner,
    String? repo,
    String? state,
    List<String>? labels,
    String? sort,
    String? direction,
    DateTime? since,
    int? perPage,
    int? page,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    final params = <String, String>{};
    if (state != null) params['state'] = state;
    if (labels != null && labels.isNotEmpty) {
      params['labels'] = labels.join(',');
    }
    if (sort != null) params['sort'] = sort;
    if (direction != null) params['direction'] = direction;
    if (since != null) params['since'] = since.toUtc().toIso8601String();
    if (perPage != null) params['per_page'] = perPage.toString();
    if (page != null) params['page'] = page.toString();

    final response =
        await _http.getRaw('/repos/$o/$r/issues', queryParams: params);
    final list = jsonDecode(response.body) as List<dynamic>;

    // Filter out pull requests (they have a 'pull_request' field)
    return list
        .cast<Map<String, dynamic>>()
        .where((j) => !j.containsKey('pull_request'))
        .map(GitHubIssue.fromJson)
        .toList();
  }

  /// Fetch ALL matching issues across all pages (handles pagination).
  Future<List<GitHubIssue>> listAllIssues({
    String? repoSlug,
    String? owner,
    String? repo,
    String? state,
    List<String>? labels,
    String? sort,
    String? direction,
    DateTime? since,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    final params = <String, String>{
      'per_page': '100',
    };
    if (state != null) params['state'] = state;
    if (labels != null && labels.isNotEmpty) {
      params['labels'] = labels.join(',');
    }
    if (sort != null) params['sort'] = sort;
    if (direction != null) params['direction'] = direction;
    if (since != null) params['since'] = since.toUtc().toIso8601String();

    final allIssues = <GitHubIssue>[];
    var response =
        await _http.getRaw('/repos/$o/$r/issues', queryParams: params);
    var list = jsonDecode(response.body) as List<dynamic>;

    allIssues.addAll(
      list
          .cast<Map<String, dynamic>>()
          .where((j) => !j.containsKey('pull_request'))
          .map(GitHubIssue.fromJson),
    );

    // Follow pagination
    var links = parseLinkHeader(response.headers['link']);
    while (links.containsKey('next')) {
      response = await _http.getUrl(links['next']!);
      list = jsonDecode(response.body) as List<dynamic>;
      allIssues.addAll(
        list
            .cast<Map<String, dynamic>>()
            .where((j) => !j.containsKey('pull_request'))
            .map(GitHubIssue.fromJson),
      );
      links = parseLinkHeader(response.headers['link']);
    }

    return allIssues;
  }

  // ===================================================================
  // LABEL OPERATIONS
  // ===================================================================

  /// Create a new label in the repository.
  Future<GitHubLabel> createLabel({
    String? repoSlug,
    String? owner,
    String? repo,
    required String name,
    required String color,
    String? description,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    final json = await _http.post(
      '/repos/$o/$r/labels',
      body: {
        'name': name,
        'color': color,
        if (description != null) 'description': description,
      },
    );
    return GitHubLabel.fromJson(json);
  }

  /// List all labels in the repository.
  Future<List<GitHubLabel>> listLabels({
    String? repoSlug,
    String? owner,
    String? repo,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    final response = await _http.getRaw(
      '/repos/$o/$r/labels',
      queryParams: {'per_page': '100'},
    );
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .cast<Map<String, dynamic>>()
        .map(GitHubLabel.fromJson)
        .toList();
  }

  /// Update an existing label.
  Future<GitHubLabel> updateLabel({
    String? repoSlug,
    String? owner,
    String? repo,
    required String name,
    String? newName,
    String? color,
    String? description,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    final data = <String, dynamic>{};
    if (newName != null) data['new_name'] = newName;
    if (color != null) data['color'] = color;
    if (description != null) data['description'] = description;

    final json = await _http.patch('/repos/$o/$r/labels/$name', body: data);
    return GitHubLabel.fromJson(json);
  }

  /// Delete a label from the repository.
  Future<void> deleteLabel({
    String? repoSlug,
    String? owner,
    String? repo,
    required String name,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    await _http.delete('/repos/$o/$r/labels/$name');
  }

  /// Add labels to an issue without removing existing ones.
  Future<List<GitHubLabel>> addLabelsToIssue({
    String? repoSlug,
    String? owner,
    String? repo,
    required int issueNumber,
    required List<String> labels,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    // POST /repos/{owner}/{repo}/issues/{number}/labels returns an array
    final response = await _http.postRaw(
      '/repos/$o/$r/issues/$issueNumber/labels',
      body: {'labels': labels},
    );
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .cast<Map<String, dynamic>>()
        .map(GitHubLabel.fromJson)
        .toList();
  }

  /// Remove a single label from an issue.
  Future<void> removeLabelFromIssue({
    String? repoSlug,
    String? owner,
    String? repo,
    required int issueNumber,
    required String label,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    await _http.delete('/repos/$o/$r/issues/$issueNumber/labels/$label');
  }

  // ===================================================================
  // COMMENT OPERATIONS
  // ===================================================================

  /// Add a comment to an issue.
  Future<GitHubComment> addComment({
    String? repoSlug,
    String? owner,
    String? repo,
    required int issueNumber,
    required String body,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    final json = await _http.post(
      '/repos/$o/$r/issues/$issueNumber/comments',
      body: {'body': body},
    );
    return GitHubComment.fromJson(json);
  }

  /// Edit an existing issue comment.
  ///
  /// Comments are addressed by their own **comment id**, not by the issue
  /// number — that is how the REST API models them, and it is why the issue
  /// number is absent from the signature.
  Future<GitHubComment> updateComment({
    String? repoSlug,
    String? owner,
    String? repo,
    required int commentId,
    required String body,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    final json = await _http.patch(
      '/repos/$o/$r/issues/comments/$commentId',
      body: {'body': body},
    );
    return GitHubComment.fromJson(json);
  }

  /// Delete an issue comment.
  Future<void> deleteComment({
    String? repoSlug,
    String? owner,
    String? repo,
    required int commentId,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    await _http.delete('/repos/$o/$r/issues/comments/$commentId');
  }

  /// List comments for an issue (single page).
  Future<List<GitHubComment>> listComments({
    String? repoSlug,
    String? owner,
    String? repo,
    required int issueNumber,
    int? perPage,
    int? page,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    final params = <String, String>{};
    if (perPage != null) params['per_page'] = perPage.toString();
    if (page != null) params['page'] = page.toString();

    final response = await _http.getRaw(
      '/repos/$o/$r/issues/$issueNumber/comments',
      queryParams: params,
    );
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .cast<Map<String, dynamic>>()
        .map(GitHubComment.fromJson)
        .toList();
  }

  /// Fetch ALL comments for an issue across all pages.
  Future<List<GitHubComment>> listAllComments({
    String? repoSlug,
    String? owner,
    String? repo,
    required int issueNumber,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    final allComments = <GitHubComment>[];

    var response = await _http.getRaw(
      '/repos/$o/$r/issues/$issueNumber/comments',
      queryParams: {'per_page': '100'},
    );
    var list = jsonDecode(response.body) as List<dynamic>;
    allComments.addAll(
        list.cast<Map<String, dynamic>>().map(GitHubComment.fromJson));

    var links = parseLinkHeader(response.headers['link']);
    while (links.containsKey('next')) {
      response = await _http.getUrl(links['next']!);
      list = jsonDecode(response.body) as List<dynamic>;
      allComments.addAll(
          list.cast<Map<String, dynamic>>().map(GitHubComment.fromJson));
      links = parseLinkHeader(response.headers['link']);
    }

    return allComments;
  }

  /// Fetch ALL comments for an issue, **conditionally**.
  ///
  /// `If-None-Match` on the first page: a `304` witnesses the thread itself —
  /// which the issue's `updated_at` cannot, since editing a comment does not
  /// bump it — and GitHub does not charge a `304` against the quota. The
  /// entity tag returned is the **first page's**, and it is returned only for
  /// a thread that fits in one page: a tag over page one says nothing about
  /// a comment on page two, so a thread with a `next` link comes back with
  /// `etag: null` and is re-read in full next time.
  Future<GitHubConditional<List<GitHubComment>>> listAllCommentsConditional({
    String? repoSlug,
    String? owner,
    String? repo,
    required int issueNumber,
    String? ifNoneMatch,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    final first = await _http.getConditionalList(
      '/repos/$o/$r/issues/$issueNumber/comments',
      queryParams: {'per_page': '100'},
      ifNoneMatch: ifNoneMatch,
    );
    if (first.notModified) return GitHubConditional.unmodified(etag: ifNoneMatch);
    final allComments = <GitHubComment>[
      ...first.value!.cast<Map<String, dynamic>>().map(GitHubComment.fromJson),
    ];
    // The Link header is not on the conditional result, so a thread past one
    // page is walked the way [listAllComments] walks it — and is not tagged.
    if (allComments.length < 100) {
      return GitHubConditional.modified(allComments, etag: first.etag);
    }
    return GitHubConditional.modified(
      await listAllComments(owner: o, repo: r, issueNumber: issueNumber),
      etag: null,
    );
  }

  /// What this client's token is: the login it authenticates as, its class
  /// (classic or fine-grained), and a classic token's scopes — read from
  /// `GET /user`'s body and its `x-oauth-scopes` header in one request.
  ///
  /// The credential *class* is load-bearing for the live suites (a branch
  /// refuses a classic PAT carrying `repo`; a probe skips without `project`),
  /// and until this existed every one of them stood up an `http.Client` of its
  /// own to read one response header. The parsing is an API fact and lives
  /// here; what a consumer refuses on the strength of it is its own policy.
  /// See [GitHubCredential] for the unverified fine-grained branch.
  Future<GitHubCredential> credential() async {
    final response = await _http.getRaw('/user');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return GitHubCredential.fromHeaders(
      response.headers,
      login: body['login'] as String,
    );
  }

  /// Creates a repository webhook. A hook created **inactive** is never
  /// called, which makes creation itself the cheapest way to ask whether
  /// GitHub accepts an event on a repository: it answers at creation time,
  /// `201` or `422`, and the `422` arrives as a [GitHubException] carrying
  /// GitHub's own words.
  Future<GitHubWebhook> createWebhook({
    String? repoSlug,
    String? owner,
    String? repo,
    required String url,
    required List<String> events,
    bool active = true,
    String contentType = 'json',
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    final json = await _http.post('/repos/$o/$r/hooks', body: {
      'name': 'web',
      'active': active,
      'events': events,
      'config': {'url': url, 'content_type': contentType},
    });
    return GitHubWebhook.fromJson(json);
  }

  /// Deletes a repository webhook by id.
  Future<void> deleteWebhook({
    String? repoSlug,
    String? owner,
    String? repo,
    required int id,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    await _http.delete('/repos/$o/$r/hooks/$id');
  }

  // ===================================================================
  // SEARCH OPERATIONS
  // ===================================================================

  /// Search issues using GitHub's search syntax.
  Future<GitHubSearchResult> searchIssues({
    required String query,
    String? sort,
    String? order,
    int? perPage,
    int? page,
  }) async {
    final params = <String, String>{
      'q': query,
    };
    if (sort != null) params['sort'] = sort;
    if (order != null) params['order'] = order;
    if (perPage != null) params['per_page'] = perPage.toString();
    if (page != null) params['page'] = page.toString();

    final json = await _http.get('/search/issues', queryParams: params);
    return GitHubSearchResult.fromJson(json);
  }

  // ===================================================================
  // WORKFLOW OPERATIONS
  // ===================================================================

  /// Trigger a GitHub Actions workflow via workflow_dispatch.
  Future<void> dispatchWorkflow({
    String? repoSlug,
    String? owner,
    String? repo,
    required String workflowId,
    String ref = 'main',
    Map<String, String>? inputs,
  }) async {
    final (o, r) = _parseSlug(repoSlug, owner, repo);
    await _http.postNoContent(
      '/repos/$o/$r/actions/workflows/$workflowId/dispatches',
      body: {
        'ref': ref,
        if (inputs != null) 'inputs': inputs,
      },
    );
  }
}
