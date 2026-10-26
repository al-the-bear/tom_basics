# Tom GitHub API — Specification

This document defines the API surface, data models, and behavior of the `tom_github_api` package — a reusable Dart library for interacting with the GitHub Issues API.

---

## Overview

`tom_github_api` provides typed Dart access to the GitHub REST API v3, focused on the subset needed by `tom_issue_kit` and `tom_test_kit`:

- **Issues**: CRUD operations, state management, filtering
- **Labels**: Create, list, add/remove from issues
- **Comments**: Add, list per issue
- **Search**: Full-text search via GitHub Search API
- **Workflow Dispatch**: Trigger GitHub Actions workflows
- **Authentication**: Token-based (Personal Access Token)
- **Rate Limiting**: Detection, reporting, retry

The library is **standalone** — it has no dependency on `tom_build_base`, `tom_issue_kit`, or `tom_test_kit`.

---

## Architecture

```
tom_github_api/
├── lib/
│   ├── tom_github_api.dart              # Public API barrel file
│   └── src/
│       ├── github_api_client.dart        # Main client class
│       ├── github_exception.dart         # Exception types
│       ├── models/
│       │   ├── github_issue.dart         # Issue model
│       │   ├── github_label.dart         # Label model
│       │   ├── github_comment.dart       # Comment model
│       │   ├── github_rate_limit.dart    # Rate limit info
│       │   ├── github_search_result.dart # Search result wrapper
│       │   └── github_user.dart          # User model (minimal)
│       ├── auth/
│       │   └── github_auth.dart          # Token resolution
│       └── http/
│           ├── github_http_client.dart   # HTTP wrapper with auth/rate-limit
│           └── paginated_response.dart   # Pagination helper
├── test/
│   ├── models/
│   │   ├── github_issue_test.dart
│   │   ├── github_label_test.dart
│   │   ├── github_comment_test.dart
│   │   └── github_search_result_test.dart
│   ├── auth/
│   │   └── github_auth_test.dart
│   ├── http/
│   │   ├── github_http_client_test.dart
│   │   └── paginated_response_test.dart
│   ├── client/
│   │   ├── issues_test.dart
│   │   ├── labels_test.dart
│   │   ├── comments_test.dart
│   │   ├── search_test.dart
│   │   └── workflow_test.dart
│   └── helpers/
│       ├── mock_http_client.dart
│       └── fixtures.dart
└── doc/
    └── github_api_specification.md       # This file
```

---

## Data Models

### GitHubIssue

Represents a GitHub Issue (used for both tom_issues and tom_tests entries).

```dart
class GitHubIssue {
  final int number;
  final String title;
  final String? body;
  final String state;           // 'open' or 'closed'
  final List<GitHubLabel> labels;
  final GitHubUser? assignee;
  final GitHubUser user;        // Creator
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? closedAt;
  final int commentsCount;
  final String htmlUrl;
}
```

**Serialization**: `fromJson(Map<String, dynamic>)` and `toJson()`.

**Behavior**:
- `number` is the unique issue identifier within a repository
- `state` is either `'open'` or `'closed'` (GitHub API values)
- `labels` contains the full label objects (name + color)
- `commentsCount` comes from the `comments` field in the API response

### GitHubLabel

```dart
class GitHubLabel {
  final int? id;
  final String name;
  final String? color;          // 6-char hex without '#'
  final String? description;
}
```

**Serialization**: `fromJson(Map<String, dynamic>)` and `toJson()`.

**Behavior**:
- `name` is the primary identifier (used for matching)
- `color` is a 6-character hex string (e.g., `'ff0000'`)
- `id` may be null when creating a new label (assigned by GitHub)

### GitHubComment

```dart
class GitHubComment {
  final int id;
  final String body;
  final GitHubUser user;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

**Serialization**: `fromJson(Map<String, dynamic>)` and `toJson()`.

### GitHubUser

Minimal user representation.

```dart
class GitHubUser {
  final String login;
  final int id;
  final String? avatarUrl;
}
```

**Serialization**: `fromJson(Map<String, dynamic>)` and `toJson()`.

### GitHubRateLimit

```dart
class GitHubRateLimit {
  final int limit;        // Max requests per hour
  final int remaining;    // Requests remaining
  final DateTime resetAt; // When the limit resets
}
```

**Serialization**: From `X-RateLimit-*` response headers.

**Behavior**:
- Parsed from every API response's headers
- `resetAt` is derived from the `X-RateLimit-Reset` header (Unix timestamp)

### GitHubSearchResult

```dart
class GitHubSearchResult {
  final int totalCount;
  final bool incompleteResults;
  final List<GitHubIssue> items;
}
```

**Serialization**: `fromJson(Map<String, dynamic>)`.

---

## GitHubApiClient

The main client class. All operations are methods on this class.

### Construction

```dart
class GitHubApiClient {
  GitHubApiClient({
    required String token,
    Client? httpClient,       // For testing — inject mock
    String baseUrl = 'https://api.github.com',
  });

  void close();               // Release HTTP client resources
}
```

**Behavior**:
- If `httpClient` is not provided, creates a default `http.Client()`
- `close()` must be called when done to release resources
- `baseUrl` defaults to GitHub's API but can be overridden for testing or GitHub Enterprise

### Repository Targeting

All methods take an `owner` and `repo` parameter (or a combined `repoSlug` like `'al-the-bear/tom_issues'`):

```dart
// Two forms — both equivalent:
client.getIssue(owner: 'al-the-bear', repo: 'tom_issues', number: 42);
client.getIssue(repoSlug: 'al-the-bear/tom_issues', number: 42);
```

The `repoSlug` form splits on `/` internally. If both forms are provided, `repoSlug` takes precedence.

---

## Issue Operations

### createIssue

```dart
Future<GitHubIssue> createIssue({
  required String owner,
  required String repo,
  required String title,
  String? body,
  List<String>? labels,
  String? assignee,
});
```

**API**: `POST /repos/{owner}/{repo}/issues`

**Behavior**:
- Creates a new issue in the specified repository
- Returns the created issue with its assigned number
- `labels` are label names — they must already exist in the repo
- Throws `GitHubException` on failure (401, 403, 404, 422)

### getIssue

```dart
Future<GitHubIssue> getIssue({
  required String owner,
  required String repo,
  required int number,
});
```

**API**: `GET /repos/{owner}/{repo}/issues/{number}`

**Behavior**:
- Returns the issue with full details
- Throws `GitHubNotFoundException` if issue doesn't exist
- Throws `GitHubException` on other errors

### updateIssue

```dart
Future<GitHubIssue> updateIssue({
  required String owner,
  required String repo,
  required int number,
  String? title,
  String? body,
  String? state,              // 'open' or 'closed'
  List<String>? labels,       // Replaces ALL labels
  String? assignee,
});
```

**API**: `PATCH /repos/{owner}/{repo}/issues/{number}`

**Behavior**:
- Only provided fields are updated (null fields are not sent)
- `labels` replaces ALL labels on the issue (GitHub API behavior)
- To add a label without removing others, read current labels first
- Returns the updated issue
- Throws `GitHubNotFoundException` if issue doesn't exist

### closeIssue

```dart
Future<GitHubIssue> closeIssue({
  required String owner,
  required String repo,
  required int number,
});
```

**Convenience**: Calls `updateIssue` with `state: 'closed'`.

### reopenIssue

```dart
Future<GitHubIssue> reopenIssue({
  required String owner,
  required String repo,
  required int number,
});
```

**Convenience**: Calls `updateIssue` with `state: 'open'`.

### listIssues

```dart
Future<List<GitHubIssue>> listIssues({
  required String owner,
  required String repo,
  String? state,              // 'open', 'closed', 'all' (default: 'open')
  List<String>? labels,       // Filter by labels (comma-separated in API)
  String? sort,               // 'created', 'updated', 'comments'
  String? direction,          // 'asc' or 'desc'
  DateTime? since,            // Only issues updated after this date
  int? perPage,               // Items per page (max 100, default 30)
  int? page,                  // Page number
});
```

**API**: `GET /repos/{owner}/{repo}/issues`

**Behavior**:
- Returns issues matching the filters
- Default: open issues only, sorted by creation date descending
- GitHub's API returns pull requests mixed with issues; this library filters them out (issues have no `pull_request` field)
- For fetching ALL issues, use `listAllIssues` (handles pagination)

### listAllIssues

```dart
Future<List<GitHubIssue>> listAllIssues({
  required String owner,
  required String repo,
  String? state,
  List<String>? labels,
  String? sort,
  String? direction,
  DateTime? since,
});
```

**Behavior**:
- Fetches ALL matching issues across all pages (100 per page)
- Follows `Link` header pagination until no more pages
- Returns the complete list
- Use for snapshots and exports where all data is needed

---

## Label Operations

### createLabel

```dart
Future<GitHubLabel> createLabel({
  required String owner,
  required String repo,
  required String name,
  required String color,      // 6-char hex without '#'
  String? description,
});
```

**API**: `POST /repos/{owner}/{repo}/labels`

**Behavior**:
- Creates a new label
- Throws `GitHubValidationException` if label already exists (422)
- Color must be a 6-character hex string

### listLabels

```dart
Future<List<GitHubLabel>> listLabels({
  required String owner,
  required String repo,
});
```

**API**: `GET /repos/{owner}/{repo}/labels`

**Behavior**:
- Returns all labels in the repository
- Handles pagination internally

### updateLabel

```dart
Future<GitHubLabel> updateLabel({
  required String owner,
  required String repo,
  required String name,
  String? newName,
  String? color,
  String? description,
});
```

**API**: `PATCH /repos/{owner}/{repo}/labels/{name}`

**Behavior**:
- Updates an existing label
- `name` identifies the label; `newName` renames it
- Only provided fields are updated

### deleteLabel

```dart
Future<void> deleteLabel({
  required String owner,
  required String repo,
  required String name,
});
```

**API**: `DELETE /repos/{owner}/{repo}/labels/{name}`

### addLabelsToIssue

```dart
Future<List<GitHubLabel>> addLabelsToIssue({
  required String owner,
  required String repo,
  required int issueNumber,
  required List<String> labels,
});
```

**API**: `POST /repos/{owner}/{repo}/issues/{issueNumber}/labels`

**Behavior**:
- Adds labels without removing existing ones
- Returns the complete list of labels on the issue

### removeLabelFromIssue

```dart
Future<void> removeLabelFromIssue({
  required String owner,
  required String repo,
  required int issueNumber,
  required String label,
});
```

**API**: `DELETE /repos/{owner}/{repo}/issues/{issueNumber}/labels/{label}`

**Behavior**:
- Removes a single label from an issue
- Throws `GitHubNotFoundException` if label is not on the issue

---

## Comment Operations

### addComment

```dart
Future<GitHubComment> addComment({
  required String owner,
  required String repo,
  required int issueNumber,
  required String body,
});
```

**API**: `POST /repos/{owner}/{repo}/issues/{issueNumber}/comments`

**Behavior**:
- Adds a comment to an issue
- Returns the created comment

### listComments

```dart
Future<List<GitHubComment>> listComments({
  required String owner,
  required String repo,
  required int issueNumber,
  int? perPage,
  int? page,
});
```

**API**: `GET /repos/{owner}/{repo}/issues/{issueNumber}/comments`

### listAllComments

```dart
Future<List<GitHubComment>> listAllComments({
  required String owner,
  required String repo,
  required int issueNumber,
});
```

**Behavior**:
- Fetches ALL comments across all pages
- For snapshot/export use cases

---

## Search Operations

### searchIssues

```dart
Future<GitHubSearchResult> searchIssues({
  required String query,
  String? sort,               // 'created', 'updated', 'comments'
  String? order,              // 'asc' or 'desc'
  int? perPage,
  int? page,
});
```

**API**: `GET /search/issues?q={query}`

**Behavior**:
- Searches across all accessible repositories (or scoped by `repo:` qualifier in query)
- Returns `GitHubSearchResult` with total count and items
- The query uses GitHub's search syntax: `repo:owner/name state:open label:bug`
- Rate limit for search API is lower (30 requests/minute)

---

## Workflow Operations

### dispatchWorkflow

```dart
Future<void> dispatchWorkflow({
  required String owner,
  required String repo,
  required String workflowId,  // Filename or ID
  String ref = 'main',         // Branch to run on
  Map<String, String>? inputs,
});
```

**API**: `POST /repos/{owner}/{repo}/actions/workflows/{workflowId}/dispatches`

**Behavior**:
- Triggers a `workflow_dispatch` event
- Returns void (GitHub returns 204 No Content on success)
- `workflowId` can be the workflow file name (e.g., `nightly_tests.yml`) or numeric ID
- Throws `GitHubNotFoundException` if workflow doesn't exist

---

## Authentication

### GitHubAuth

```dart
class GitHubAuth {
  /// Resolve a token from multiple sources (in order):
  /// 1. Explicit `token` parameter
  /// 2. `GITHUB_TOKEN` environment variable
  /// 3. Token file at `~/.tom/github_token`
  ///
  /// Returns null if no token is found.
  static String? resolveToken({String? token});

  /// Resolve a token, throwing if not found.
  static String resolveTokenOrThrow({String? token});
}
```

**Resolution order**:
1. Explicit token parameter (highest priority)
2. `GITHUB_TOKEN` environment variable
3. File: `~/.tom/github_token` (first line, trimmed)

**Behavior**:
- `resolveToken` returns `null` if no source has a token
- `resolveTokenOrThrow` throws `GitHubAuthException` if no token found

---

## Error Handling

### Exception Types

```dart
/// Base exception for all GitHub API errors
class GitHubException implements Exception {
  final int statusCode;
  final String message;
  final String? documentationUrl;
  final Map<String, dynamic>? responseBody;
}

/// 404 Not Found
class GitHubNotFoundException extends GitHubException {}

/// 401 Unauthorized / 403 Forbidden
class GitHubAuthException extends GitHubException {}

/// 422 Unprocessable Entity (validation errors)
class GitHubValidationException extends GitHubException {
  final List<Map<String, dynamic>>? errors;  // Validation error details
}

/// 403 Rate Limit Exceeded
class GitHubRateLimitException extends GitHubException {
  final GitHubRateLimit rateLimit;
}
```

**Behavior**:
- All exceptions extend `GitHubException`
- `GitHubRateLimitException` includes the rate limit info (when it resets)
- Exceptions are created from the HTTP response body (JSON)
- Unknown status codes produce a generic `GitHubException`

### Error Mapping

| HTTP Status | Exception Type | Meaning |
|-------------|---------------|---------|
| 200-299 | (none) | Success |
| 304 | (none) | Not Modified |
| 401 | `GitHubAuthException` | Bad token |
| 403 | `GitHubRateLimitException` or `GitHubAuthException` | Rate limit OR insufficient permissions |
| 404 | `GitHubNotFoundException` | Resource not found |
| 422 | `GitHubValidationException` | Invalid request data |
| 5xx | `GitHubException` | Server error |

### Distinguishing 403

A 403 response could be rate limiting or permissions. The library checks:
- If `X-RateLimit-Remaining` header is `0`, it's a `GitHubRateLimitException`
- Otherwise, it's a `GitHubAuthException`

---

## HTTP Layer

### GitHubHttpClient

Internal class that wraps `http.Client` with:

1. **Authentication**: Adds `Authorization: Bearer {token}` header to all requests
2. **Content Type**: Sets `Accept: application/vnd.github+json` and `X-GitHub-Api-Version: 2022-11-28`
3. **Rate Limit Tracking**: Parses `X-RateLimit-*` headers from every response
4. **Error Handling**: Converts non-2xx responses to typed exceptions

```dart
class GitHubHttpClient {
  GitHubHttpClient({
    required String token,
    required Client httpClient,
    required String baseUrl,
  });

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? queryParams});
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body});
  Future<Map<String, dynamic>> patch(String path, {Map<String, dynamic>? body});
  Future<void> delete(String path);

  /// Current rate limit info from the last response
  GitHubRateLimit? get lastRateLimit;

  void close();
}
```

### Pagination

The `Link` header from paginated responses is parsed:

```dart
class PaginatedResponse<T> {
  final List<T> items;
  final String? nextPageUrl;
  final String? lastPageUrl;
  final bool hasNextPage;
}
```

**Behavior**:
- `listAllIssues` and `listAllComments` follow pagination automatically
- Each page request is a separate API call
- Pages are requested with `per_page=100` (maximum)

---

## Usage Example

```dart
import 'package:tom_github_api/tom_github_api.dart';

void main() async {
  final token = GitHubAuth.resolveTokenOrThrow();
  final client = GitHubApiClient(token: token);

  try {
    // Create an issue
    final issue = await client.createIssue(
      owner: 'al-the-bear',
      repo: 'tom_issues',
      title: 'Array parser crashes on empty arrays',
      body: 'The parser throws RangeError when given []',
      labels: ['new', 'severity:high'],
    );
    print('Created issue #${issue.number}');

    // Add a comment
    await client.addComment(
      owner: 'al-the-bear',
      repo: 'tom_issues',
      issueNumber: issue.number,
      body: 'Root cause: missing empty check in _parseElements()',
    );

    // Update labels (state transition)
    await client.removeLabelFromIssue(
      owner: 'al-the-bear',
      repo: 'tom_issues',
      issueNumber: issue.number,
      label: 'new',
    );
    await client.addLabelsToIssue(
      owner: 'al-the-bear',
      repo: 'tom_issues',
      issueNumber: issue.number,
      labels: ['analyzed'],
    );

    // Search
    final results = await client.searchIssues(
      query: 'repo:al-the-bear/tom_issues state:open label:severity:high',
    );
    print('Found ${results.totalCount} high-severity issues');

    // Snapshot — get all issues
    final allIssues = await client.listAllIssues(
      owner: 'al-the-bear',
      repo: 'tom_issues',
      state: 'all',
    );
    print('Total issues: ${allIssues.length}');
  } finally {
    client.close();
  }
}
```

---

## Dependencies

| Package | Purpose |
|---------|---------|
| `http` | HTTP client for API requests |
| `test` (dev) | Unit testing |

No other dependencies. The library is self-contained.

---

## Constraints

- **No real API calls in tests**: All tests use mock HTTP clients
- **No caching**: Each call hits the API (caching is the consumer's responsibility)
- **No retry logic**: Rate limit exceptions are thrown, not retried (consumer decides)
- **Thread safety**: Not guaranteed — single-client-per-isolate pattern assumed
- **GitHub API version**: Targets `2022-11-28` (via `X-GitHub-Api-Version` header)
