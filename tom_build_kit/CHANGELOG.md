## 1.9.0

### Changed — twelve private copies of the option lookup replaced by one

Eight executors carried their own "per-command options for this command, else
global" helper (bumpversion, compiler, publisher, runner, cleanup, versioner,
dependencies, buildsorter). A sweep found four more places doing it by hand,
and two of those had the MIRROR-IMAGE defect: `bumppubspec` and `status` read
`commandArgs` ONLY, so an option written BEFORE the command was dropped.
`execute` rolled its own per-command-then-global and did not know its command's
aliases, so `buildkit :x --condition=...` was lost. `git_executors` held a
ninth copy.

All now call `CliArgs.optionsFor` (tom_build_base 2.13.0), which also MERGES
the two positions rather than choosing between them — the copies returned the
per-command map whole, so an option given globally was hidden whenever any
per-command option was present.

Requires tom_build_base >=2.13.0.

## 1.8.0

### Fixed — `:bumpversion --minor=<x>` no longer does a silent PATCH bump when the selector matches nothing (sce10)

A selector matched the traversal's project name and a path SUFFIX, and nothing
else. So `--minor=tom_d4rt_generator` — the package's own pubspec name, and the
obvious thing to type — selected nothing, the project took the default patch
bump, and nothing said so.

That is the one shape a release checklist cannot catch by eye, because nothing
disagrees: the pubspec says a version, `--versioner` stamps the same version
from it, the CHANGELOG section is written beside them. The release is
internally consistent and numbered wrong.

Two changes:

* a selector may now name a project's pubspec `name:`, as well as its
  traversal name or a suffix of its path (`.` being the project you are
  standing in);
* a selector that named NO project is printed and exits non-zero, listing the
  projects that were processed so the correction does not cost a second run to
  find the right name.

A name must match whole. `tom_d4rt` and `tom_d4rt_generator` are different
packages, and a prefix rule would bump the wrong one.

### Features

- **Guided-mode is now testable** — `GuidedMode` renders its menus,
  confirmations and text prompts through an injectable `PromptDriver` instead
  of calling `dcli` directly. `DcliPromptDriver` performs real terminal I/O by
  default; `ScriptedPromptDriver` replays a fixed list of answers so guided-flow
  logic can be unit-tested without a live TTY (`BK-GUIDE-*`). Existing callers
  are unaffected (`GuidedMode()` still defaults to the real terminal driver).

- **`ProjectGroupPicker` / `pickProjectScopes` are now testable** — the project
  scope picker used by git guided flows renders through the same injectable
  `PromptDriver` instead of calling `dcli` directly, so its scope-choice,
  multi-select and cancellation logic is covered by unit tests (`BK-PGP-*`).
  `ProjectGroupPicker({PromptDriver? driver})` and `pickProjectScopes({...,
  PromptDriver? driver})` default to the real terminal driver; existing callers
  are unaffected.

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
