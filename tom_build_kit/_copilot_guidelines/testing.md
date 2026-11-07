# Tom Build Kit — Testing Guidelines

## Test Strategy: Integration Tests on the Workspace Clone

Buildkit's integration tests exercise the real CLI tools by spawning them as child processes against the workspace's project tree, then verify outcomes through file system checks and git diffs. They do NOT run in the live workspace: they run on the machine's **workspace clone** (tom_test_support `TomWorkspaceClone`; see `_copilot_guidelines/dart/tests_buildtools.md` at the workspace root), so they can run while other sessions edit the tree, and nothing they install, generate or revert can reach it.

No preparation is needed: no commit, no push, no backup. `testkit :test` (or `dart test`) from the package root runs everything. The first run on a machine creates the clone (a few minutes); later runs only bring it up to date.

### The clone

`TestWorkspace.isolated()` acquires the clone for the live workspace above this package (`TomWorkspaceClone.findLiveRoot`):

- it sits beside the workspace, `<parent>/tom_agent_container_testclone` (`TOM_TEST_WORKSPACE` overrides it), gitignored by the parent repository;
- it is a **full clone with every submodule**, so a test sees the real repository structure, real sources and real nested repositories;
- before the run each repository is brought to the commit its live repository has checked out, fetched from the live repository itself (no network); its `origin` cannot push;
- one clone per machine, held under an **exclusive lock** (`<clone>.lock`): a second suite waits for the first;
- on release every repository is reset to that commit, `reset --hard` and `clean -fd` (ignored files are kept);
- a marker (`.git/tom_workspace_clone.json`); every `TestWorkspace` method that changes the tree, runs git or runs buildkit refuses a root without it.

buildkit is compiled once per suite to a kernel snapshot under this package's `.dart_tool/tom_build_kit_test/`, instead of `dart run` recompiling it for every call; `dispose()` deletes it.

### Core Mechanism

1. **Acquire** (`setUpAll`): `ws = await TestWorkspace.isolated();`
2. **Install fixture**: copy a test-specific `buildkit_master.yaml` into the clone's root, and provision the `_build` project from `test/fixtures/build_project/_build`
3. **Run tool**: execute buildkit in the clone (`runTool`, `runPipeline`; a `workingDirectory` outside the clone is refused)
4. **Verify**: exit code, stdout/stderr, generated/modified files
5. **Revert** (`tearDown`): `git checkout -- .` in the clone
6. **Dispose** (last step of `tearDownAll`): `await ws.dispose();` releases the clone (and resets it). It must come last — the tear-down still verifies and cleans the clone — and an `addTearDown` registered in `setUpAll` would run before `tearDownAll`. BK-ISO-5 fails for a suite that calls `isolated()` without disposing.

### Directory Layout

```
tom_build_kit/
  test/
    helpers/
      test_workspace.dart      # Clone lifecycle, fixture swap, git revert, process runner
    fixtures/
      build_project/_build/    # The `_build` target project, provisioned per test
      versioner/ exclusion/ pipeline/ compile_fail/
        buildkit_master.yaml   # Minimal master configs per suite
    workspace_isolation_test.dart     # BK-ISO: the clone and its guards
    workspace_cleanliness_test.dart   # BK-CLEAN: the clean check
    frozen_lock_guard_test.dart       # Reads the live locks (marked live-root: ok)
    *_test.dart                       # Tool integration suites
```

### Fixture Design Principles

- Each fixture `buildkit_master.yaml` targets **1–2 small projects** to keep tests fast
- Fixtures define only the **minimum config** needed for the specific test
- The `navigation:` section in fixtures uses explicit `exclude:` patterns to limit scope

### Test Helper: TestWorkspace

- **Clone lifecycle**: `TestWorkspace.isolated()` (in `setUpAll`), `dispose()` (last in `tearDownAll`); `workspaceRoot` is the clone, `liveRoot` the workspace it mirrors (read only). `TestWorkspace.forRoot(path)` exists for the helper's own tests and refuses every change.
- **Protection protocol** (on the clone):
  - `requireCleanWorkspace()` — fails if the clone has uncommitted changes (call in `setUpAll`)
  - `saveHeadRefs()` / `verifyHeadRefs()` — no commit may leak during the suite
  - `uncommittedChangesIn(root)` — read from `git status --porcelain=v2`: modified or untracked content (in the root or inside a submodule) is dirty, a submodule whose pointer merely moved is not, at any depth
- **Skip files**: `placeSkipFile(relativeDir)` / `removeSkipFile(relativeDir)` — a temporary `buildkit_skip.yaml` in the clone; `isSkippedRepo(path)` checks for one
- **Fixtures**: `installFixture(name)`, `provisionBuildProject()`, `deprovisionBuildProject()`
- **Git revert**: `revertAll()` (the clone's root), `revertFiles(paths)`, `revertSubmodule(path)`
- **Tool execution**: `runTool(name, args)`, `runPipeline(name, args)` — buildkit from the snapshot, in the clone
- **File helpers**: `readWorkspaceFile()`, `workspaceFileExists()`, `relativeProjectPath()` — relative to the clone

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
- **buildkit scanning**: Both `--exclude-projects` and skip file checks apply
- **Test git operations**: `saveHeadRefs()` and `tearDownProtocol()` skip repos with this file

### Test Isolation Rules

- Each test gets a fresh fixture installed in `setUp` or at test start
- Each test reverts its changes in `tearDown`; untracked files a test creates are its own to delete
- Tests **must not depend on execution order**
- Test files run one at a time (`dart_test.yaml` `concurrency: 1`); they share the one clone, which its lock serialises anyway

## Test Coverage

See [doc/test_coverage.md](../doc/test_coverage.md) for the complete feature coverage plan with all tools and their testable features.

## Running Tests

```bash
cd tom_ai/basics/tom_build_kit
testkit :test      # or: dart test
```

Individual test files:

```bash
dart test test/versioner_test.dart
```
