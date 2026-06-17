## 1.8.0

### Features

- **`:execute` command** — Run shell commands in each traversed folder with placeholder substitution.
  - Aliases: `exec`, `x`
  - Path placeholders: `${root}`, `${folder}`, `${folder.name}`, `${folder.relative}`
  - Nature existence checks: `${dart.exists}`, `${flutter.exists}`, `${git.exists}`
  - Nature attributes: `${dart.name}`, `${dart.version}`, `${git.branch}`, `${git.dirty}`
  - Ternary expressions: `${condition?(true-value):(false-value)}`
  - Condition filtering: `--condition dart.exists`

- **`--executable` / `-e` option for `:compiler`** — Filter compilation to specific executable files.
  - Comma-separated file list: `--executable buildkit.dart,compiler.dart`
  - Matches by basename or path suffix
  - Works in both buildkit `:compiler` command and standalone `compiler` tool

- **`--project` ID and name matching** — The `--project` option now matches against project IDs and names from `buildkit.yaml` and `tom_project.yaml`, not just folder names and globs.
  - Matches `short-id`/`project_id` from `tom_project.yaml`
  - Matches `id` and `name` from `buildkit.yaml`
  - Case-insensitive matching

- **Command prefix matching** — Command names can be abbreviated to their shortest unambiguous prefix.
  - `:vers` matches `:versioner`, `:comp` matches `:compiler`
  - Exact matches always take priority over prefix matches
  - Ambiguous prefixes report all matching commands

- **Macro placeholders** — Macros now support argument placeholders `$1`–`$9` and `$$` (all arguments).

### Bug Fixes

- **`--project` filter applied before nature detection** — Fixed regression where `--project` with ID/name values always returned empty results because folder natures were not yet detected at filter time.

### Dependencies

- Requires tom_build_base v1.11.0 or later.

---

## 1.7.0

### Refactoring

- **WorkspaceScanner integration** — Refactored all 17 git tools to use unified `WorkspaceScanner` API.
  - Replaced duplicated `_findGitRepositories()` methods with `WorkspaceScanner().findGitRepoPaths()`.
  - Removed ~30 lines of duplicated code from each tool.
  - `bumppubspec` now uses `WorkspaceScanner().findPublishable()` for package discovery.

### Dependencies

- Requires tom_build_base v1.11.0 or later for WorkspaceScanner API.

---

## 1.6.0

### Features

- **`:status` command** — New internal command showing buildkit version, binary status, and git state.
  - Source version display (version, build number, git commit, build time, Dart SDK)
  - Binary currency check for all 25 buildkit tools (runs `<tool> --version`)
  - Categorizes tools as current, outdated, unavailable, or non-conformant
  - Git status with pending changes and unpushed commits
  - Supports `--json` for structured output
  - Supports `--verbose` to show individual file/commit details
  - Supports `--skip-binaries` and `--skip-git` flags
  - Uses standard navigation options for git repo traversal

## 1.5.0

### Bug Fixes

- **`pubgetall` / `pubupdateall` showing 0 projects** — These commands now correctly run once at workspace level with their own project discovery instead of being invoked per-project.
- **Progress line not clearing** — Fixed progress display in `pubget` and `pubupdate` commands by padding output to 120 chars and flushing stdout immediately.
- **Build order path normalization** — Fixed `computeBuildOrder()` filtering out all projects due to non-normalized paths.

### Features

- **`ownDiscoveryCommands`** — New pattern in `buildkit.dart` for commands that do their own project discovery (e.g., `pubgetall`, `pubupdateall`).
- **`--no-recursive` support** — Respects the new negatable `--recursive` flag from tom_build_base v1.6.0.

## 1.4.0

### Features

- **`--modules` / `-m` navigation option** — Filter projects/repositories to specific git modules. Comma-separated list of module names (e.g., `--modules tom_module_d4rt,tom_module_basics`). Use "root" or "tom" for main repository.
- All 17 git tools now support modules filtering (`gitstatus`, `gitcommit`, `gitpull`, `gitsync`, `gitbranch`, `gittag`, `gitcheckout`, `gitreset`, `gitclean`, `gitprune`, `gitstash`, `gitunstash`, `git`, `gitcompare`, `gitmerge`, `gitsquash`, `gitrebase`).
- `ToolBase.findProjects()` now accepts `modules` parameter for include filtering.
- `buildkit` CLI supports `--modules` / `-m` option.

## 1.0.0

- Initial version.
