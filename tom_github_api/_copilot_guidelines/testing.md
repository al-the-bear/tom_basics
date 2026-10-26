# tom_github_api Testing Guidelines

This document describes the testing strategy for `tom_github_api`, covering both unit tests and integration tests.

## Test Architecture Overview

```
tom_github_api/
├── test/                          # Unit tests (mocked HTTP)
│   ├── helpers/
│   │   ├── fixtures.dart          # JSON response fixtures
│   │   └── mock_http_client.dart  # Mock HTTP client factory
│   ├── models/
│   │   └── github_models_test.dart
│   ├── client/
│   │   ├── issues_test.dart
│   │   ├── labels_test.dart
│   │   ├── comments_test.dart
│   │   ├── search_test.dart
│   │   ├── workflow_test.dart
│   │   └── error_handling_test.dart
│   └── http/
│       └── pagination_test.dart
└── tool/
    ├── integration_test.dart       # Quick integration test
    └── api_integration_test.dart   # Comprehensive integration tests
```

## Unit Testing Strategy

Unit tests use **mocked HTTP responses** to test the library without making real API calls. This allows:

- Fast execution (~1 second for all 57 tests)
- No network dependency
- Predictable, deterministic behavior
- Testing edge cases and error conditions

### Mock HTTP Client

The `createMockClient()` function creates a mock that routes requests by `"METHOD /path"`:

```dart
final mockClient = createMockClient({
  'GET /repos/owner/repo/issues/42': MockResponse(
    200,
    createIssueJson(number: 42, title: 'Test'),
  ),
  'POST /repos/owner/repo/issues': MockResponse(
    201,
    createIssueJson(number: 99),
  ),
});
```

### Fixtures

The `fixtures.dart` file provides factory functions that generate realistic GitHub API responses:

| Function | Purpose |
|----------|---------|
| `createIssueJson()` | Issue response with configurable fields |
| `createLabelJson()` | Label response |
| `createCommentJson()` | Comment response |
| `createSearchResultJson()` | Search result wrapper |
| `createErrorJson()` | Error response for testing exceptions |

### Test Naming Convention

Tests follow the `GH-<CAT>-<num>: description [date] (expectation)` pattern:

| Category | Code |
|----------|------|
| Issue operations | ISS |
| Label operations | LBL |
| Comment operations | CMT |
| Search operations | SRC |
| Workflow operations | WFL |
| Model parsing | MDL |
| Pagination | PAG |
| Error handling | ERR |
| Authentication | AUT |

Example:
```dart
test('GH-ISS-3: getIssue throws GitHubNotFoundException for missing issue [2026-02-13] (expect 404)', () async {
  // ...
});
```

### Running Unit Tests

```bash
# All unit tests
dart test

# With baseline tracking (via testkit)
testkit :test

# Specific test file
dart test test/client/issues_test.dart
```

## Integration Testing Strategy

Integration tests run against the **real GitHub API** to verify end-to-end functionality.

### Configuration

| Environment Variable | Purpose | Default |
|---------------------|---------|---------|
| `GITHUB_TEST_TOKEN` | Personal access token | (required) |
| `GITHUB_TEST_REPO` | Test repository slug | `al-the-bear-automated/tom_github_api_test` |

**How configuration works in code:**

```dart
final _token = Platform.environment['GITHUB_TEST_TOKEN'] ?? '';
final _repo = Platform.environment['GITHUB_TEST_REPO'] ?? 'al-the-bear-automated/tom_github_api_test';
```

- `GITHUB_TEST_TOKEN`: If not set, returns empty string → test exits with error
- `GITHUB_TEST_REPO`: If not set, falls back to the default test repo

**Usage examples:**

```bash
# Uses your token + default repo (al-the-bear-automated/tom_github_api_test)
dart run tool/api_integration_test.dart

# Uses your token + custom repo
GITHUB_TEST_REPO=myuser/myrepo dart run tool/api_integration_test.dart
```

The test token needs these permissions:
- **Issues**: Read and write
- **Metadata**: Read (usually auto-granted)

### Test Repository

The default test repository is `al-the-bear-automated/tom_github_api_test`. This is a dedicated repository for API testing — tests create/modify/delete issues and labels here.

**For other developers:** Set `GITHUB_TEST_REPO` to your own test repository.

### Integration Test Files

| File | Purpose | Tests |
|------|---------|-------|
| `tool/integration_test.dart` | Quick smoke test | 9 operations |
| `tool/api_integration_test.dart` | Comprehensive test | 37 operations |

### Running Integration Tests

```bash
# Quick smoke test
dart run tool/integration_test.dart

# Comprehensive test suite
dart run tool/api_integration_test.dart

# With custom repository
GITHUB_TEST_REPO=myuser/myrepo dart run tool/api_integration_test.dart
```

### What Integration Tests Cover

1. **Label Operations**
   - Create with/without description
   - Duplicate detection (422)
   - List, update, delete

2. **Issue Operations**
   - Create with various fields
   - Get by number, 404 handling
   - Update title, body, labels
   - Close/reopen
   - List with filters
   - Pagination

3. **Comment Operations**
   - Add comments
   - List comments
   - Pagination

4. **Search Operations**
   - Repository search
   - Label qualifiers
   - State qualifiers
   - Text search

5. **Parameter Forms**
   - `repoSlug` form (`owner/repo`)
   - Separate `owner`/`repo` parameters
   - Validation errors

6. **Error Handling**
   - 404 → `GitHubNotFoundException`
   - 422 → `GitHubValidationException` with errors
   - Rate limit tracking

### Test Cleanup

Integration tests create and then clean up:
- Issues are closed (not deleted — GitHub doesn't allow deleting issues)
- Labels prefixed with `api-test-` are deleted

## CI Considerations

Unit tests can run in CI without credentials. Integration tests require:

```yaml
env:
  GITHUB_TEST_TOKEN: ${{ secrets.GITHUB_TEST_TOKEN }}
  GITHUB_TEST_REPO: al-the-bear-automated/tom_github_api_test
```

Consider rate limits when running integration tests frequently (5000 requests/hour for authenticated users).

## Adding New Tests

### Unit Test Template

```dart
test('GH-XXX-N: description [YYYY-MM-DD] (expectation)', () async {
  final mockClient = createMockClient({
    'METHOD /path': MockResponse(statusCode, body),
  });
  final api = GitHubApiClient(token: 'test', httpClient: mockClient);
  
  // Test logic
  expect(result, matcher);
  
  api.close();
});
```

### Integration Test Template

Add to `api_integration_test.dart`:

```dart
await _test('N.M New test description', () async {
  final result = await client.someOperation(...);
  _assert(condition, 'description');
});
```

## Test Coverage Summary

| Area | Unit Tests | Integration Tests |
|------|------------|-------------------|
| Models | 17 | — |
| Issues | 12 | 13 |
| Labels | 7 | 5 |
| Comments | 3 | 4 |
| Search | 2 | 4 |
| Workflow | 3 | — |
| Errors | 9 | 3 |
| Pagination | 4 | 2 |
| Parameters | 4 | 4 |
| Rate Limit | — | 2 |
| **Total** | **57** | **37** |
