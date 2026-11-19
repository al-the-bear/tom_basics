# Tom GitHub API — Implementation Guidelines

This document defines the development workflow for `tom_github_api`, emphasizing specification-driven development and test-first implementation.

---

## Core Principle: Test the Specification, Not the Implementation

**Tests verify that the code meets its design specification — not that the current implementation works.**

| Approach | What It Tests | Problem |
|----------|---------------|---------|
| Testing implementation | "Does the code do what it currently does?" | Tests pass even when the code is wrong |
| Testing specification | "Does the code do what it should do?" | Tests fail when the code deviates from design |

Always write tests from the specification. If a test fails, the implementation is wrong — not the test.

---

## Development Sequence

```
1. Specification    → What should the code do?
2. Tests            → How do we verify it does that?
3. Implementation   → Make the tests pass
4. Verification     → Run tests, fix any failures
```

### 1. Specification First

Before writing any code, understand **what** the code should do:

- Read the design document (`doc/github_api_specification.md`)
- Identify the specific behavior being implemented
- Note edge cases and error conditions

### 2. Tests First (TDD)

Write the test **before** implementing the feature or fix.

### 3. Implementation

Implement the minimum code needed to make tests pass.

### 4. Verification

1. Run `dart analyze` — fix all errors and warnings
2. Run `dart test` — verify new tests pass
3. Run full test suite — ensure no regressions
4. Update test expectation from `(FAIL)` to `(PASS)` or remove it

---

## Test Naming Convention

All tests use a structured naming format:

```
<ID>: <description> [<creation-timestamp>] (<expectation>)
```

### Components

| Component | Format | Description |
|-----------|--------|-------------|
| **ID** | `GH-<CAT>-<num>` | Unique identifier (GH = GitHub API) |
| **Description** | Free text | What the test verifies |
| **Timestamp** | `YYYY-MM-DD HH:MM` | When the test was created |
| **Expectation** | `PASS` or `FAIL` | Expected result (optional) |

### ID Categories

| Prefix | Category | Examples |
|--------|----------|----------|
| `GH-AUT-n` | Authentication | GH-AUT-1 |
| `GH-ISS-n` | Issue CRUD | GH-ISS-1 |
| `GH-LBL-n` | Label management | GH-LBL-1 |
| `GH-CMT-n` | Comments | GH-CMT-1 |
| `GH-SRC-n` | Search | GH-SRC-1 |
| `GH-PAG-n` | Pagination | GH-PAG-1 |
| `GH-RAT-n` | Rate limiting | GH-RAT-1 |
| `GH-WFL-n` | Workflow dispatch | GH-WFL-1 |
| `GH-MDL-n` | Data models | GH-MDL-1 |
| `GH-SER-n` | Serialization | GH-SER-1 |
| `GH-ERR-n` | Error handling | GH-ERR-1 |
| `GH-INT-n` | Integration tests | GH-INT-1 |

### Issue-Linked Tests

Tests linked to a `tom_issues` issue embed the issue number:

```
GH-<issue-number>-<CAT>-<num>
```

---

## Testing Strategy

### Unit Tests (Mock-Based)

All GitHub API tests use a **mock HTTP client** — no real API calls. This ensures:

- Tests run fast and offline
- No rate limiting concerns
- Deterministic results
- No test data pollution on GitHub

```dart
// Pattern: inject a mock HTTP client
final mockClient = MockHttpClient();
final api = GitHubApiClient(
  httpClient: mockClient,
  token: 'test-token',
);
```

### Test Response Fixtures

Use JSON fixtures that match real GitHub API responses:

```dart
const issueResponse = '''
{
  "number": 42,
  "title": "Array parser crashes",
  "state": "open",
  "labels": [{"name": "new"}, {"name": "severity:high"}]
}
''';
```

---

## Bug Fixing Workflow

1. **Understand the specification** — What does the design document say?
2. **Write a failing test** — Proves the bug exists
3. **Run the test** — Verify it fails
4. **Fix the implementation** — Match the specification
5. **Verify the fix** — Run the test, run full suite
6. **Update test expectation** — Remove `(FAIL)`

---

## Quality Checklist

Before marking any task complete:

- [ ] Tests written based on **specification**, not implementation
- [ ] Failing test written **before** fix (for bugs)
- [ ] `dart analyze` shows no errors or warnings
- [ ] All related tests pass
- [ ] Full test suite passes (no regressions)
- [ ] Test expectations updated

---

## Related Documents

- [github_api_specification.md](../doc/github_api_specification.md) — API specification
- [issuekit_implementation_todos.md](../../../devops/tom_issue_kit/doc/issuekit_implementation_todos.md) — Phased implementation plan
