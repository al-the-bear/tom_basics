# Changelog

No version of this package has been published to pub.dev. The version numbers
below are the ones `pubspec.yaml` has carried, and each entry lists what landed
while the pubspec carried that number. The top entry is the version the first
publish will carry, and it is still open: a change to the public API adds a
line to it.

## 1.3.0

### Added

- **`package:tom_github_api/testing.dart`** — `FakeGitHubServer`, an in-memory GitHub (git data with content-addressed objects and the non-fast-forward refusal, contents, issues, labels, comments, search with lagging indexes, refusing a query that names neither `is:issue` nor `is:pull-request` with the `422` GitHub answers it with) behind an `http.Client`, and the canned `rateLimited`, `secondaryRateLimited`, `serverError` and `unauthorized` responses. It was test support of the Webwork app and is now the shared test double for any caller of this client; a separate entry point, so the client links no test double. Adds `crypto` as a dependency.
- `createWebhook` / `deleteWebhook` and the `GitHubWebhook` model — the last REST calls a live suite made through an `http.Client` of its own. An inactive hook's creation is how a suite asks whether GitHub accepts an event on a repository; the `422` arrives as a `GitHubException`.
- `GitHubApiClient.credential()` and the `GitHubCredential` model — the token's login, class (classic or fine-grained, read off the presence of `x-oauth-scopes`) and a classic token's scopes, from one `GET /user`. The fine-grained branch is stated as unverified: no fleet host has held one.
- `GitHubHttpClient.getConditionalList` — the array form of the conditional GET (`If-None-Match`, `304` reported as unmodified and counted), beside the object form. `GitHubApiClient.listAllCommentsConditional` reads a whole comment thread conditionally; the entity tag is the first page's and is returned only for a thread that fits in one page.
- **A public GraphQL entry point** — `GitHubApiClient.graphql(query,
  {variables, operationName})`. The client had posted GraphQL since
  `transferIssue` landed, through a private `_http.post('/graphql', …)` that
  only that method could reach, so every other GraphQL need in the workspace
  stood up its own `http.Client` — a second place handling auth, retries and
  the rate-limit headers. The REST surface also cannot reach everything:
  Projects v2 is GraphQL-only, REST Projects classic having been sunset on
  2025-04-01.

  The error handling is shaped by what GitHub actually does rather than by
  what an HTTP client usually does, because GitHub answers **200 for every
  error class** and `path` is the discriminator:

  - a **field-scoped** error (`NOT_FOUND`, `VALIDATION`) arrives with `data`
    present, the offending field null and `path` naming it. Every sibling
    resolved, so it is **returned** — throwing would discard the half that
    worked. Read `GitHubGraphQlResponse.fieldErrors`.
  - a **query-fatal** error (`INSUFFICIENT_SCOPES`) arrives with no `data` key
    at all and no `path`. There is nothing to return, so it **throws**
    `GitHubGraphQlException`. An explicit `"data": null` throws too: nothing
    resolved is nothing resolved.

  There is deliberately no `expectErrors` flag. A flag that suppresses errors
  is one somebody sets once and forgets, and the shape above already gives a
  caller both halves.

- **`GitHubApiClient.lastGraphQlRateLimit`**, beside `lastRateLimit`.

  REST and GraphQL both answer `x-ratelimit-*` and they are **different
  currencies**: 5000 requests an hour against 5000 points, where one point
  covers roughly a hundred nodes. One field for both would let a REST caller
  read a GraphQL reply's points as requests and conclude the account had spent
  far less than it had — silently, and only after a GraphQL call had happened
  to run in between. The budget is routed on the request's own URL, so a
  future GraphQL caller cannot forget to set a flag.

- **`GitHubGraphQlCost`**, read from a document's own `rateLimit { … }` field.
  A different question again from the budget above: what *this query asked
  for*, rather than what the account has left. Null when the document did not
  request it — a zero would assert the query was free. `rateLimit` does not
  exist on `Mutation`, so a mutation's cost is readable only from the headers,
  which is the asymmetry the two accessors exist for.

### Changed

- `transferIssue` posts through the public entry point rather than the private
  one, so it is a caller of the same surface as everything else and an
  error-class change is one edit rather than two. Its behaviour is unchanged:
  the mutation has exactly one field, so **any** error is a failed transfer
  however GitHub chose to report it.

### Fixed

- The test mock now sets `request` on every response it builds, as
  `BaseClient` does in production. It was not merely thinner but
  **unfaithful**, and it hid behaviour that reads the field.

### Documentation

- `GitHubSecondaryRateLimitException` states the measured duration of a
  content-creation block. It said a block was "not something a flush can wait
  out", from one measurement of a client that kept sending; a client that
  stops at the first refusal saw it clear in about two minutes.

## 1.2.0

### Added

- **`GitHubApiClient.getRepository`** and the `GitHubRepository` model. GitHub
  answers a request for a renamed repository's old name with 200 and the
  repository's current `fullName`, so comparing the two is the only way to
  tell a live name from a stale one. `getDefaultBranch` and
  `getRepositoryNodeId` read through the same call.
- **`createUserRepository`** and **`deleteRepository`**. The create takes
  `autoInit`, because a repository with no commits refuses every git-data
  write.
- **`GitHubApiClient.requestCounts`** — requests issued by this client
  instance, and separately the ones answered `304`. `lastRateLimit` is a
  per-token figure, so two clients sharing a token read each other's traffic
  through it. A conditional request answered `304` is not charged, so
  `requests == notModified` over a stretch of polling states that the polling
  was free.
- **A secondary rate limit is classified.** `GitHubSecondaryRateLimitException`
  tells the points throttle from the content-creation block. Both leave the
  primary quota untouched, so only the response body separates them.
- **`GitHubSecondaryRateLimitException.retryAfter`** — the `Retry-After` GitHub
  sent, and null when it sent none.
- **Mutations are paced.** `minMutativeInterval` spaces writes, which is what
  GitHub asks of a client that creates content.
- **`GitHubRetryPolicy.jittered`**, public and static: an additive spread
  clamped to a ceiling, for a caller that schedules its own waits.

### Changed

- `GitHubRetryPolicy` prefers a stated `Retry-After` over its own exponential
  backoff for a secondary limit, and spreads both by jitter. An account-wide
  limit trips every client of the account at once.
- **Breaking:** `GitHubContentWriteResult.treeSha` is a required field. A
  contents write answers with the tree it created, and the model dropped it.

## 1.1.0

### Added

- **`GitHubApiClient.git`** — the git data API: blobs, trees (recursive),
  commits, refs, and a conditional ref read, so polling an unchanged branch
  costs no quota. It is what lets a caller land several files as one commit.
- **`git.deleteRef`**, so a caller that creates a branch can remove it.
- **`GitHubApiClient.contents`** — the repository contents API, for reading and
  writing a single file.
- **`GitHubDeviceFlow`** — OAuth device authorization, so access can be granted
  without pasting a token.
- **`GitHubRetryPolicy`** — tells a primary rate limit, a secondary rate limit
  and a server error apart, and waits accordingly.
- **`updateComment`**, **`deleteComment`** and **`transferIssue`**.
  `GitHubIssue` carries the fields the transfer reads back.

## 1.0.0

- Issues, labels, comments, search and workflow dispatch over token
  authentication, with rate-limit tracking and typed exceptions.
