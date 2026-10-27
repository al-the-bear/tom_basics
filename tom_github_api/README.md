# Tom GitHub API

Published on pub.dev as [`tom_github_api` 1.3.0](https://pub.dev/packages/tom_github_api).

> Tom GitHub API is part of the **Tom framework** by al-the-bear.
> Distributed under the terms in this package's license — see
> [LICENSE](LICENSE).

Typed Dart client for the GitHub REST API v3 — issues, labels, comments, search
and workflows.

`tom_github_api` is a small, standalone Dart library that wraps the
[GitHub REST API v3](https://docs.github.com/en/rest) with typed models, token
authentication, transparent pagination, rate-limit tracking and a structured
exception hierarchy. It implements exactly the slice the Tom CLI kits need —
**issues, labels, comments, search and workflow dispatch** — and nothing more,
so it stays dependency-light (`http` only) and easy to reason about.

It is the HTTP engine under [`tom_issue_kit`](../../devops/tom_issue_kit/) (the `issuekit`
CLI) and the GitHub-backed flows in [`tom_test_kit`](../../devops/tom_test_kit/).

---

## Overview

GitHub's REST API is large; the Tom kits use a narrow, well-defined corner of
it. `tom_github_api` packages that corner as a reusable library so each kit does
not re-implement request signing, JSON parsing, pagination and error mapping.

| Concern | What the library does |
| ------- | --------------------- |
| **Typed surface** | Every response becomes a Dart model (`GitHubIssue`, `GitHubLabel`, `GitHubComment`, `GitHubUser`, `GitHubRateLimit`, `GitHubSearchResult`, `GitHubRepository`, `GitHubContentEntry`, `GitHubGitRef`) — no raw maps leak to callers. |
| **Authentication** | Resolves a Personal Access Token from an explicit argument, the `GITHUB_TOKEN` environment variable, or `~/.tom/github_token` (in that order). |
| **Pagination** | `listAll…` methods follow GitHub's `Link` header to fetch every page; single-page `list…` methods expose `perPage`/`page` for manual control. |
| **Rate limiting** | Every response updates `lastRateLimit`; a 403 with `x-ratelimit-remaining: 0` is raised as a dedicated `GitHubRateLimitException`. |
| **Structured errors** | HTTP failures map to typed exceptions (`GitHubNotFoundException`, `GitHubAuthException`, `GitHubValidationException`, `GitHubRateLimitException`) instead of bare status codes. |
| **Testing** | `package:tom_github_api/testing.dart` is an in-memory GitHub — git data, contents and issues — for callers' tests. |

The library is **standalone** — it has no dependency on `tom_build_base`,
`tom_issue_kit` or `tom_test_kit`; the dependency arrow points the other way.

### What it does *not* cover

The surface is intentionally scoped to what its consumers use. It does **not**
implement pull-request or release endpoints, and of the repository endpoints it
implements the read that identifies a repository (`getRepository` and the two
accessors over it) and creating and deleting a user's repository. If a
consumer grows a need for one of those, the
endpoint is added here first (with tests) — never worked around in the
consumer.

---

## Installation

`tom_github_api` is a standalone library. It has not been published to
pub.dev, so a consumer inside this workspace takes it by path — here from a
package in another `tom_ai` repository, such as `tom_ai/devops/tom_issue_kit`:

```yaml
dependencies:
  tom_github_api:
    path: ../../basics/tom_github_api
```

### Versions and the changelog

- **A change to the public API adds a line to the top entry of
  [`CHANGELOG.md`](CHANGELOG.md).** That entry is the version `pubspec.yaml`
  names, and it stays open until that version is published.
- **A feature commit does not bump the version.** The version moves when a
  version is published: the publish closes the top entry, and the next change
  opens a new one with the next number.
- The pubspec version and the top changelog entry are the same number. A test
  holds them together.

```dart
import 'package:tom_github_api/tom_github_api.dart';
```

**SDK requirement:** Dart `^3.10.8`. **Runtime dependency:** `http: ^1.3.0` (the
only one).

---

## Features

### Operations

| Group | Methods |
| ----- | ------- |
| **Issues** | `createIssue`, `getIssue`, `updateIssue`, `closeIssue`, `reopenIssue`, `listIssues` (single page), `listAllIssues` (all pages) |
| **Labels** | `createLabel`, `listLabels`, `updateLabel`, `deleteLabel`, `addLabelsToIssue`, `removeLabelFromIssue` |
| **Comments** | `addComment`, `listComments` (single page), `listAllComments` (all pages), `listAllCommentsConditional` (`If-None-Match`; a `304` is unmodified and uncharged) |
| **Search** | `searchIssues` (GitHub search syntax) |
| **Credential** | `credential()` — the token's login, class (classic / fine-grained by the presence of `x-oauth-scopes`) and scopes, from one `GET /user` |
| **Workflows** | `dispatchWorkflow` (trigger a GitHub Actions `workflow_dispatch`) |
| **Webhooks** | `createWebhook`, `deleteWebhook` |
| **Repositories** | `getRepository`, `getDefaultBranch`, `getRepositoryNodeId` |
| **Contents** (`client.contents`) | `readFile`, `writeFile`, `deleteFile`, `stat`, `listDirectory` |
| **Git data** (`client.git`) | `getRef`, `getRefConditional`, `createRef`, `updateRef`, `deleteRef`, `getCommit`, `createCommit`, `getTree`, `getTreeOrNull`, `createTree`, `createBlob`, `getBlob` |

#### A repository name is not a repository identity

`getRepository` returns a `GitHubRepository` whose `fullName` is the name the
repository has **today**. That need not be the name you asked for: GitHub keeps
a redirect from a repository's pre-rename name, so a request for a stale name
returns **200** and answers with the current name. A call that merely
*succeeds* therefore establishes nothing about the name you hold — and the
redirect stops working the day somebody creates a new repository under the
freed-up name, at which point the stale reference silently retargets to
somebody else's repository.

```dart
final repo = await client.getRepository(repoSlug: recorded);
if (repo.fullName != recorded) {
  // `recorded` survives only as a rename redirect.
}
```

Compare the two whenever a repository name is stored durably. `id` is the
rename-stable identity when you need to ask whether two names are the same
repository.

### Cross-cutting

| Capability | Where |
| ---------- | ----- |
| Token resolution | `GitHubAuth.resolveToken` / `resolveTokenOrThrow` |
| Rate-limit snapshot | `GitHubApiClient.lastRateLimit` → `GitHubRateLimit` (per **token**) |
| Own request tally | `GitHubApiClient.requestCounts` → `(requests, notModified)` (per **client**) |
| Typed errors | `GitHubException` + four subtypes |
| Pull-request filtering | `listIssues` / `listAllIssues` drop entries that carry a `pull_request` field, so you get issues only |
| Custom base URL | `GitHubApiClient(baseUrl: …)` for GitHub Enterprise |
| Injectable transport | `GitHubApiClient(httpClient: …)` for testing with a mock client |

### Repo addressing

Every repo-scoped method accepts the target either as a single
`repoSlug: 'owner/repo'` **or** as separate `owner:` + `repo:` arguments — pick
whichever reads better at the call site.

---

## Quick start

```dart
import 'package:tom_github_api/tom_github_api.dart';

void main() async {
  // Resolve a token from arg / GITHUB_TOKEN / ~/.tom/github_token.
  final token = GitHubAuth.resolveTokenOrThrow();
  final client = GitHubApiClient(token: token);

  try {
    final issues = await client.listIssues(
      repoSlug: 'al-the-bear/tom_issues',
      state: 'open',
    );
    for (final issue in issues) {
      print('#${issue.number}: ${issue.title}'); // #42: Pagination bug
    }
  } on GitHubException catch (e) {
    print('GitHub error ${e.statusCode}: ${e.message}');
  } finally {
    client.close(); // always release the underlying http.Client
  }
}
```

Always `close()` the client when you are done — it owns an `http.Client`.

---

## Example projects

| Location | What it shows |
| -------- | ------------- |
| [`example/tom_github_api_example.dart`](example/tom_github_api_example.dart) | Minimal end-to-end: resolve a token, list issues, print them. |
| [`test/`](test/) | 57 tests across client / models / http / error handling, run against a mock `http.Client` (no network). |
| [`tool/integration_test.dart`](tool/integration_test.dart), [`tool/api_integration_test.dart`](tool/api_integration_test.dart) | Opt-in integration checks that hit the **live** GitHub API (require a real token). |
| [`tom_devops_samples/tom_github_api_sample/`](../../devops/tom_devops_samples/tom_github_api_sample/) | The flagship devops sample, built on this library — see the [samples learning path](../../devops/tom_devops_samples/README.md). |

---

## Usage

### 1. Authentication

`GitHubAuth` resolves a Personal Access Token from three sources, in order:

1. an explicit `token:` argument,
2. the `GITHUB_TOKEN` environment variable,
3. the file `~/.tom/github_token` (first line only).

```dart
// Returns null if nothing is found.
final maybe = GitHubAuth.resolveToken();

// Throws GitHubAuthError (with a message listing all three sources) if missing.
final token = GitHubAuth.resolveTokenOrThrow();

// Or pass one explicitly — it always wins.
final explicit = GitHubAuth.resolveTokenOrThrow(token: 'ghp_xxx');
```

The token is sent as `Authorization: Bearer <token>` with
`Accept: application/vnd.github+json` and `X-GitHub-Api-Version: 2022-11-28` on
every request.

### 2. Issues

```dart
final client = GitHubApiClient(token: token);

// Create
final created = await client.createIssue(
  repoSlug: 'al-the-bear/tom_issues',
  title: 'Flaky pagination test',
  body: 'Fails ~1 in 10 runs.',
  labels: ['bug', 'flaky'],
  assignee: 'al-the-bear',
);

// Read
final issue = await client.getIssue(
  repoSlug: 'al-the-bear/tom_issues', number: created.number);

// Update (only non-null fields are sent)
await client.updateIssue(
  repoSlug: 'al-the-bear/tom_issues',
  number: issue.number,
  labels: ['bug'],
);

// Close / reopen (convenience over updateIssue)
await client.closeIssue(repoSlug: 'al-the-bear/tom_issues', number: issue.number);
await client.reopenIssue(repoSlug: 'al-the-bear/tom_issues', number: issue.number);
```

#### Listing and pagination

`listIssues` returns a single page (use `perPage`/`page` to walk manually);
`listAllIssues` transparently follows the `Link` header until every matching
issue is fetched:

```dart
// One page, filtered.
final page1 = await client.listIssues(
  repoSlug: 'al-the-bear/tom_issues',
  state: 'open',
  labels: ['bug'],
  sort: 'updated',
  direction: 'desc',
  perPage: 50,
  page: 1,
);

// Everything, across all pages (per_page=100 internally).
final all = await client.listAllIssues(
  repoSlug: 'al-the-bear/tom_issues',
  state: 'all',
  since: DateTime.utc(2026, 1, 1),
);
```

Both methods **exclude pull requests** — GitHub returns PRs from the issues
endpoint, and the client drops any entry carrying a `pull_request` field.

### 3. Labels

```dart
await client.createLabel(
  repoSlug: 'al-the-bear/tom_issues',
  name: 'needs-triage',
  color: 'ededed',
  description: 'Awaiting first review',
);

final labels = await client.listLabels(repoSlug: 'al-the-bear/tom_issues');

await client.updateLabel(
  repoSlug: 'al-the-bear/tom_issues',
  name: 'needs-triage',
  newName: 'triage',
  color: 'fbca04',
);

// Add labels to an issue without clearing existing ones.
await client.addLabelsToIssue(
  repoSlug: 'al-the-bear/tom_issues', issueNumber: 42, labels: ['triage']);

await client.removeLabelFromIssue(
  repoSlug: 'al-the-bear/tom_issues', issueNumber: 42, label: 'triage');

await client.deleteLabel(repoSlug: 'al-the-bear/tom_issues', name: 'triage');
```

### 4. Comments

```dart
await client.addComment(
  repoSlug: 'al-the-bear/tom_issues',
  issueNumber: 42,
  body: 'Reproduced on CI — see run #1234.',
);

// Single page or all pages.
final page = await client.listComments(
  repoSlug: 'al-the-bear/tom_issues', issueNumber: 42, perPage: 30);
final everything = await client.listAllComments(
  repoSlug: 'al-the-bear/tom_issues', issueNumber: 42);
```

### 5. Search

```dart
final result = await client.searchIssues(
  query: 'repo:al-the-bear/tom_issues is:open label:bug',
  sort: 'updated',
  order: 'desc',
);
print('${result.totalCount} matches');
for (final issue in result.items) {
  print('#${issue.number}: ${issue.title}');
}
```

### 6. Workflow dispatch

```dart
await client.dispatchWorkflow(
  repoSlug: 'al-the-bear/tom_issues',
  workflowId: 'verify.yml',
  ref: 'main',
  inputs: {'issue': '42'},
);
```

### 7. Errors and rate limits

Every failed request maps to a typed exception so callers can branch on cause,
not status code:

```dart
try {
  await client.getIssue(repoSlug: 'al-the-bear/tom_issues', number: 999999);
} on GitHubNotFoundException {
  // 404 — issue doesn't exist
} on GitHubValidationException catch (e) {
  // 422 — e.errors holds the field-level details
} on GitHubRateLimitException catch (e) {
  // 403 with remaining == 0 — e.rateLimit.resetAt tells you when to retry
} on GitHubAuthException {
  // 401 / 403 — bad or missing token
} on GitHubException catch (e) {
  // any other non-2xx
  print('${e.statusCode}: ${e.message}');
}

// Inspect the most recent rate-limit snapshot at any time.
final rl = client.lastRateLimit;
if (rl != null && rl.remaining < 10) {
  print('Slow down — ${rl.remaining} calls left until ${rl.resetAt}');
}

// What THIS client has spent. `lastRateLimit` is a per-TOKEN figure, so two
// clients sharing a token read each other's traffic through it; `requestCounts`
// is per instance, which is the scope "how much did my client spend" actually
// has. `requests` counts round trips, so a retry counts twice.
client.resetRequestCounts();
await client.listAllIssues(owner: 'o', repo: 'r');
final spent = client.requestCounts;

// GitHub does not charge a conditional request it answers 304, so over a
// stretch of polling `requests == notModified` *is* "this cost no quota" —
// observable without reading a quota counter at all.
print('${spent.requests} requests, ${spent.notModified} of them free');
```

### Testing against a mock transport

Inject any `http.Client` to test without a network:

```dart
final client = GitHubApiClient(
  token: 'test-token',
  httpClient: myMockHttpClient, // returns canned responses
);
```

This is how the package's own suite runs — see
[`test/helpers/mock_http_client.dart`](test/helpers/mock_http_client.dart).

### Testing against an in-memory GitHub

A canned transport answers what a test told it to. A caller that does more than
one request — commits through the git data API, or keeps an issue in step with a
store — needs a GitHub that behaves. `package:tom_github_api/testing.dart`
provides one: `FakeGitHubServer`.

```dart
import 'package:tom_github_api/testing.dart';
import 'package:tom_github_api/tom_github_api.dart';

final server = FakeGitHubServer();
server.commitFiles('acme/notes', {'README.md': 'hello'});
final client = GitHubApiClient(
  token: 'test',
  httpClient: server.client,
  baseUrl: FakeGitHubServer.baseUrl,
);
```

What it reproduces, because a caller that ignored it would pass against a
looser fake and fail against GitHub:

- **Git objects are content-addressed** — blobs, trees and commits hash as git
  hashes them, so equal content has one sha and a subtree sha changes exactly
  when something under it changes.
- **A ref update that is not a fast-forward is refused** with `422`, the
  compare-and-swap a multi-file commit relies on.
  `FakeGitHubServer.beforeRefUpdate` lands a competing commit inside a writer's
  read-modify-write window.
- **Conditional reads are free** — an unchanged ref or list answers `304`, and
  `notModifiedCount` says how many did.
- **Issues**: bodies have no compare-and-swap (`beforeIssueUpdate`); transfer
  drops labels the target lacks; the list and search indexes lag the issue and
  each other (`indexLag`, `searchIndexExcludes`, `searchIncomplete`); labels
  longer than GitHub's 50 characters are refused.
- **Failures**: `canned` queues responses for the next requests —
  `rateLimited`, `secondaryRateLimited`, `serverError`, `unauthorized` — and
  `contentCreationBlocked` refuses issue and comment writes while serving
  everything else, the shape GitHub gives a content-creation block.

It is its own entry point so that nothing importing the client links a test
double; import it from tests only.

---

## Architecture

```
            GitHubApiClient            ← public façade: typed operations
                  │  delegates transport to
                  ▼
            GitHubHttpClient           ← internal: signs requests, tracks
                  │                       rate limits, maps errors, paginates
       ┌──────────┼──────────┐
       ▼          ▼          ▼
   GitHubAuth  models     GitHubException (+ subtypes)
   (token      (Issue,    NotFound / Auth /
    resolution) Label,    Validation / RateLimit
                Comment…)
                  │
                  ▼
            GitHub REST API v3
```

`GitHubApiClient` is the only class callers construct. It owns an internal
`GitHubHttpClient` (not exported) that adds the auth headers, records the
rate-limit headers, raises typed exceptions on non-2xx responses, and follows
`Link` headers for the `listAll…` methods. Models are immutable value types
built from JSON via `fromJson` factories.

### Key types

| Type | Role |
| ---- | ---- |
| `GitHubApiClient` | Public client — all issue / label / comment / search / workflow operations; `lastRateLimit`; `requestCounts` / `resetRequestCounts()`; `close()`. |
| `GitHubAuth` | Static token resolver (`resolveToken`, `resolveTokenOrThrow`); throws `GitHubAuthError` when no token is found. |
| `GitHubException` | Base API exception (`statusCode`, `message`, `documentationUrl`, `responseBody`); `fromResponse` factory picks the subtype. |
| `GitHubNotFoundException` | 404. |
| `GitHubAuthException` | 401 / 403 (bad or missing token, not rate limit). |
| `GitHubValidationException` | 422 — carries field-level `errors`. |
| `GitHubRateLimitException` | 403 with `x-ratelimit-remaining: 0` — carries a `GitHubRateLimit`. |
| `GitHubIssue` | Issue model (number, title, body, state, labels, assignee, user, timestamps, `commentsCount`, `htmlUrl`). |
| `GitHubLabel` | Label model (id, name, color, description). |
| `GitHubComment` | Comment model (id, body, user, timestamps). |
| `GitHubUser` | Minimal user model (login, id, avatarUrl). |
| `GitHubRateLimit` | Rate-limit snapshot (limit, remaining, resetAt); `fromHeaders`. |
| `GitHubSearchResult` | Search wrapper (totalCount, incompleteResults, items). |

(`GitHubHttpClient` is internal and intentionally not exported.)

---

## Ecosystem

```
        tom_issue_kit (issuekit)      tom_test_kit (testkit)
                 │                            │
                 └──────────────┬─────────────┘
                                │ depend on
                                ▼
                       ┌──────────────────┐
                       │  tom_github_api  │  ← you are here
                       └──────────────────┘
                                │ depends on
                                ▼
                          package:http
```

`tom_github_api` sits at the bottom of the GitHub-facing stack: the kits call
it, it calls `http`, and it depends on nothing else in the workspace.

---

## Further documentation

| Document | What it covers |
| -------- | -------------- |
| [`doc/github_api_specification.md`](doc/github_api_specification.md) | The authoritative API specification — full surface, data models, behaviour, error mapping and rate-limit rules. |

### Related packages

| Package | Relationship |
| ------- | ------------ |
| [`tom_issue_kit`](../../devops/tom_issue_kit/) | The `issuekit` CLI — primary consumer of this client. |
| [`tom_test_kit`](../../devops/tom_test_kit/) | The `testkit` CLI — uses the GitHub-backed flows. |
| [Tom DevOps map](../README.md) | The repository-level index for the whole devops toolchain. |

---

## Status

- **Version:** 1.3.0, not published. See [`CHANGELOG.md`](CHANGELOG.md).
- **SDK:** Dart `^3.10.8`
- **Runtime dependencies:** `http: ^1.3.0` (only).
- **Surface:** Issues, Labels, Comments, Search, Workflow dispatch, the git
  data and contents APIs, repository read / create / delete, GraphQL, token
  and device-flow auth, rate-limit tracking and retry, typed exceptions. (No
  pull-request / release endpoints — added on demand.)
- **Tests:** 139 (mock-transport unit suite) + opt-in live-API integration
  checks under `tool/`.

---

## License

See [LICENSE](LICENSE); each package in this repository carries its own license
terms.
