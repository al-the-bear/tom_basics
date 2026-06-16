# tom_build_base

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause, see [LICENSE](LICENSE).

Unified CLI framework for workspace traversal, tool definition, pipeline
execution, and build configuration.

`tom_build_base` is the foundation every Tom command-line tool is built on —
`buildkit`, `testkit`, `issuekit`, `d4rtgen`, and the rest. It answers the
questions that *every* workspace tool has to answer and that nobody should have
to re-answer: how do I declare commands and options, how do I generate help,
how do I find the projects in this workspace, in what order do I process them,
and how do I run a pipeline of shell and tool steps over them. A tool author
declares **what** their tool does (a `ToolDefinition` with commands and an
executor per command); `tom_build_base` supplies **how** it runs.

This is a deliberately large, single-purpose package. It is also the reason the
Tom CLI tools feel like one product rather than a pile of scripts: they share
this framework, so they share their navigation flags, their help format, their
configuration model, and their end-of-run summaries.

---

## Overview

A workspace tool is mostly the same machinery wrapped around a small core of
tool-specific logic. Without a shared base, every tool reinvents argument
parsing, copies a help formatter, writes its own directory walk, and disagrees
with its siblings about what `--project` means. `tom_build_base` collapses all
of that into one framework with four cooperating layers:

- **Tool definition** — `ToolDefinition`, `CommandDefinition`, `OptionDefinition`
  describe a tool *declaratively*. From that description the framework derives
  argument parsing, `--help`/`--version`, shell completion, and the standard
  navigation flags — no imperative wiring per tool.
- **Execution** — `ToolRunner` takes a definition plus a `CommandExecutor` per
  command, parses the arguments, runs the right command across the traversal,
  and aggregates per-item outcomes into a single `ToolResult`.
- **Traversal** — `BuildBase.traverse` (and the higher-level runner) scans the
  filesystem, detects each folder's *natures* (Dart project, git repo,
  buildkit folder…), filters by project/module selectors, orders by dependency
  build order or git depth, and invokes a callback with a typed
  `CommandContext` per match.
- **Pipelines & configuration** — multi-command tools get pipelines, runtime
  macros, and persistent defines automatically; `TomBuildConfig` reads the
  two-tier `…_master.yaml` / project-level YAML configuration.

The package ships two entry points. `package:tom_build_base/tom_build_base.dart`
is the full surface (tool framework + traversal + config + utilities);
`package:tom_build_base/tom_build_base_v2.dart` is the same modern surface
without the few legacy utility exports, for tools that only need the v2
framework.

---

## Installation

```yaml
dependencies:
  tom_build_base: ^2.6.0
```

Or from the command line:

```sh
dart pub add tom_build_base
```

Then import the entry point:

```dart
import 'package:tom_build_base/tom_build_base.dart';
```

Requires Dart SDK `^3.10.4`. It depends on `args`, `console_markdown`, `dcli`,
`glob`, `path`, and `yaml`. It is a `dart:io` package — it runs on desktop,
server, and CLI hosts, not the web.

---

## Features

### Tool definition

| API | Kind | Purpose |
| --- | --- | --- |
| `ToolDefinition` | class | Declares a tool: name, version, mode, commands, features |
| `CommandDefinition` | class | One command: name, aliases, options, nature requirements |
| `OptionDefinition` | class | One flag/option/multi-option, with `.flag`/`.option`/`.multi` constructors |
| `ToolMode` | enum | `singleCommand`, `multiCommand`, or `hybrid` |
| `NavigationFeatures` | class | Which navigation flags a tool exposes (`projectTool`, `gitTool`, `all`, …) |
| `CommandListOps` | extension | `without` / `replacing` / `plus` for deriving command lists |

### Execution

| API | Kind | Purpose |
| --- | --- | --- |
| `ToolRunner` | class | Parses args, routes commands, drives traversal, aggregates results |
| `CommandExecutor` | abstract | The contract: run a command on one folder |
| `CallbackExecutor` | class | Build an executor from a closure |
| `SyncExecutor` / `ListExecutor` / `ShellExecutor` / `DartExecutor` | class | Ready-made executors |
| `ItemResult` | class | Outcome for one folder: success / skipped / failure |
| `ToolResult` | class | Aggregated run outcome + `renderRunSummary()` |

### Traversal

| API | Kind | Purpose |
| --- | --- | --- |
| `BuildBase.traverse` | static | Scan → detect → filter → order → run a callback per folder |
| `BaseTraversalInfo` | abstract | Shared traversal config (exclude patterns, test-project toggles) |
| `ProjectTraversalInfo` | class | Project-mode config (scan path, recursive, build-order, selectors) |
| `GitTraversalInfo` | class | Git-mode config (modules, inner/outer-first order) |
| `CommandContext` | class | Per-folder context: path, natures, `getNature<T>()` |
| `DartProjectFolder` / `GitFolder` / `BuildkitFolder` / `ExtensionFolder` | nature | Detected folder kinds with typed metadata |
| `FilterPipeline` / `FolderSorter` | class | Project/module filtering and build-order/git-depth ordering |

### Pipelines, configuration & utilities

| API | Kind | Purpose |
| --- | --- | --- |
| `PipelineConfig` / `PipelineExecutor` | class | Multi-step pipelines (`shell`, `shell-scan`, `stdin`, `print`, `{TOOL}`) |
| `TomBuildConfig` | class | Two-tier `…_master.yaml` + project-level config loading |
| `HelpGenerator` / `CompletionGenerator` | class | Auto-generated help and shell completion |
| `yamlToMap` / `yamlListToList` / `toStringList` | function | YAML-node conversion helpers |
| `MkLinkExecutor` / `createSymLink` | API | Cross-platform symlink creation for tool commands |

---

## Quick start

A complete tool is a `ToolDefinition`, one `CommandExecutor` per command, and a
`ToolRunner` to glue them together:

```dart
import 'dart:io';
import 'package:tom_build_base/tom_build_base.dart';

const myTool = ToolDefinition(
  name: 'mytool',
  description: 'My custom build tool',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.projectTool,
  commands: [
    CommandDefinition(
      name: 'list',
      description: 'List discovered Dart projects',
      requiredNatures: {DartProjectFolder},
    ),
  ],
);

void main(List<String> args) async {
  final runner = ToolRunner(
    tool: myTool,
    executors: {
      'list': CallbackExecutor(
        onExecute: (context, args) async {
          final dart = context.getNature<DartProjectFolder>();
          print('  ${dart.projectName} v${dart.version}');
          return ItemResult.success(path: context.path, name: context.name);
        },
      ),
    },
  );
  final result = await runner.run(args);
  exit(result.success ? 0 : 1);
}
```

That ~30-line tool already supports `mytool :list`, `mytool --help`,
`mytool --version`, the full `--project` / `--exclude` / `--scan` /
`--build-order` navigation flag set, dependency-ordered traversal, and a
consolidated end-of-run summary. `--version` prints:

```text
mytool v1.0.0
```

and `--help` prints the tool description, every global option, and the command
list — all derived from the definition, none of it hand-written.

> The runnable version of this tool lives in
> [`example/tom_build_base_example.dart`](example/tom_build_base_example.dart).

---

## Example projects

| Example | What it shows |
| --- | --- |
| [`example/tom_build_base_example.dart`](example/tom_build_base_example.dart) | A two-command (`hello`, `list`) `ToolRunner` tool |

Run it with:

```sh
dart run example/tom_build_base_example.dart --help
dart run example/tom_build_base_example.dart :list
```

> Worked samples — `tom_build_base_sample` (the tool-authoring walkthrough) and
> `tom_build_base_advanced_analyzer_sample` (traversal feeding an analyzer
> cache) — are planned under `../tom_basics_samples/`; until they land, the
> usage sections below and the [`doc/`](#further-documentation) guides are the
> reference.

---

## Usage

### Defining a tool

A `ToolDefinition` is a `const` value object. Its `mode` decides the calling
convention:

- `ToolMode.singleCommand` — the tool *is* one operation (`mytool [options]`).
- `ToolMode.multiCommand` — the tool dispatches to named commands, invoked with
  a colon prefix (`mytool :build`, `mytool :clean`).
- `ToolMode.hybrid` — supports both.

`features` selects which standard flags appear. The presets cover the common
cases — `NavigationFeatures.projectTool` (project traversal + recursion),
`NavigationFeatures.gitTool` (git traversal), `NavigationFeatures.all`,
`NavigationFeatures.minimal` — or construct one to enable exactly the flags you
want (`jsonOutput`, `interactiveMode`, `dryRun`, …).

```dart
const tool = ToolDefinition(
  name: 'mytool',
  description: 'Demonstrates the definition surface',
  version: '2.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.projectTool,
  commands: [
    CommandDefinition(
      name: 'build',
      description: 'Compile each package',
      aliases: ['b'],
      requiredNatures: {DartProjectFolder},
      examples: ['mytool :build', 'mytool :build --project app_*'],
    ),
  ],
);
```

`CommandDefinition.requiredNatures` is the filter that makes a command run only
where it makes sense: `{DartProjectFolder}` means "only on folders that are Dart
projects". Commands resolve by exact name, alias, or **unambiguous prefix** —
`mytool :b` and `mytool :bui` both reach `build`, and an ambiguous prefix
resolves to nothing rather than guessing.

### Options

`OptionDefinition` has three named constructors for the three kinds of option,
and a `.usage` getter the help generator uses:

```dart
const verbose = OptionDefinition.flag(
    name: 'verbose', abbr: 'v', description: 'Verbose output');
const config = OptionDefinition.option(
    name: 'config', abbr: 'c', description: 'Config path', valueName: 'path');
const exclude = OptionDefinition.multi(
    name: 'exclude', description: 'Skip these', valueName: 'pattern');

print(verbose.usage); // -v, --verbose
print(config.usage);  // -c, --config=<path>
print(exclude.type);  // OptionType.multiOption
```

You rarely define the navigation options yourself — `projectTraversalOptions`,
`gitTraversalOptions`, and `commonOptions` are contributed automatically based
on the tool's `features`. Define options only for behaviour unique to your tool.

### Deriving a tool from another

Because a `ToolDefinition` is immutable, you extend one with `copyWith`, and the
`CommandListOps` extension (`without` / `replacing` / `plus`) edits the command
list functionally. This is how a specialised tool reuses a general one without
inheritance:

```dart
final superTool = baseTool.copyWith(
  name: 'supertool',
  commands: baseTool.commands
      .without({'clean'})                       // drop a command
      .replacing('build', fasterBuildCommand)   // swap one out, keep its slot
      .plus([shipCommand]),                      // add new ones
);

print(superTool.commands.map((c) => c.name)); // (build, ship)
print(superTool.findCommand('sh')?.name);      // ship  (prefix match)
```

### Running commands

`ToolRunner` ties a definition to behaviour. Each command name maps to a
`CommandExecutor`; the simplest is `CallbackExecutor`, which wraps a closure.
The closure receives a `CommandContext` (the folder and its natures) and the
parsed `CliArgs`, and returns an `ItemResult`:

```dart
final runner = ToolRunner(
  tool: myTool,
  executors: {
    'build': CallbackExecutor(
      onExecute: (context, args) async {
        if (!context.isDartProject) {
          return ItemResult.skipped(
              path: context.path, name: context.name, message: 'not a package');
        }
        // … do the build …
        return ItemResult.success(path: context.path, name: context.name);
      },
    ),
  },
);
await runner.run(args);
```

For common shapes there are ready-made executors: `ShellExecutor` (run a shell
command per folder), `DartExecutor` (a `Future<bool>` function per folder),
`SyncExecutor` (a synchronous callback), and `ListExecutor` (just enumerate).

### Reading results

Each folder yields an `ItemResult` — `success`, `skipped` (a deliberate,
non-failing skip), or `failure`. `ToolResult.fromItems` aggregates them, and
`renderRunSummary()` produces the uniform end-of-run block every Tom tool
prints:

```dart
final result = ToolResult.fromItems([
  ItemResult.success(path: '/a', name: 'a', commandName: 'build'),
  ItemResult.skipped(path: '/b', name: 'b', commandName: 'build', message: 'no changes'),
  ItemResult.failure(path: '/c', name: 'c', commandName: 'build', error: 'compile failed'),
]);

print('success=${result.success} failed=${result.failedCount}');
print(result.renderRunSummary());
```

Output:

```text
success=false failed=1
=== Skipped ===
  b :build — no changes
1 project(s) skipped.

=== Errors ===
  c :build — compile failed
1 error(s) in 1 project(s).
```

A skipped item is still a *success* — it never affects the exit code — but it is
reported separately from items that did real work, so a long run ends with one
readable account of what was built, what was skipped and why, and what failed.

### Traversal without the full runner

When you want the scanning and ordering machinery but not the CLI layer — say,
inside another tool or a test — call `BuildBase.traverse` directly. You give it
a traversal config and a nature filter; it scans, detects natures, filters,
orders, and invokes your callback with a typed `CommandContext`:

```dart
await BuildBase.traverse(
  info: ProjectTraversalInfo(
    scan: workspaceRoot,
    recursive: true,
    executionRoot: workspaceRoot,
  ),
  requiredNatures: {DartProjectFolder},
  run: (ctx) async {
    final dart = ctx.getNature<DartProjectFolder>();
    print('${dart.projectName} v${dart.version}');
    return true;
  },
);
```

Over a workspace containing `alpha` and `beta` packages this prints:

```text
alpha v1.2.3
beta v1.2.3
```

By default `ProjectTraversalInfo.buildOrder` is `true`, so packages arrive in
dependency order (a package's dependencies before the package itself) computed
across *all* scanned projects — not just the filtered subset — so ordering stays
correct even when `--project` narrows the run. At least one of `requiredNatures`
/ `worksWithNatures` must be set; use `{FsFolder}` to match every folder.

### Natures

A *nature* is a capability the framework detects on a folder. One folder can
have several — a Dart package inside a git repo is both a `DartProjectFolder`
and a `GitFolder`. `CommandContext` exposes them type-safely:

```dart
if (ctx.hasNature<DartProjectFolder>()) {
  final dart = ctx.getNature<DartProjectFolder>();      // throws if absent
  print(dart.dependencies.keys);
}
final git = ctx.tryGetNature<GitFolder>();              // null if absent
```

| Nature | Detected when | Carries |
| --- | --- | --- |
| `DartProjectFolder` | folder has `pubspec.yaml` | `projectName`, `version`, `dependencies`, `devDependencies`, `pubspec` |
| `GitFolder` | folder has `.git/` | git repository metadata |
| `BuildkitFolder` | folder has `buildkit.yaml` | tool configuration presence |
| `ExtensionFolder` | a VS Code / tool extension folder | extension metadata |

`DartProjectFolder` is hierarchy-aware: a Flutter package is a
`FlutterProjectFolder` *and* matches `DartProjectFolder`, so a
`requiredNatures: {DartProjectFolder}` filter catches every Dart project subtype.

### Configuration

Tom tools read configuration from two tiers: a workspace-root master file
(`{tool}_master.yaml`, e.g. `buildkit_master.yaml`) for shared defaults, and a
per-project file (`buildkit.yaml`) that overrides them. `TomBuildConfig.load`
and `TomBuildConfig.loadMaster` read these:

```yaml
# buildkit_master.yaml (workspace root) — shared defaults
navigation:
  scan: .
  recursive: true
  exclude: [.git, build]

mytool:
  verbose: false

# buildkit.yaml (inside a project) — overrides
mytool:
  verbose: true
```

### Pipelines

Multi-command tools get pipelines for free. A pipeline is a list of steps, each
with a prefix that decides how the step runs:

| Prefix | Behaviour |
| --- | --- |
| `shell <cmd>` | Run a shell command once |
| `shell-scan <cmd>` | Run the command once per traversed project |
| `stdin <cmd>` | Run with multiline stdin content |
| `print <msg>` | Print exactly one resolved message (no shell noise) |
| `{TOOL} <cmd>` | Delegate to one of the tool's own commands |

Pipelines also support runtime **macros** (`$name`, defined on the command line
and persisted per tool) and persistent **defines** (key/value pairs in the
master and project YAML). See
[`multiws_pipelines_macros_defines.md`](doc/multiws_pipelines_macros_defines.md)
and [`modes_and_placeholders.md`](doc/modes_and_placeholders.md) for the full
model.

---

## Architecture

```text
package:tom_build_base/tom_build_base.dart   (full surface)
package:tom_build_base/tom_build_base_v2.dart (framework only, no legacy utils)
        │
   ┌────┴───────────────── Tool definition ──────────────────┐
   │ ToolDefinition ── commands ─▶ CommandDefinition          │
   │      │                             │                     │
   │   features                      options ─▶ OptionDefinition
   │   (NavigationFeatures)                                   │
   └──────────────┬──────────────────────────────────────────┘
                  │ given to
                  ▼
            ToolRunner ── executors: { name → CommandExecutor }
                  │  parse args → route command → traverse → aggregate
                  ▼
            BuildBase.traverse
                  │ scan ─▶ NatureDetector ─▶ FilterPipeline ─▶ FolderSorter
                  ▼
            CommandContext (path + natures) ─▶ executor ─▶ ItemResult
                  │
                  ▼
            ToolResult.fromItems(...) ─▶ renderRunSummary()
```

| Type | Role |
| --- | --- |
| `ToolDefinition` | Declarative description of a tool (the single source of truth) |
| `CommandDefinition` | One command within a multi-command tool |
| `OptionDefinition` | One flag/option/multi-option |
| `ToolRunner` | Parses args, routes to a command, drives traversal, aggregates |
| `CommandExecutor` | The per-folder behaviour contract (`CallbackExecutor` et al.) |
| `BuildBase` | Static traversal engine: scan → detect → filter → order → run |
| `BaseTraversalInfo` / `ProjectTraversalInfo` / `GitTraversalInfo` | Traversal configuration (project vs git mode) |
| `CommandContext` | Typed per-folder context with nature accessors |
| `FilterPipeline` / `FolderSorter` | Selection and ordering |
| `ItemResult` / `ToolResult` | Per-item and aggregated outcomes |
| `TomBuildConfig` | Two-tier YAML configuration loader |

The framework holds no global mutable state across tools: a `ToolDefinition` is
an immutable value, traversal is a pure scan over the filesystem, and a
`ToolRunner` owns only the state of its own invocation.

---

## Ecosystem

`tom_build_base` is the build-framework member of the
[`tom_ai/basics`](../) foundation layer:

- [`tom_basics`](../tom_basics/) — exceptions, logging, the platform seam, and
  the runtime model.
- [`tom_basics_console`](../tom_basics_console/) — the standalone/server
  platform implementation.
- [`tom_basics_network`](../tom_basics_network/) — HTTP retry and LAN server
  discovery.

Downstream, the Tom CLI tools are *all* `tom_build_base` tools: `buildkit`,
`testkit`, `issuekit`, and the code generators each ship a `ToolDefinition` and
a set of executors and let this package supply everything else. That is the
design rule for the workspace — shared CLI infrastructure lives here, never
re-implemented in a tool. New capability that a tool needs is added to
`tom_build_base`, published, and then consumed.

---

## Further documentation

The [`doc/`](doc/) folder holds the in-depth guides:

- [`build_base_user_guide.md`](doc/build_base_user_guide.md) — the complete user
  guide and API reference.
- [`cli_tools_navigation.md`](doc/cli_tools_navigation.md) — the navigation flag
  model and how traversal selection works.
- [`modes_and_placeholders.md`](doc/modes_and_placeholders.md) — modes and
  placeholder resolution.
- [`multiws_pipelines_macros_defines.md`](doc/multiws_pipelines_macros_defines.md)
  — pipelines, multi-workspace runs, macros, and defines.
- [`tool_inheritance_and_nesting.md`](doc/tool_inheritance_and_nesting.md) —
  deriving tools (`copyWith` + `CommandListOps`) and nested tool wiring.
- [`test_coverage.md`](doc/test_coverage.md) — the test-coverage map.

See also [`../README.md`](../README.md), the `tom_ai/basics` package map, and
[`example/tom_build_base_example.dart`](example/tom_build_base_example.dart).

---

## Status

- **Version:** 2.6.25
- **Tests:** an extensive suite under `test/` (`dart test` / `testkit :test`)
  covering tool definition, argument parsing, help and completion generation,
  traversal, filtering and build-order, pipelines, macros and defines, and
  configuration loading.
- **Analysis:** clean under `package:lints` (`dart analyze` — no issues).
- **Platforms:** any Dart runtime with `dart:io` (desktop, server, CLI).
