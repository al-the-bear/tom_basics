# Tom Build Kit — Testing Guidelines

## Test Strategy: Workspace Integration Tests

Buildkit tests are **integration tests** that run against the **real workspace**. They exercise the actual CLI tools by spawning them as child processes, then verify outcomes through file system checks and git diffs.

**No one may make changes to the workspace during tests.** The tests assume exclusive access to the workspace. Any concurrent changes will corrupt test results and may prevent git revert from working correctly.

## Pre-Test Safety Protocol

**This protocol MUST be followed before running any integration tests.** There are no shortcuts or workarounds.

### Step 1: Commit and push all submodules

Every submodule must be clean (no uncommitted changes) and pushed to origin.

```bash
# For each submodule:
cd xternal/<submodule>
git add -A && git commit -m "..." && git push
```

### Step 2: Commit and push the main workspace repo

```bash
cd <workspace-root>
git add -A && git commit -m "..." && git push
```

### Step 3: Make a backup copy of the complete workspace

This is the secondary safety net. If a tool under test deletes git files or otherwise destroys the workspace beyond what `git checkout` can recover, this backup is the fallback.

```bash
cp -a tom2 tom2_backup
```

### Step 4: Run the test loop

For each test:

1. **Run** the test (installs fixture, executes tool)
2. **Verify** changes (check generated files, stdout, exit code)
3. **Revert** all changes via `git checkout -- .` from workspace root (and submodule roots if needed)

The `tearDown()` in each test file handles the revert automatically. The `setUpAll()` verifies the workspace is in a clean state before any tests run.

## Test Architecture

### Core Mechanism

1. **Install fixture**: Copy a test-specific `buildkit_master.yaml` into the workspace root, overwriting the real one
2. **Run tool**: Execute the buildkit command via `dart run <path/to/bin/tool.dart>`
3. **Verify**: Check exit code, stdout/stderr, generated/modified files
4. **Revert**: `git checkout -- .` restores everything (fixture, generated files, state files)

### Directory Layout

```
tom_build_kit/
  test/
    helpers/
      test_workspace.dart      # Shared utilities: fixture swap, git revert, process runner
    fixtures/
      versioner/
        buildkit_master.yaml   # Minimal master config for versioner tests
      exclusion/
        buildkit_master.yaml   # Minimal master config for exclusion tests
      cleanup/
        buildkit_master.yaml   # Minimal master config for cleanup tests
      pipeline/
        buildkit_master.yaml   # Pipeline-specific configs
    versioner_test.dart         # Versioner tool integration tests
    exclusion_test.dart         # Cross-tool project exclusion tests (27 tests)
    cleanup_test.dart           # Cleanup tool integration tests
    pipeline_test.dart          # Buildkit pipeline integration tests
```

### Fixture Design Principles

- Each fixture `buildkit_master.yaml` targets **1–2 small projects** to keep tests fast
- Fixtures define only the **minimum config** needed for the specific test
- The `navigation:` section in fixtures uses explicit `exclude:` patterns to limit scope
- Target projects must be in the **main repo** (not submodules) for simple git revert

### Test Helper: TestWorkspace

The shared `TestWorkspace` class provides:

- **Workspace protection protocol**:
  - `requireCleanWorkspace()` — fails if uncommitted changes exist (call in `setUpAll`)
  - `saveHeadRefs()` — records HEAD SHAs for main repo + all submodules (call in `setUpAll`)
  - `verifyHeadRefs()` — post-suite check that no commits leaked (call in `tearDownAll`)
  - `tearDownProtocol()` — combined revert + verify for `tearDownAll`
- **Skip file support**: `isSkippedRepo(path)` — checks for `buildkit_skip.yaml` marker; repos with this file are excluded from test git operations (no commit check, no checkout revert)
- **Skip file placement**: `placeSkipFile(relativeDir)` — creates a temporary `buildkit_skip.yaml` in a directory; `removeSkipFile(relativeDir)` — removes it. Tests should track placed files and clean them up in `tearDown`.
- **Fixture installation**: `installFixture(name)` — copies fixture `buildkit_master.yaml` to workspace root
- **Git revert**: `revertAll()` — reverts all changes in main repo; `revertSubmodule(path)` — reverts submodule
- **Tool execution**: `runTool(name, args)` — runs a tool via `dart run <bin/tool.dart>` from workspace root
- **Pipeline execution**: `runPipeline(name, args)` — runs buildkit with a pipeline name
- **File helpers**: `readWorkspaceFile()`, `workspaceFileExists()` — read/check files relative to workspace root
- **Dirty check**: `hasUncommittedChanges()` — verifies workspace is clean before tests start

### Automatic Workspace Protection

When you run `dart test`, the test infrastructure **automatically** protects the workspace:

1. `setUpAll` calls `requireCleanWorkspace()` + `saveHeadRefs()`
2. Each `tearDown` calls `revertAll()` to restore files
3. `tearDownAll` calls `verifyHeadRefs()` to verify no commits leaked

This means even a single test file run (`dart test test/versioner_test.dart`) provides full workspace protection without any manual steps beyond the initial commit/push.

### `--exclude-projects` Pattern Matching

The `--exclude-projects` option supports two kinds of glob patterns, auto-detected at match time:

**Basename patterns** (no `/` or `**` in the pattern):
- Matched against the project directory's basename only
- Example: `--exclude-projects 'zom_*'` excludes all projects whose folder name starts with `zom_`
- Example: `--exclude-projects 'tom_d4rt*'` excludes `tom_d4rt` and `tom_d4rt_generator`

**Path patterns** (contain `/` or `**`):
- Matched against the workspace-relative path of the project
- Example: `--exclude-projects 'basics/*'` excludes all projects under the basics sub-repo
- Example: `--exclude-projects '**/basics/*'` matches regardless of leading path segments

**Auto-detection rule:** If the pattern contains `/` or `**`, it is treated as a path pattern. Otherwise it is treated as a basename pattern. Both types can be combined in a single invocation by passing `--exclude-projects` multiple times.

This same logic applies to:
- `--exclude-projects` CLI flag on all tools (via `ToolBase._filterProjectsByName`)
- `--exclude-projects` CLI flag on buildkit (via `_filterProjectPaths`)
- `exclude-projects` list in `buildkit_master.yaml` navigation section

### buildkit_skip.yaml

A marker file `buildkit_skip.yaml` in a directory root excludes that directory from:

- **Tool processing**: ProjectDiscovery skips the directory and all subdirectories
- **Test git operations**: `saveHeadRefs()` and `tearDownProtocol()` skip repos with this file
- **buildkit scanning**: Both `--exclude-projects` and skip file checks apply

### Git Revert Strategy

After each test (`tearDown`):

1. `git checkout -- .` from workspace root — restores `buildkit_master.yaml`, generated files, state files
2. For submodule targets: `git checkout -- .` from submodule root

The revert restores all tracked files to their committed state. Untracked files created by tests are not automatically cleaned — tests that create new files must delete them explicitly.

### Test Isolation Rules

- Each test gets a fresh fixture installed in `setUp` or at test start
- Each test reverts all changes in `tearDown`
- Tests **must not depend on execution order**
- Tests **must not leave untracked files** behind (delete them in tearDown if created)
- The `setUpAll()` verifies the workspace starts clean

## Test Coverage

See [doc/test_coverage.md](../doc/test_coverage.md) for the complete feature coverage plan with all tools and their testable features.

## Running Tests

```bash
cd basics/tom_build_kit
dart test
```

Individual test files:

```bash
dart test test/versioner_test.dart
```
