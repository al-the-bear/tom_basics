# Tom Build Kit — Testing Guidelines

## Test Strategy: Integration Tests in a Scratch Copy of the Workspace

Buildkit's integration tests exercise the real CLI tools by spawning them as child processes against the workspace's project tree, then verify outcomes through file system checks and git diffs. They do NOT run in the live workspace: each test file works in its own **scratch copy** (`test/helpers/scratch_workspace.dart`), so they can run while other sessions edit the tree, and nothing they install, generate or revert can reach it.

No preparation is needed: no commit, no push, no backup. `dart test` (or `testkit :test`) from the package root runs everything.

### The scratch copy

`TestWorkspace.isolated()` builds the copy from the live workspace's tracked tree (`git ls-files --recurse-submodules`):

- every **descriptor file** (`pubspec.yaml`, `buildkit.yaml`, `buildkit_skip.yaml`, `tom_project.yaml`, `.gitignore`, `package.json`, ... — `descriptorFileNames`) with its content;
- every file in a `bin/` folder, and one file of every other directory, created **empty** — nature detection checks descriptors, folder existence and `bin/` file names, so the copy is about 9k files instead of 73k files and 2.5 GB;
- committed as **one git repository**, so a test's `git checkout -- .` works on it; nested repositories are not reproduced (no suite uses git-mode traversal);
- a committed marker file (`scratchMarkerFileName`); every `TestWorkspace` method that changes the tree, runs git or runs buildkit refuses a root without it;
- in the **system temp directory**, outside any git repository: tom_build_base's `findTopRepo` returns the outermost repository above a path, so a copy under the workspace's `ztmp/` would resolve to the live superproject.

buildkit is compiled once per copy to a kernel snapshot (excluded from the copy's git status), instead of `dart run` recompiling it for every call.

A test that needs a real project's sources (not just its descriptors) cannot get them from the copy; give it a fixture instead (as `_build` is).

### Core Mechanism

1. **Copy** (`setUpAll`): `ws = await TestWorkspace.isolated();`
2. **Install fixture**: copy a test-specific `buildkit_master.yaml` into the copy's root, and provision the `_build` project from `test/fixtures/build_project/_build`
3. **Run tool**: execute buildkit in the copy (`runTool`, `runPipeline`; a `workingDirectory` outside the copy is refused)
4. **Verify**: exit code, stdout/stderr, generated/modified files
5. **Revert** (`tearDown`): `git checkout -- .` in the copy
6. **Dispose** (last step of `tearDownAll`): `await ws.dispose();` deletes the copy. It must come last — the tear-down still verifies and cleans the copy — and an `addTearDown` registered in `setUpAll` would run before `tearDownAll`. BK-ISO-8 fails for a suite that calls `isolated()` without disposing.

### Directory Layout

```
tom_build_kit/
  test/
    helpers/
      scratch_workspace.dart   # Builds and deletes the scratch copy
      test_workspace.dart      # Fixture swap, git revert, process runner — on the copy
    fixtures/
      build_project/_build/    # The `_build` target project, provisioned per test
      versioner/ exclusion/ pipeline/ compile_fail/
        buildkit_master.yaml   # Minimal master configs per suite
    scratch_workspace_test.dart       # BK-ISO: the copy and its guards
    workspace_cleanliness_test.dart   # BK-CLEAN: the clean check
    *_test.dart                       # Tool integration suites
```

### Fixture Design Principles

- Each fixture `buildkit_master.yaml` targets **1–2 small projects** to keep tests fast
- Fixtures define only the **minimum config** needed for the specific test
- The `navigation:` section in fixtures uses explicit `exclude:` patterns to limit scope

### Test Helper: TestWorkspace

- **Copy lifecycle**: `TestWorkspace.isolated()` (in `setUpAll`), `dispose()` (last in `tearDownAll`); `workspaceRoot` is the copy, `liveRoot` the workspace it was made from (read only). `TestWorkspace.forRoot(path)` exists for the helper's own tests and refuses every change.
- **Protection protocol** (on the copy):
  - `requireCleanWorkspace()` — fails if the copy has uncommitted changes (call in `setUpAll`)
  - `saveHeadRefs()` / `verifyHeadRefs()` — no commit may leak during the suite
  - `uncommittedChangesIn(root)` — read from `git status --porcelain=v2`: modified or untracked content (in the root or inside a submodule) is dirty, a submodule whose pointer merely moved is not
- **Skip files**: `placeSkipFile(relativeDir)` / `removeSkipFile(relativeDir)` — a temporary `buildkit_skip.yaml` in the copy; `isSkippedRepo(path)` checks for one
- **Fixtures**: `installFixture(name)`, `provisionBuildProject()`, `deprovisionBuildProject()`
- **Git revert**: `revertAll()` (the copy's root), `revertFiles(paths)`, `revertSubmodule(path)`
- **Tool execution**: `runTool(name, args)`, `runPipeline(name, args)` — buildkit from the snapshot, in the copy
- **File helpers**: `readWorkspaceFile()`, `workspaceFileExists()`, `relativeProjectPath()` — relative to the copy

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
- Test files run one at a time (`dart_test.yaml` `concurrency: 1`). Each has its own copy, so they no longer share workspace files; running them in parallel has not been verified (they still share `.test-log/` and `$HOME`-level state)

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
