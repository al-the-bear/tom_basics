# Tom Build Base — Implementation Guidelines

This document defines the development workflow for `tom_build_base`, emphasizing specification-driven development and test-first implementation.

---

## Core Principle: Test the Specification, Not the Implementation

**Tests verify that the code meets its design specification — not that the current implementation works.**

This distinction is critical:

| Approach | What It Tests | Problem |
|----------|---------------|---------|
| Testing implementation | "Does the code do what it currently does?" | Tests pass even when the code is wrong |
| Testing specification | "Does the code do what it should do?" | Tests fail when the code deviates from design |

When a test is written based on implementation, it becomes a snapshot of current behavior — including bugs. When a test is written based on specification, it becomes a contract that the code must fulfill.

### Example

**Specification says:** DartPackageFolder requires `pubspec.yaml` AND `lib/src/` directory.

**Implementation does:** Returns DartPackageFolder for any Dart project without `bin/`, regardless of `lib/src/`.

- **Implementation-based test:** Passes (matches current behavior)
- **Specification-based test:** Fails (catches the bug)

Always write tests from the specification. If a test fails, the implementation is wrong — not the test.

---

## Development Sequence

The correct sequence for implementing features or fixing bugs:

```
1. Specification    → What should the code do?
2. Tests            → How do we verify it does that?
3. Implementation   → Make the tests pass
4. Verification     → Run tests, fix any failures
```

### 1. Specification First

Before writing any code, understand **what** the code should do:

- Read the design document (e.g., `doc/cli_v2_design.md`)
- Identify the specific behavior being implemented
- Note edge cases and error conditions
- If the spec is unclear, clarify before proceeding

For tom_build_base v2, the authoritative specification is [cli_v2_design.md](../doc/cli_v2_design.md).

### 2. Tests First (TDD)

Write the test **before** implementing the feature or fix:

```dart
test('BB-NAT-42: DartPackageFolder requires lib/src/ [2026-02-12 14:00] (FAIL)', () {
  // Create Dart project without bin/ or lib/src/
  final dir = createTempDir();
  File('$dir/pubspec.yaml').writeAsStringSync('name: test_pkg');
  
  final nature = detector.detectNature(Folder(dir));
  
  // Per spec: DartPackageFolder requires lib/src/
  expect(nature is DartPackageFolder, isFalse);
});
```

**Why test first?**

1. **Proves the test catches the problem** — If the test passes before you fix anything, the test is wrong
2. **Defines the goal clearly** — You know exactly what success looks like
3. **Prevents over-engineering** — You implement only what's needed to pass the test
4. **Documents the requirement** — The test IS the executable specification

### 3. Implementation

Now implement the feature or fix to make the test pass:

- Write the minimum code needed
- Keep the specification in mind, not just the test
- Run the test to verify

### 4. Verification

After implementation:

1. Run `dart analyze` — fix all errors and warnings
2. Run `dart test` — verify the new test passes
3. Run full test suite — ensure no regressions
4. Update test expectation from `(FAIL)` to `(PASS)` or remove it

---

## Test Naming Convention

All tests use a structured naming format for traceability and baseline tracking:

```
<ID>: <description> [<creation-timestamp>] (<expectation>)
```

### Components

| Component | Format | Description |
|-----------|--------|-------------|
| **ID** | `BB-<CAT>-<num>` | Unique identifier (BB = Build Base) |
| **Description** | Free text | What the test verifies |
| **Creation timestamp** | `YYYY-MM-DD HH:MM` | When the test was created |
| **Expectation** | `PASS` or `FAIL` | Expected result (optional, omit for normal tests) |

### ID Categories

| Prefix | Category | Examples |
|--------|----------|----------|
| `BB-NAT-n` | Nature detection | BB-NAT-1, BB-NAT-42 |
| `BB-FLT-n` | Filter pipeline | BB-FLT-1 |
| `BB-SCN-n` | Folder scanner | BB-SCN-1 |
| `BB-NAV-n` | Navigation/traversal | BB-NAV-1 |
| `BB-CTX-n` | Command context | BB-CTX-1 |
| `BB-CLI-n` | CLI argument parsing | BB-CLI-1 |
| `BB-INT-n` | Integration tests | BB-INT-1 |

### Examples

```dart
// Normal test (expected to pass)
test('BB-NAT-1: Detects Flutter project by sdk dependency [2026-02-12 10:00]', () {
  // ...
});

// Bug reproduction test (expected to fail until fixed)
test('BB-NAT-42: DartPackageFolder requires lib/src/ [2026-02-12 14:00] (FAIL)', () {
  // ...
});

// Issue-linked test (from tom_issues)
test('BB-156-NAT-3: Empty pubspec handling [2026-02-12 15:00] (FAIL)', () {
  // ...
});
```

### Issue-Linked Tests

Tests linked to a `tom_issues` issue embed the issue number:

```
BB-<issue-number>-<CAT>-<num>
```

Example: `BB-156-NAT-3` links to issue #156 in tom_issues.

---

## Bug Fixing Workflow

When a bug is discovered:

### 1. Understand the Specification

What does the design document say the behavior should be?

### 2. Write a Failing Test

Create a test that demonstrates the bug:

```dart
test('BB-NAT-42: BUG: Dart project without bin/ or lib/src/ misclassified [2026-02-12 14:00] (FAIL)', () {
  // Setup: Dart project with pubspec.yaml but no bin/ and no lib/src/
  final dir = createTempDir();
  File('$dir/pubspec.yaml').writeAsStringSync('name: test_pkg');
  
  final nature = detector.detectNature(Folder(dir));
  
  // Per spec: Should NOT be DartPackageFolder (requires lib/src/)
  // Per spec: Should be generic DartProjectFolder
  expect(nature is DartPackageFolder, isFalse,
    reason: 'Per design spec: DartPackageFolder requires lib/src/');
});
```

### 3. Run the Test — Verify It Fails

```bash
dart test --name "BB-NAT-42"
```

**If the test passes, the test is wrong.** Re-read the specification and fix the test.

### 4. Fix the Implementation

Modify the code to match the specification.

### 5. Verify the Fix

```bash
dart test --name "BB-NAT-42"  # Should pass now
dart test                      # Full suite — no regressions
dart analyze                   # No errors
```

### 6. Update Test Expectation

Remove `(FAIL)` or change to `(PASS)`:

```dart
test('BB-NAT-42: Dart project without bin/ or lib/src/ is generic DartProjectFolder [2026-02-12 14:00]', () {
  // ...
});
```

---

## Test Organization

### Directory Structure

```
test/
├── v2/
│   ├── core/                    # CLI core tests
│   │   ├── cli_arg_parser_test.dart
│   │   ├── command_definition_test.dart
│   │   └── ...
│   ├── folder/                  # Folder nature tests
│   │   └── natures/
│   │       └── dart_project_folder_test.dart
│   ├── traversal/               # Traversal system tests
│   │   ├── nature_detector_test.dart
│   │   ├── filter_pipeline_test.dart
│   │   ├── folder_scanner_test.dart
│   │   └── build_base_integration_test.dart
│   └── ...
└── ...
```

### Test Categories

| Category | Purpose | Location |
|----------|---------|----------|
| **Unit tests** | Test individual classes/functions in isolation | `test/v2/<component>/` |
| **Integration tests** | Test components working together | `test/v2/traversal/*_integration_test.dart` |
| **Design verification** | Verify behavior matches specification | Group: "Design specification: ..." |

### Integration Test Projects

Integration tests use real project structures in `zom_workspaces/zom_analyzer_test/`:

| Test Project | Purpose |
|--------------|---------|
| `zom_test_standalone` | Standalone Dart project (no lib/) |
| `zom_test_flutter` | Flutter project |
| `zom_test_package` | Dart package with lib/src/ |
| `zom_test_vscode_ext` | VS Code extension (TypeScript) |
| `zom_test_workspace` | Nested workspace structure |

---

## Testkit Integration

Use `testkit` for test execution and baseline tracking:

```bash
# Run tests and compare against baseline
testkit :test

# Create a new baseline
testkit :baseline
```

Baseline files in `doc/baseline_MMDD_HHMM.csv` track test results over time.

### Result Format

`<current>/<baseline>` where `-` = SKIP, `X` = FAIL, `OK` = PASS

| Result | Meaning |
|--------|---------|
| `OK/OK` | Test passes, as expected |
| `X/OK` | **Regression** — test now fails |
| `OK/X` | **Fix** — test now passes |
| `X/X` | Known failure (expected) |

---

## Quality Checklist

Before marking any implementation task complete:

- [ ] Tests written based on **specification**, not implementation
- [ ] Failing test written **before** fix (for bugs)
- [ ] `dart analyze` shows no errors or warnings
- [ ] All related tests pass
- [ ] Full test suite passes (no regressions)
- [ ] Test expectations updated (`FAIL` → `PASS` or removed)

---

## Related Documents

- [cli_v2_design.md](../doc/cli_v2_design.md) — Authoritative specification for v2 API
- [build_base_user_guide.md](../doc/build_base_user_guide.md) — API documentation
- [index.md](index.md) — Guidelines index
