# Tom Build Kit

> Tom Build Kit is part of the **Tom framework** by al-the-bear.
> Distributed under the terms in this package's license — see [LICENSE](LICENSE).

Build orchestration tool with pipelines that integrates Tom build tools.

`tom_build_kit` is the package behind the **`buildkit`** command — the
pipeline-based orchestrator for the whole Tom workspace. From a single
invocation it runs named build **pipelines**, invokes individual build
**commands** (`:versioner`, `:compiler`, `:runner`, `:pubget`, …), drives
**git** across every repository in the workspace, and scans many projects in
dependency order. Every command is a native v2 `CommandExecutor` dispatched by
the shared `ToolRunner` from [`tom_build_base`](../../basics/tom_build_base/),
so buildkit gets argument parsing, workspace traversal, pipeline execution and
end-of-run summaries for free.

A second, smaller binary — **`findproject`** — resolves a project by name, ID or
folder and prints its path, so a shell wrapper can `cd` to it.

---

## Overview

A Tom workspace is a tree of many Dart/Flutter packages spread across nested git
repositories. Building, versioning, compiling, fetching dependencies and
managing git across all of them by hand does not scale. `buildkit` makes the
whole workspace addressable from one command in two complementary ways:

- **Pipelines** — named sequences of steps defined in `buildkit_master.yaml`
  (e.g. a `build` pipeline that runs `:versioner`, then `:runner`, then
  `:compiler`). Run `buildkit build` and the steps execute in order, across the
  selected projects, in dependency order.
- **Direct commands** — invoke a single build tool with `:command` syntax
  (`buildkit :compiler`), optionally across a project selection.

Both share the same engine. buildkit is a **v2 tool**: it declares a
`ToolDefinition` (`buildkitTool`) listing every command, and a matching map of
`CommandExecutor`s (`createBuildkitExecutors()`). The `bin/buildkit.dart`
entry point hands both to a `ToolRunner` from `tom_build_base`, which parses the
arguments, resolves the project/git traversal, runs the chosen executor against
each matched folder, and renders a consistent errors/skips summary. buildkit
itself contributes the *commands*; the *framework* — parsing, traversal,
pipelines, option precedence, multi-workspace navigation — lives in
`tom_build_base`.

### How a command flows

```
buildkit :pubget --project='tom_*'
        │
        ▼
  ToolRunner (tom_build_base)
   • parse args against buildkitTool (ToolDefinition)
   • resolve project selection + traversal order
   • for each matched DartProjectFolder:
        └─► PubGetExecutor.execute(...)  →  dart/flutter pub get
   • aggregate ToolResult, render run summary
```

---

## Installation

`tom_build_kit` is a **workspace-internal package** (`publish_to: none`). It is
not published to pub.dev — it lives inside the Tom devops repository and is
consumed in place. There is no `dart pub add tom_build_kit`, and you should
**never** add a manual `path:` override to reach it.

It depends on the **hosted** `tom_build_base: ^2.6.25` from pub.dev (the shared
CLI / build framework), plus `args`, `dcli`, `glob`, `yaml`, `yaml_edit` and
`console_markdown`.

The package declares two executables:

```yaml
executables:
  buildkit:
  findproject:
```

In day-to-day use the binaries are activated/compiled and put on `PATH`:

```bash
# From tom_ai/basics/tom_build_kit
dart pub get
dart run bin/buildkit.dart --help     # or, once on PATH: buildkit --help
```

A short alias and a `cd`-helper are conventional:

```bash
alias bk=buildkit

# Jump to a project by name / ID / folder using findproject
goto() {
  local d; d="$(findproject "$@" 2>/dev/null)"
  if [[ -n "$d" && -d "$d" ]]; then cd "$d"; else findproject "$@"; return 1; fi
}
```

**SDK requirement:** Dart `^3.10.4`.

---

## Features

| Feature | Description |
| ------- | ----------- |
| Pipeline execution | Define and run named build pipelines from `buildkit_master.yaml` (base-owned). |
| Direct commands | Run build tools directly with `:command` syntax. |
| Sequential execution | Mix pipelines and commands in a single invocation. |
| Project scanning | Run pipelines/commands across many projects in dependency order. |
| Platform filtering | Run steps only on specific platforms. |
| Git orchestration | Drive git across every repository in the workspace with one command. |
| Dependency management | `dart/flutter pub get` / `upgrade` across the selected projects. |
| Dry-run mode | Preview what would be executed without running it. |
| Guided mode | Interactive `-g` / `--guide` flow for git and standalone tools. |

---

## Quick start

```bash
# Run a pipeline
buildkit build

# Run multiple pipelines in sequence
buildkit clean build

# Run tool commands directly
buildkit :versioner :compiler

# Mix pipelines and commands
buildkit build :cleanup --all

# Scan all projects under the current directory
buildkit build --scan . --recursive
```

```text
▶ build › versioner   (12 projects)   ok
▶ build › runner      (3 projects)     ok
▶ build › compiler    (5 projects)     ok
Run summary: 20 ok · 0 skipped · 0 errors
```

---

## Example projects

| Where | Demonstrates |
| ----- | ------------ |
| [`bin/buildkit.dart`](bin/buildkit.dart) | The v2 entry point: `ToolRunner(tool: buildkitTool, executors: createBuildkitExecutors())`. |
| [`bin/findproject.dart`](bin/findproject.dart) | A standalone project-resolver tool wrapped by a shell `goto()` function. |
| [`test/`](test/) | 182 tests covering executors, pipelines, project scanning and git commands — each is a runnable usage example. |
| [`tom_build_kit_sample`](../tom_devops_samples/tom_build_kit_sample/) | Authoring a small build tool / pipeline with buildkit against a fixture workspace *(planned — forward reference until the samples build-out lands)*. |

---

## Usage

```
buildkit [options] <pipeline|:command> [args...] [<pipeline|:command> [args...]]...

Options:
  -h, --help         Show help
  -v, --verbose      Verbose output
  -n, --dry-run      Show what would be executed
  -l, --list         List available pipelines
  -s, --scan         Scan directory for projects
  -R, --recursive    Scan recursively into projects
  -p, --project      Project(s) to process (comma-separated, globs: tom_*_builder, ./*)
```

### Built-in commands

| Command | Description |
| ------- | ----------- |
| `:versioner` | Generate `version.versioner.dart` from `pubspec.yaml`. |
| `:compiler` | Compile Dart to native executables. |
| `:runner` | Run `build_runner` for code generation. |
| `:cleanup` | Clean build artifacts. |
| `:dependencies` | Report/resolve inter-project dependencies. |
| `:publisher` | Publish packages. |
| `:status` | Show tool/repo status across the workspace. |
| `:buildsorter` | Compute the dependency build order. |
| `:execute` | Execute a shell command in each traversed folder. |

### Dependency commands

`:pubget` and `:pubupdate` run the SDK's dependency commands per matched Dart
project (recursive by default). They pick `dart` vs `flutter` automatically
based on the project's nature:

```bash
# Fetch dependencies across all matched Dart/Flutter projects
buildkit :pubget                  # alias: :pg

# Limit to a project selection
buildkit :pubget --project='tom_*'

# Upgrade dependencies to the latest allowed versions
buildkit :pubupdate               # alias: :pu
```

| Command | Aliases | Runs |
| ------- | ------- | ---- |
| `:pubget` | `:pg` | `dart pub get` / `flutter pub get` per project (recursive). |
| `:pubgetall` | `:pga` | Deprecated alias for `:pubget`. |
| `:pubupdate` | `:pu` | `dart pub upgrade` / `flutter pub upgrade` per project. |
| `:pubupdateall` | `:pua` | Deprecated alias for `:pubupdate`. |

These commands declare `worksWithNatures: {DartProjectFolder}`, so the
`ToolRunner` only invokes them on folders detected as Dart/Flutter projects and
skips everything else.

### Execute command

Run a shell command in every traversed folder, with placeholder substitution:

```bash
# Echo folder name in each git repo
buildkit -i :execute "echo ${folder.name}"

# Run dart pub get only in dart projects
buildkit -i :execute --condition dart.exists "dart pub get"

# Conditional output based on project type
buildkit -i :execute "echo ${dart.publishable?(Publishable):(Not publishable)}"

# Git status in all repos
buildkit -i :execute --condition git.exists "git status"
```

**Available placeholders:**

- Path: `${root}`, `${folder}`, `${folder.name}`, `${folder.relative}`
- Platform: `${current-os}`, `${current-arch}`, `${current-platform}`
- Nature existence: `${dart.exists}`, `${flutter.exists}`, `${git.exists}`
- Dart: `${dart.name}`, `${dart.version}`, `${dart.publishable}`
- Git: `${git.branch}`, `${git.remote}`, `${git.dirty}`

**Ternary syntax:** `${condition?(true-value):(false-value)}`

### Git commands

Manage git repositories across the entire workspace with a single command. Each
command has a defined traversal order (inner-first or outer-first) so operations
are safe across nested repositories:

| Command | Description | Traversal |
| ------- | ----------- | --------- |
| `:gitstatus` | Show status of all repositories | inner-first (default) |
| `:gitcommit` | Commit and push all repos with same message | inner-first (fixed) |
| `:gitpull` | Pull latest from all repositories | outer-first (fixed) |
| `:gitsync` | Full sync: stash, fetch, merge, push | outer-first (fixed) |
| `:gitbranch` | Manage branches across repos | inner-first (fixed) |
| `:gittag` | Manage tags across repos | inner-first (fixed) |
| `:gitcheckout` | Checkout branch/tag/commit | outer-first (fixed) |
| `:gitreset` | Reset repos to specific state | outer-first (fixed) |
| `:gitclean` | Remove untracked files | inner-first (fixed) |
| `:gitprune` | Remove stale remote-tracking branches | outer-first (fixed) |
| `:gitstash` | Stash uncommitted changes | inner-first (fixed) |
| `:gitunstash` | Restore stashed changes | outer-first (fixed) |
| `:gitcompare` | Compare current branch with another | inner-first (fixed) |
| `:gitmerge` | Merge branch into current branch | inner-first (fixed) |
| `:gitsquash` | Squash merge branch into current | inner-first (fixed) |
| `:gitrebase` | Rebase current branch onto another | inner-first (fixed) |
| `:git` | Run arbitrary git commands | requires `-i`/`-o` |

```bash
# Check status of all repos
bk :gitstatus

# Commit all repos with same message
bk :gitcommit -m "Add feature X"

# Full sync (stash, pull, push)
bk :gitsync

# Create branch in all repos
bk :gitbranch -c feature/new

# Run arbitrary git command
bk :git -i -- log --oneline -5
```

### Project selection

Specify projects with `--project` using comma-separated values and glob
patterns:

```bash
# Single project
buildkit build --project=my_app

# Multiple projects (comma-separated)
buildkit build --project='project1,project2'

# Glob patterns
buildkit build --project='tom_*_builder'

# Current directory children
buildkit build --project='./*'
```

### Pipeline configuration

Define pipelines in `buildkit_master.yaml` (workspace root):

```yaml
buildkit:
  pipelines:
    build:
      core:
        - commands:
            - buildkit :versioner
            - buildkit :runner
            - buildkit :compiler
```

Pipeline command prefixes: `buildkit` (delegate to a tool command), `shell`
(run in the workspace root), `shell-scan` (run once per project). Pipeline
execution, option precedence and multi-workspace traversal are handled by
`tom_build_base`.

---

## Architecture

buildkit is a thin command catalogue over the `tom_build_base` v2 framework. It
declares **what** the commands are (`buildkitTool`) and **how** each one runs
(the executor map); the framework decides **where** they run (traversal) and
**when** (pipeline order).

```
                bin/buildkit.dart
                       │ builds
                       ▼
        ToolRunner(tool: buildkitTool,
                   executors: createBuildkitExecutors())
                       │  (ToolRunner, traversal, pipelines
                       │   all from tom_build_base v2)
        ┌──────────────┼───────────────────────────────┐
        ▼              ▼                                ▼
  buildkitTool    project / git                  CommandExecutor map
  (ToolDefinition  traversal                     name → executor
   = list of       (filter pipeline,             ┌───────────────────┐
   CommandDefs)    build order)                  │ versioner → Versioner│
        │                                        │ compiler  → Compiler │
        │ each CommandDefinition names           │ pubget    → PubGet   │
        │ its options, natures, traversal        │ gitstatus → GitStatus│
        └───────────────────────────────────────┤ …                  │
                                                 └───────────────────┘
```

### Key types (the v2 model)

| Type | Origin | Responsibility |
| ---- | ------ | -------------- |
| `ToolRunner` | `tom_build_base` | Parses args, resolves traversal, dispatches to executors, aggregates the `ToolResult`. |
| `ToolDefinition` | `tom_build_base` | The tool's full command catalogue; buildkit's instance is `buildkitTool`. |
| `CommandDefinition` | `tom_build_base` | One command's metadata: `name`, `aliases`, `options`, `worksWithNatures`, traversal flags, `examples`. |
| `OptionDefinition` | `tom_build_base` | A flag/option on a command (e.g. `versionerOptions`). |
| `CommandExecutor` | `tom_build_base` | Base class every buildkit command extends; `execute(...)` does the work for one folder. |
| `buildkitTool` | `tom_build_kit` | The `ToolDefinition` listing every buildkit command. |
| `createBuildkitExecutors()` | `tom_build_kit` | Builds the `name → CommandExecutor` map wired into the `ToolRunner`. |
| `VersionerExecutor` / `CompilerExecutor` / `RunnerExecutor` / `CleanupExecutor` / `DependenciesExecutor` | `tom_build_kit` | The core build-step executors. |
| `PubGetExecutor` / `PubUpdateExecutor` | `tom_build_kit` | Per-project `pub get` / `pub upgrade` (auto-selecting dart vs flutter). |
| `Git*Executor` (e.g. `GitStatusExecutor`, `GitCommitExecutor`, `GitSyncExecutor`) | `tom_build_kit` | One executor per git command, each with a fixed traversal order. |
| `FindProjectExecutor` | `tom_build_kit` | Resolves a project by name/ID/folder for the `findproject` binary. |

Adding a command is therefore two coordinated edits: a `CommandDefinition` in
`buildkitTool` and a `CommandExecutor` registered in `createBuildkitExecutors()`.

---

## Ecosystem

buildkit sits at the top of the build toolchain, built on the shared framework
and reusing the workspace understanding from `tom_build`.

```
                      buildkit · findproject   (this package)
                             │ built on
                             ▼
                    ┌──────────────────┐
                    │  tom_build_kit   │  ← you are here
                    └────────┬─────────┘
              depends on     │  (hosted ^2.6.25)
                             ▼
                    ┌──────────────────┐
                    │  tom_build_base  │  CLI framework: ToolRunner,
                    │  (basics layer)  │  traversal, pipelines, config
                    └──────────────────┘
```

The shared CLI framework `tom_build_base` lives in the basics layer
([`tom_ai/basics/tom_build_base`](../../basics/tom_build_base/)) and is taken as
a **hosted** dependency — buildkit consumes a published version, never a path
override. The sibling kits [`tom_test_kit`](../tom_test_kit/) and
[`tom_issue_kit`](../tom_issue_kit/) follow the same pattern.

---

## Further documentation

In-package guides under [`doc/`](doc/):

| Document | What's there |
| -------- | ------------ |
| [`doc/buildkit_user_guide.md`](doc/buildkit_user_guide.md) | The BuildKit orchestrator: pipelines, commands, scanning, security. |
| [`doc/tools_user_guide.md`](doc/tools_user_guide.md) | Reference for the individual tools: versioner, cleanup, compiler, runner, dependencies, pubget, … |
| [`doc/git_guide_mode.md`](doc/git_guide_mode.md) | The guided (`-g` / `--guide`) mode for git commands. |
| [`doc/standalone_guided_mode.md`](doc/standalone_guided_mode.md) | Guided mode for standalone tools beyond git. |
| [`doc/test_coverage.md`](doc/test_coverage.md) | The buildkit test-coverage plan and status. |
| [`doc/issues.md`](doc/issues.md) | Historical record of the consolidation issues (all resolved). |

Related packages (don't duplicate — follow the link):

| Package | Relationship |
| ------- | ------------ |
| [`tom_build_base`](../../basics/tom_build_base/) | The CLI / build framework buildkit is built on (`ToolRunner`, traversal, pipelines). |
| [`tom_build`](../tom_build/) | The workspace analyzer + metadata buildkit's traversal builds on. |
| [`tom_test_kit`](../tom_test_kit/) | Sibling kit — test tracking, same framework. |
| [`tom_issue_kit`](../tom_issue_kit/) | Sibling kit — issue tracking, same framework. |
| [Tom DevOps map](../README.md) | The repository-level index for the whole devops toolchain. |

---

## Status

- **Version:** 1.7.1 (`publish_to: none` — workspace-internal)
- **SDK:** Dart `^3.10.4`
- **Base:** `tom_build_base: ^2.6.25` (hosted)
- **Tests:** 182 tests across executor, pipeline, project-scan and git suites.
- **Binaries:** `buildkit` (primary), `findproject`.

---

## License

See [LICENSE](LICENSE); each package in this repository carries its own license
terms.
