## 1.27.0

### Added — `:bumpversion --changelog` drafts the CHANGELOG entry

With `--changelog`, each bumped project gets a draft `## <new version>`
section at the top of its CHANGELOG.md (created when missing): the subjects
of the commits that touched the project folder since its version last
changed (the newest commit whose version file states another version than
its parent's, or adds it), newest first, without merges, plus a line when
the folder has uncommitted changes; a comment names where it was drawn from.
A section of the new version that exists is kept and nothing is added.
`--dry-run` prints the draft. BK-CLOG-1..6; user guide, bumpversion.

## 1.26.0

### Added — `:docsite`, the API docs of the selected packages in one site

`buildkit -s tom_ai/basics :apidoc :docsite` copies each selected
package's dartdoc output (`build/api_doc`, `--api-doc`) into one gitignored
folder (`build/doc_site` under the workspace root, `--output`), renders its
README beside it, and writes an index page: every package with API docs,
sorted, with version and description from its pubspec and links to its API
docs and README; packages without API docs are named below. Built once the
traversal is over (tom_build_base's `afterTraversal`), replacing the folder
whole. Served locally (`dart pub global run dhttpd --path build/doc_site`).
New dependency: `markdown` (README rendering). BK-DOCSITE-1..5; user
guide, Docsite Command.

### Changed — the output-folder rule names its base

`refuseGeneratedOutput` says "inside the workspace root" for a folder
relative to it (`:docsite`), "inside the package" for the others.

## 1.25.0

### Added — `:doccheck`, the documents each package lacks

`buildkit -s tom_ai/basics :doccheck` reports per package what the workspace
guidelines ask for and is missing: README.md, its attribution blockquote,
its required sections (default Features, Installation, Quick start,
Documentation — the ones component_module_readme_example.md and
documentation_guidelines.md share), CHANGELOG.md, an example, user docs in
doc/, and an index in a `_copilot_guidelines/` folder. `--strict` exits 1 on
a gap. The checks and sections come from `doccheck:` in buildkit_master.yaml;
a package opts out in its buildkit.yaml, always with a reason (`skip:`,
`exclude: {check: reason}`, its own `readme-sections:`); an opt-out without a
reason or with an unknown check is a configuration error. BK-DOCCHK-1..8;
user guide, Doccheck Command.

## 1.24.1

### Fixed — a hung md2pdf no longer stops `:apireference` for good

tom_md2pdf can hang on a document it cannot lay out (tom_core_kernel's
logging and reflection summaries). `:apireference` stops md2pdf after
`--timeout` seconds (default 600) and fails the package with a message;
the other packages go on. BK-APIREF-9.

## 1.24.0

### Added — `:apireference`, a package's combined API reference PDF

`buildkit -p <package> :apireference` collects the package's summary index,
module summaries (alphabetically) and module guides
(`doc/<module>.md` or `doc/<module>/<module>.md`), assembles them in the order
`api_reference_creation.md` gives — Part I index, Part II module references,
Part III guides, headings nested, link columns removed, links as text — and
renders the PDF with tom_md2pdf (`md2pdf` from the binaries layer, or
`--md2pdf`), both into the gitignored `build/api_reference/`; never `doc/`.
Missing inputs (no index, no module summary, a summary the index links to)
are named and fail the package; modules without a guide are listed; a
package without `doc/api/` is NOT DOCUMENTED and skipped. BK-APIREF-1..8;
user guide, Apireference Command.

### Changed — one rule for generated output folders

`:apidoc` and `:apireference` share `refuseGeneratedOutput` (inside the
package, never in `doc/`) and the note when git would track the output.

## 1.23.0

### Added — `:apisummary`, where an API summary is out of date

`buildkit -p <package> :apisummary` reads the package's public API with the
analyzer's parser (what the `lib/*.dart` entry points export, `show` / `hide`
applied, top-level constants included — tom_build_base 2.32.0) and compares it
with its hand-authored `doc/api/api_summary_*.md` in both directions: public
API no summary names (a member is looked for in its type's section, a
supertype's, or the extended type's), and names a summary presents as API —
a `### Name` heading, a member-table cell, a `Type.member` code span — that
the package no longer declares. It writes nothing. `--strict` exits 1 on a
finding; a package without a summary is NOT MEASURED and skipped.
BK-APISUM-1..8; user guide, Apisummary Command; api_summary_creation.md.

### Changed — `:apidoc` writes into `build/api_doc`

The default output is now `build/api_doc`, the workspace's place for
generated API reference (`_bin/check_doc_runner_output.py`), instead of
`build/api`.

### Changed — the exported-symbol listing is shared

`exportedSymbolsOf` / `exportedTopLevelOf` (lib/src/unreferenced) list a
package's public API for both the unreferenced-export audit and
`:apisummary`; the audit's findings are unchanged.

## 1.22.0

### Added — `:apidoc`, dartdoc API documentation per package

`buildkit -s tom_ai/basics :apidoc` runs `dart doc` in every Dart package of
the traversal and writes into `build/api` (`--output <dir>`, relative to the
package; never inside `doc/`, which holds hand-authored documents only). Per
package it prints dartdoc's warning and error lines and one result line:
libraries, warnings (unresolved doc references counted apart), and how many
public elements of `index.json` have no doc comment. A non-zero exit, dartdoc
errors or no public library fail the package; an unresolved package
(`.dart_tool/package_config.json` missing) is refused before dartdoc runs; a
package without a `lib/` library is skipped. Usable as a pipeline step
(`buildkit :apidoc`). BK-APIDOC-1..9; user guide, Apidoc Command.

### Fixed — the user guide's pipeline examples

The examples wrote pipeline steps as bare command names (`- versioner`) and a
`dcli` step, which the pipeline loader refuses; they now read
`buildkit :versioner` and `shell dcli ...`, and the text names the step kinds.

## 1.21.0

### Fixed — `--list` runs nothing (tom_build_base 2.29.0)

`buildkit --list :pubgetall` ran `pub get` in every project. On tom_build_base
2.29.0, `--list` runs nothing: alone it lists the commands and pipelines, with
a command the projects it would run on, with a pipeline its steps. The nine
executors that already had a read-only list mode keep it and declare it
(`handlesListMode`): versioner, compiler, cleanup, runner, dependencies,
unreferenced, bumpversion, bumppubspec and the build / test / clean actions;
every other command is named per project and not run. The `--list` help text
and the user guide say so.

## 1.20.0

### Changed — `-X-` is refused (tom_build_base 2.28.0)

The user guide described `-X-` (`-s-`, `-v-`, `-n-`) as taking an option away
from one command of a multi-command run. That never existed: the commands of a
run share one traversal, and `buildkit :versioner -s-` read `-s-` as
`--scan -`. On tom_build_base 2.28.0, `-X-` and `--name-` are refused with an
error before anything runs. The guide's "Options in Multi-Command Runs" section
says what holds: the options of a run apply to all of its commands, wherever
they stand, also after a pipeline name. BKT_OPT01 tests the refusal; BKT_DRY01
(an option after a pipeline name, bug #15) runs again instead of being
skipped.

## 1.19.0

### Added — `:projects`: the projects buildkit works on

- `buildkit :projects` lists every project a project command would visit
  (the same traversal, `buildkit_master.yaml` navigation defaults, `-p`, `-r`,
  `--exclude-projects`, `--group`) with id, name, path and natures;
  `--json` prints one JSON document (`formatVersion` 1) for callers outside
  Dart. The VS Code extension lists projects with it instead of the retired
  generated workspace manifest (tom_build_base ^2.27.0, `listProjectsFor`).
  `--all` lists every project of the tree, past the `navigation:` excludes.
  Alias `proj`. BK-PRJ-1..5.
- The primary nature of `:build` / `:test` / `:clean` is tom_build_base's
  `primaryProjectNature` (the same order as before).

## 1.18.0

### Changed — dcli is `tom_dcli`

`tom_dcli` ^10.4.7+tom.1 in place of `dcli`: the Tom Framework's fork of dcli
10.4.7, which reads INI files with its own `IniConfig` instead of the LGPL-3.0
`ini` package that the `buildkit` binary compiled in.

## 1.17.0

### Changed — the build number lives in `version.versioner.dart`

- `:versioner` reads the build number from the project's existing versioner
  file and writes it plus one (1 when there is none). It no longer reads or
  writes `tom_build_state.json`, which is retired. A versioner file without a
  `buildNumber` is an error that names the file. VBN-1..5.
- `:bumpversion` no longer resets the build number: it only grows, so the
  fleet's merge driver can tell the newer build by it alone.

## 1.16.0

### Added — `:build`, `:test`, `:clean` for every SOM runtime language

- New commands run one step in every selected project with its language's
  own tool, by its nature (tom_build_base ^2.26.1): Dart / Flutter, TypeScript,
  JavaScript, Python, Java (Maven, Gradle), Go, Rust, C / C++ (make, CMake). A
  `build:` / `test:` / `clean:` entry in the project's `buildkit.yaml` replaces
  the default (a command, a list, or `false`); `--list` / `--dry-run` show the
  command. Proven on the 18 SOM runtime packages (build, test, clean all
  green). BK-ACT-1..7.
- `:bumpversion` bumps the version file of every language project
  (`package.json`, `pyproject.toml`, `Cargo.toml`, `pom.xml` besides
  `pubspec.yaml`); Go and C / C++ have none and are skipped.
- `:clean` is no longer an alias of `:cleanup` (which keeps `cl`).

## 1.15.1

### Changed — the project identity comes from `buildkit.yaml`

buildkit takes tom_build_base ^2.25.0. `--project <id or name>` and
`findproject` match the `project_id` and `name` at the top of the project's
`buildkit.yaml` (the resolver read a `project-id` key no file used);
`tom_project.yaml` is not read any more. BK-RES-1..4.

## 1.15.0

### Added — `--group`

buildkit takes tom_build_base ^2.24.0: `--group <name>` selects the projects of
a group, where every git repository and every `buildkit_group.yaml` directory is
a group (user guide, "Group Selection"). The hand-kept group lists of
`tom_workspace.yaml` are not read.

## 1.14.1

### Changed — the workspace root is the nearest `buildkit_master.yaml`

buildkit takes tom_build_base ^2.23.0, where `buildkit_master.yaml` is the one
workspace marker (`tom.code-workspace` no longer counts). Each lookup
(`pubgetall`, the compiler's placeholders, project search, runner, versioner)
uses `findWorkspaceRootOrNull` and falls back to its start directory outside a
workspace, as before. The `build_project` fixture's tool finds the workspace
the same way.

## 1.14.0

### Added — `:boundaries`, the context-boundary check

Runs tom_build_base's `checkContextBoundaries` (2.21.0) over the traversal: the
bounded contexts of a package, read from the `boundaries:` section of its
`buildkit.yaml`, against its imports and exports. A violation or a rotted rule
fails the project (exit 1) and names file, line and imported library; a package
without the section is NOT MEASURED, which fails when the package was asked
for by name or the command runs inside it, and is skipped by name in a wider
traversal. `--json` prints one report per project per line, written past the
console-markdown layer so the JSON stays intact; `--tests` adds `test/`.
Documented in `doc/buildkit_user_guide.md`; tests BK-BND-1..6.
`tom_build_base: ^2.21.0`.

## 1.13.4

### Changed — `:compiler` names every listed target it does not build

A compile section's `targets:` lists what it may build; a plain run builds the
current platform only (each platform is built on its own host), and
`--all-platforms` / `--targets` build more. The listed targets a run did not
build used to vanish from the trace, so `targets: [darwin-arm64, linux-x64,
linux-arm64, linux-armhf]` looked like a fan-out that never happened. With
`-v` each is now named with the reason (`Not building linux-x64: current
platform only; --all-platforms or --targets builds it`). A selected target the
host cannot build (`dart compile exe` cross-compiles to Linux only, so Windows
or macOS from another platform) is skipped by name, verbose or not, instead of
running a compile that fails. `CompilerExecutor.planTargets`,
`PlatformUtils.canBuildOn`; tests CMP_PLAN01..07.

## 1.13.3

### Fixed — `:buildsorter --include-dev` was ignored

tom_build_base 2.19.0 added `--include-dev` as a traversal option, which took
the flag before `:buildsorter`'s own option of the same name could, so
`:buildsorter --include-dev` sorted without dev dependencies. The command now
reads the traversal setting (`--exclude-dev` still wins) and no longer defines
its own option. Tests BK-SORT-1/2. `tom_build_base: ^2.19.1`.

## 1.13.2

### Changed — build order without dev dependencies (tom_build_base 2.19.0)

`tom_build_base: ^2.19.0`. buildkit's build order ignores `dev_dependencies`
by default (`--include-dev` opts in), so the two dev-only cycles in the
workspace (tom_reflection / tom_reflection_generator, tom_ast_generator /
tom_d4rt_exec) no longer make every run fall back to scan order. A remaining
cycle is reported with its members and edges only.

## 1.13.1

### Changed — `dcli` ^10.4.7

`dcli: ^10.4.7` (from ^10.0.0), the version this package is tested on. 1.13.0
had to admit 10.0.0 because `tom_d4rt_dcli` pinned `pubspec_manager ^3.2.1`,
which only dcli 10.0.0 accepts; `tom_d4rt_dcli` 1.14.0 and `tom_dcli_exec`
1.15.0 are on dcli ^10.4.7 / `pubspec_manager` ^4.1.0, so a package taking
both now resolves dcli 10.4.7.

### Tests run on the workspace clone

The integration suites run on the machine's workspace clone (tom_test_support
0.6.0 `TomWorkspaceClone`, a full clone with every submodule beside the
workspace) instead of a skeleton copy of descriptor files. The clone is
created on first use, brought to the live repositories' commits before a run
and reset after it. Test-only: the library is unchanged by it. See
`_copilot_guidelines/testing.md`.

## 1.13.0

### Changed — `dcli` ^10

`dcli: ^10.0.0` (from ^8.4.2). Every `tom_d4rt_dcli` from 1.5.0 on is on
dcli ^10, so a package taking both (tom_build_cli, the `tom` binary) did not
resolve against any earlier tom_build_kit. The floor is 10.0.0 because
`tom_d4rt_dcli` still pins `pubspec_manager ^3.2.1`, which only dcli 10.0.0
accepts; on its own tom_build_kit resolves the current 10.4.x. Tested on both.

### Changed — `--project` ids come from `project_id` only

Requires `tom_build_base` 2.18.0. A bare `--project` name matches a project's
folder, its `tom_project.yaml` `project_id`, or its name; the `short-id`
fallback is gone, as in tom_build_base 2.18.0.

### Fixed — a workspace reached through a symbolic link selects its projects

An absolute `--project` path in a workspace reached through a link (on macOS
everything under `/var` is `/private/var`) was rejected as outside the
workspace, and then selected no project (tom_build_base 2.17.1 / 2.17.2).

### Tests run in a scratch copy of the workspace

The integration suites no longer touch the live workspace: each test file
works in its own copy (`test/helpers/scratch_workspace.dart`), so they run
while other sessions edit the tree. See `_copilot_guidelines/testing.md`.

## 1.12.0

### Added — `:unreferenced`, the unreferenced-export audit

Every public symbol a set of packages exports from `lib/` that no other `lib/`
or `bin/` file names, configured by the `unreferenced:` section of a project's
`buildkit.yaml` (root, package prefix, exclusions, consumer repositories, and
an allowlist whose every entry carries a reason). A `@visibleForTesting` seam
passes while a test names it; a stale allowlist entry, a malformed section or
an audit that checked nothing fails the project. The engine is also a library,
`package:tom_build_kit/unreferenced_exports.dart`. It came from Webwork's
`tool/unreferenced_exports.dart`, whose allowlist is now its configuration.
Requires `tom_build_base` 2.17.0 (the seam engine's declaration scanner) and
adds `analyzer`.

## 1.11.0

### Fixed — `:versioner` reports what it did, not what it intended

The installed buildkit binary printed

    Version file generated: tom_d4rt_generator v1.37.0 build 20
    Status: SUCCESS

over a `version.versioner.dart` that still read `0.0.1-STALE`. It advanced
`tom_build_state.json` and wrote nothing else. The consequence is worse than a
stale tool: `version_stamp_test.dart` fails with the remedy "run
`buildkit -v -p . :versioner`", pointing the reader at the command that
silently does nothing — so following the instruction loops.

That message exists nowhere in current source; the binary was seven months old
and ran a code path since removed, so the repair is a rebuild. The audit that
went with it found the same CLASS of defect still live in two places, and both
are fixed here:

- A **dry run** returned success with the message `version file generated`,
  having written nothing. It now reports `dry run — no version file written`.
- A real run reported success on the strength of the write not throwing. It now
  **reads the file back** and fails if the stamp on disk does not carry the
  version just generated — so "generated" means the file says so, not that a
  write was attempted. This covers the quieter half a thrown exception does
  not: output landing somewhere other than where the caller will look, or being
  undone by the in-place formatter that runs after it.

## 1.10.0

### Added — `:compiler` and `:runner` name a missing cached package

A locked package the pub cache cannot supply is not a resolution error: the
lock is satisfiable, so `dart pub get` reports success. The failure lands later
and wearing someone else's face — from the AOT compiler as
`Bad state: Generating AOT kernel dill failed!`, which names nothing at all,
and from build_runner as `Undefined name` at every use site, which reads as an
upstream rename.

Both executors now call `pubCachePreflight` (tom_build_base 2.14.0) and stop
with a report naming the package, its expected location and the repair.

Placement is deliberate in both:

- `:compiler` checks after its early returns, so a listing, a config dump, a
  configured `skip-compile-with-buildkit` or a project with no compile sections
  pays nothing. A dry run compiles nothing and is skipped too.
- `:runner` checks after its dry-run return, which shells out to nothing.

Requires tom_build_base >= 2.14.0.

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
