# tom_build_base — Introduction Sample

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause.

A runnable, article-grade **introduction** to
[`tom_build_base`](../../tom_build_base/) — the foundation every Tom command-line
tool is built on (`buildkit`, `testkit`, `issuekit`, and the rest). This sample
builds one small but complete tool, **`projreport`**, from a single declarative
value and runs it against a throwaway workspace assembled in a temp directory.
Because the workspace is built and torn down in-process, **the whole sample runs
offline** — no real repository, no network, no global setup.

> **Pairs with** the module manual at
> [`tom_ai/basics/tom_build_base/README.md`](../../tom_build_base/README.md).
> This sample teaches the framework *by building a tool with it*; the manual
> documents the full API surface.

---

## Why a "build base" at all?

Every developer workspace accumulates little command-line tools: one that prints
each package's version, one that runs `dart pub get` everywhere, one that bumps
versions before a release, one that runs the tests and diffs the results. Write
three of them by hand and you notice they are 80 % the same program:

- They all **find the projects** in a workspace — walking a directory tree,
  recognising which folders are Dart packages, which are git repos, which to
  skip.
- They all **parse the same flags** — "where do I start scanning", "recurse or
  not", "only these projects", "show me the version", "show me help".
- They all **visit projects in a sensible order** — usually *dependency order*,
  so a package is built after the things it depends on.
- They all **report a consolidated result** — what succeeded, what was skipped,
  what failed, and an exit code CI can read.

`tom_build_base` is the library that owns that shared 80 %. You describe *what
your tool is* as a value, plug in *the one thing only your tool knows how to do*,
and the framework supplies traversal, argument parsing, `--help`, `--version`,
ordering, and result aggregation. A new tool becomes a few dozen lines of
genuinely tool-specific code instead of a few hundred lines of re-implemented
plumbing.

This sample's tool, **`projreport`**, is the smallest interesting example of
that idea: *for every Dart project in a workspace, print its name, version, and
dependency count.* That is one sentence of real behaviour. Everything else in
this README is about how little code it takes to wrap that sentence in a
production-quality CLI.

---

## What you will learn

Five concepts, each isolated in one runnable example file:

1. **A tool is a value.** `projreport`'s entire identity — name, version, calling
   convention, and which folders it cares about — lives in a single
   `const ToolDefinition`. You can read it, print it, and pass it around like any
   other immutable value.

2. **You supply one behaviour; the framework supplies the rest.** A
   `CommandExecutor` says what to *do* with each visited folder. A `ToolRunner`
   wires the definition to the executor and runs it. Argument parsing, help, and
   traversal are derived — not hand-written.

3. **The run produces a value, not just side effects.** `runner.run(args)`
   returns a `ToolResult` that knows how many projects it processed, skipped, and
   failed — and renders a consolidated summary block from that data.

4. **Navigation comes for free.** Because the tool opts into project navigation,
   `--project <glob>` filtering and **dependency-order traversal** work without a
   line of traversal code in the tool.

5. **The whole CLI is a few lines of `main`.** `bin/projreport.dart` builds the
   runner, hands it the arguments, prints the summary, and exits with a code that
   reflects success. That is the entire entrypoint.

---

## Quick start

Run the whole set from this folder:

```bash
cd tom_ai/basics/tom_basics_samples/tom_build_base_introduction_sample
dart pub get
dart run example/run_all_examples.dart
```

You should see five sections run and a final `5 passed, 0 failed`. The runner
exits non-zero if any example throws, so it doubles as a smoke test.

Run any single concept on its own:

```bash
dart run example/01_a_tool_is_a_value_example.dart
```

Or run the actual tool against a real workspace:

```bash
dart run bin/projreport.dart -R /path/to/workspace --scan /path/to/workspace -r
dart run bin/projreport.dart --help
dart run bin/projreport.dart --version
```

---

## How the sample is laid out

This package is shaped like a *real* Tom tool, because the layout is part of the
lesson. A production tool is not one big script — it separates the declarative
tool from the thin entrypoint that runs it.

| Path | Role |
| ---- | ---- |
| [`lib/projreport.dart`](lib/projreport.dart) | **The tool.** The `ToolDefinition`, the executor, and a `projreportRunner()` helper. This is the file you would publish. |
| [`bin/projreport.dart`](bin/projreport.dart) | **The entrypoint.** A ~10-line `main` that builds the runner, prints the summary, and sets the exit code. |
| [`example/fixture.dart`](example/fixture.dart) | **Support code.** Builds a throwaway workspace of four mini packages in a temp directory so every example is hermetic. |
| [`example/0N_*_example.dart`](example/) | **The lessons.** One concept per file, each a self-contained `main()` with inline expected output. |
| [`example/run_all_examples.dart`](example/run_all_examples.dart) | **The aggregator.** Runs all five examples and reports a pass/fail tally. |

Splitting "the tool" (`lib/`) from "running the tool" (`bin/`) is not ceremony.
It is what lets the examples import and exercise the *same* tool the entrypoint
ships, instead of copy-pasting the definition into each file. When you build your
own tool, this is the shape to copy.

---

## The fixture: a workspace in a temp directory

A `tom_build_base` tool works against a real tree of Dart projects on disk. To
keep the examples deterministic — and to avoid committing nested `pubspec.yaml`
files that `dart pub get` would try to resolve — each example builds a throwaway
workspace, runs the tool against it, and deletes it afterward.
[`example/fixture.dart`](example/fixture.dart) is that builder. It lays down four
mini packages:

```text
<temp>/
├── app/      app_runner     v0.9.0   depends on service_layer
├── service/  service_layer  v1.2.0   depends on data_layer
├── data/     data_layer     v1.0.0   no dependencies
└── draft/    draft_pkg      (no version) — reported as a skip
```

Two details are deliberate:

- **The packages are created in scrambled order** (`app`, then `service`, then
  `data`). Directory order is therefore *not* dependency order. When the tool
  emits `data_layer → service_layer → app_runner`, that ordering can only have
  come from a real dependency sort — see [example 4](#4--navigation-for-free).

- **`draft` has no `version:`.** The executor reports it as a non-failing *skip*,
  which is how it shows up in the run summary without breaking the exit code —
  see [example 3](#3--the-run-summary).

---

## The tool itself

Before the examples, here is the whole tool. It is short enough to read in one
sitting, and every example below is just a different lens on these two pieces.

### The definition — `projreport` as a value

```dart
const projreportTool = ToolDefinition(
  name: 'projreport',
  description: 'Report the name, version, and dependency count of each '
      'Dart project in a workspace.',
  version: '1.0.0',
  mode: ToolMode.singleCommand,
  // This tool only makes sense on Dart projects, so the nature filter that
  // decides which folders to visit lives on the tool itself.
  requiredNatures: {DartProjectFolder},
);
```

That `const` value *is* the tool's identity. From it, the framework derives:

- the argument parser and every standard flag (`--scan`, `--recursive`,
  `--project`, `--build-order`, `--exclude`, …);
- the `--help` text (formatted from `name`, `description`, and the flags);
- the `--version` output (`projreport v1.0.0`);
- which folders get visited (only those matching `requiredNatures`).

`ToolMode.singleCommand` says this tool has exactly **one operation** — it is
invoked as `projreport [options]`, not `projreport <subcommand>`. (Multi-command
tools like `buildkit clean` / `buildkit publish` use `ToolMode.multiCommand` and
carry a list of `CommandDefinition`s; that is the subject of the *advanced*
sample.)

### The behaviour — one `CommandExecutor`

The framework cannot know what *your* tool does with each folder. That is the one
piece you supply. A single-command tool registers its executor under the key
`'default'`:

```dart
Map<String, CommandExecutor> projreportExecutors(StringSink out) {
  return {
    'default': CallbackExecutor(
      onExecute: (context, args) async {
        final dart = context.getNature<DartProjectFolder>();
        final version = dart.version;
        if (version == null || version.isEmpty) {
          return ItemResult.skipped(
            path: context.path,
            name: context.name,
            message: 'no version in pubspec',
          );
        }
        final deps = dart.dependencies.length;
        out.writeln('${dart.projectName} v$version — $deps dependencies');
        return ItemResult.success(path: context.path, name: context.name);
      },
    ),
  };
}
```

The callback receives a **`CommandContext`** (the folder plus the natures the
framework detected on it) and the parsed **`CliArgs`**, and returns an
**`ItemResult`** the runner aggregates. Because `requiredNatures` already filtered
the traversal to Dart projects, `context.getNature<DartProjectFolder>()` is safe
— the folder would not be here otherwise.

### The runner — wiring definition to behaviour

```dart
ToolRunner projreportRunner({StringSink? output}) {
  final sink = output ?? stdout;
  return ToolRunner(
    tool: projreportTool,
    executors: projreportExecutors(sink),
    output: sink,
    verbose: false,
  );
}
```

`ToolRunner` is the engine. Give it the definition and the executors and it does
everything else when you call `run(args)`. Passing a `StringBuffer` as `output`
captures the run for a deterministic test; passing nothing sends it to `stdout`,
which is what `bin/projreport.dart` wants. That single seam — a swappable
`StringSink` — is what makes every example below testable.

---

## The examples

Ordered from "what is a tool" to "the whole CLI". Each file is a self-contained
`main()` with its expected output pasted in as a trailing `// expected output`
comment, so every snippet below is provably runnable.

| # | File | Concept |
| - | ---- | ------- |
| 1 | [`01_a_tool_is_a_value_example.dart`](example/01_a_tool_is_a_value_example.dart) | A `ToolDefinition` is an immutable value; `--version` is derived from it |
| 2 | [`02_running_the_tool_example.dart`](example/02_running_the_tool_example.dart) | Wiring an executor to the definition and running it over a workspace |
| 3 | [`03_the_run_summary_example.dart`](example/03_the_run_summary_example.dart) | `ToolResult` counters, the rendered summary, skips, and the exit code |
| 4 | [`04_navigation_for_free_example.dart`](example/04_navigation_for_free_example.dart) | `--project` filtering and automatic dependency-order traversal |
| 5 | [`05_the_whole_cli_example.dart`](example/05_the_whole_cli_example.dart) | End-to-end run — exactly what `bin/projreport.dart` does |

---

## 1 · A tool is a value

> [`example/01_a_tool_is_a_value_example.dart`](example/01_a_tool_is_a_value_example.dart)

The first thing to internalise is that a `tom_build_base` tool is **declarative**.
It is not a script with a `main` full of `if (arg == '--version')` branches. The
whole identity is a `const` value you can inspect like any other:

```dart
print('name:     ${projreportTool.name}');
print('version:  ${projreportTool.version}');
print('mode:     ${projreportTool.mode}');
print('natures:  ${projreportTool.requiredNatures}');

// --version is handled entirely by the framework from that same value.
final buf = StringBuffer();
await projreportRunner(output: buf).run(['--version']);
print('--version prints: ${buf.toString().trim()}');
```

```text
name:     projreport
version:  1.0.0
mode:     ToolMode.singleCommand
natures:  {DartProjectFolder}
--version prints: projreport v1.0.0
```

Notice that nobody wrote code to handle `--version`. The runner recognised the
flag, read `projreportTool.version`, printed `projreport v1.0.0`, and stopped —
all from the same value the first four lines just inspected. The definition is
the single source of truth, and `--help`, `--version`, and the argument parser
are all *projections* of it.

This is the payoff of "a tool is a value": the things every CLI needs are
computed once, by the framework, from data you already wrote.

---

## 2 · Running the tool

> [`example/02_running_the_tool_example.dart`](example/02_running_the_tool_example.dart)

A definition says *what* the tool is; an executor says what to *do*. Example 2
puts them together and runs the tool across the fixture workspace:

```dart
final workspace = await createFixtureWorkspace();
try {
  final out = StringBuffer();
  final runner = projreportRunner(output: out);

  await runner.run([
    '-R', workspace.path,   // workspace root
    '--scan', workspace.path, // where to start walking
    '-r',                   // recurse into subdirectories
  ]);

  print(out.toString().trimRight());
} finally {
  await disposeFixture(workspace);
}
```

```text
data_layer v1.0.0 — 0 dependencies
service_layer v1.2.0 — 1 dependencies
app_runner v0.9.0 — 1 dependencies
```

Three flags drove the run, and **all three exist for free** because the tool
opted into project navigation: `-R` set the workspace root, `--scan` chose where
to start walking, and `-r` asked the walk to recurse. The framework found the
four package folders, recognised the Dart ones, skipped the version-less
`draft`, and called the executor once per remaining project — which wrote the
three lines you see.

The output order is not the directory order. It is *dependency order*, which is
the default. Hold that thought; example 4 proves it.

---

## 3 · The run summary

> [`example/03_the_run_summary_example.dart`](example/03_the_run_summary_example.dart)

`run()` does not just produce side effects — it returns a **`ToolResult`**. That
value is how a tool knows whether the run as a whole succeeded, which is what an
exit code is made of:

```dart
final result = await projreportRunner(output: out).run([
  '-R', workspace.path, '--scan', workspace.path, '-r',
]);

print('success:        ${result.success}');
print('processed:      ${result.processedCount}');
print('failed:         ${result.failedCount}');

print('--- summary ---');
print(result.renderRunSummary().trimRight());

print('--- exit code: ${result.success ? 0 : 1} ---');
```

```text
success:        true
processed:      4
failed:         0
--- summary ---
=== Skipped ===
  draft — no version in pubspec
1 project(s) skipped.

Done. No errors.
--- exit code: 0 ---
```

Two things to read here.

**Skips are not failures.** The executor returned `ItemResult.skipped(...)` for
`draft` because it had no version. The summary lists it under `=== Skipped ===`,
and it counts toward `processedCount` (4, not 3) — but `success` stays `true` and
the exit code stays `0`. That is the right semantics for "I looked at it and
chose not to act", as opposed to `ItemResult.failure(...)`, which *would* flip
`success` to false. The three `ItemResult` constructors —
`success`, `skipped`, and `failure` — are the vocabulary every executor speaks.

**The summary is rendered, not assembled by hand.** `renderRunSummary()` turns
the collected `ItemResult`s into the consolidated block. The tool never formatted
"1 project(s) skipped." — it just returned typed results, and the framework
rendered them. A tool that failed somewhere would get an `=== Errors ===` section
in the same block, from the same call.

---

## 4 · Navigation for free

> [`example/04_navigation_for_free_example.dart`](example/04_navigation_for_free_example.dart)

This is where the "framework supplies the 80 %" claim earns its keep. Two
behaviours that every workspace tool needs — *filtering* and *ordering* — are
present without a single line of traversal code in `projreport`.

**Filtering** with `--project <glob>`:

```dart
await projreportRunner(output: filtered).run([
  '-R', workspace.path, '--scan', workspace.path, '-r',
  '--project', 'service_layer',
]);
```

```text
service_layer v1.2.0 — 1 dependencies
```

Only the requested package's line comes back. The executor did not check names;
the framework selected the subset before the executor ever ran.

**Ordering** — the default traversal is *build order*, meaning a package is
visited only after the packages it depends on:

```text
data_layer v1.0.0 — 0 dependencies
service_layer v1.2.0 — 1 dependencies
app_runner v0.9.0 — 1 dependencies
```

Read those names against the fixture. `app_runner` sorts **first**
alphabetically, and the fixture **created its directory first** — yet it appears
**last**. It has to: it depends on `service_layer`, which depends on
`data_layer`. The framework parsed the pubspecs, built the dependency graph, and
emitted the packages leaves-first. That ordering is the default precisely because
"do this to every package, dependencies first" is what build tools almost always
want. (`--no-build-order` turns it off if you need raw discovery order.)

A tool that did this by hand would need a pubspec parser, a graph builder, and a
topological sort. `projreport` got all three by setting `mode` and
`requiredNatures` on a value.

---

## 5 · The whole CLI

> [`example/05_the_whole_cli_example.dart`](example/05_the_whole_cli_example.dart)

The last example ties the four concepts together and shows that the production
entrypoint is genuinely this small:

```dart
final out = StringBuffer();
final runner = projreportRunner(output: out);

final result = await runner.run([
  '-R', workspace.path, '--scan', workspace.path, '-r',
]);

print(out.toString().trimRight());            // per-project lines
final summary = result.renderRunSummary().trimRight();
if (summary.isNotEmpty) print(summary);       // consolidated summary
print('exit ${result.success ? 0 : 1}');      // exit code
```

```text
data_layer v1.0.0 — 0 dependencies
service_layer v1.2.0 — 1 dependencies
app_runner v0.9.0 — 1 dependencies
=== Skipped ===
  draft — no version in pubspec
1 project(s) skipped.

Done. No errors.
exit 0
```

Compare that to the real entrypoint in
[`bin/projreport.dart`](bin/projreport.dart):

```dart
Future<void> main(List<String> args) async {
  final runner = projreportRunner();
  final result = await runner.run(args);

  final summary = result.renderRunSummary();
  if (summary.isNotEmpty) stdout.writeln(summary);
  exit(result.success ? 0 : 1);
}
```

The only differences are that `bin/` reads its arguments from the shell instead
of a literal list, and writes to `stdout` instead of a captured buffer. Swap the
fixture path for a real workspace and the captured sink for `stdout`, and example
5 **is** the production tool. That is the whole point: there is no hidden layer
between "the example" and "the program".

---

## How this sample stays hermetic

Every example is deterministic and offline because of three choices:

1. **The workspace is synthetic and temporary.** `createFixtureWorkspace()`
   writes four `pubspec.yaml` files into a fresh temp directory and
   `disposeFixture()` deletes the tree in a `finally`. No example touches the
   real repository, and nothing it writes survives the run.

2. **No `dart pub get` runs against the fixture.** `projreport` only *reads*
   pubspecs to extract name, version, and dependency count — it never resolves
   them. That is why the fixture can declare `service_layer: ^1.2.0` without any
   of those packages existing on pub.dev.

3. **Output is captured through a `StringSink`.** Each example passes a
   `StringBuffer` to `projreportRunner(output: ...)`, so the run's text is data
   the example can assert on rather than something that escapes to the terminal.

The result: `dart run example/run_all_examples.dart` produces identical output on
every machine, with no setup beyond `dart pub get` for the package itself.

---

## Concept reference

A compact map from the names in this sample to where they live in
`tom_build_base`. The [module manual](../../tom_build_base/README.md) documents
each in full.

| Name | Kind | What it is here |
| ---- | ---- | --------------- |
| `ToolDefinition` | class (`const`) | The declarative identity of the tool: name, version, mode, nature filter. |
| `ToolMode.singleCommand` | enum value | One-operation calling convention; executor registered under `'default'`. |
| `requiredNatures` | field (`Set<Type>`) | Folder filter; `{DartProjectFolder}` means "only visit Dart packages". |
| `CommandExecutor` | abstract class | The one behaviour the framework can't supply: what to do per folder. |
| `CallbackExecutor` | class | An executor whose body is an `onExecute` callback. |
| `CommandContext` | class | The visited folder plus its detected natures; `getNature<T>()`, `path`, `name`. |
| `DartProjectFolder` | nature | A detected Dart package; exposes `projectName`, `version`, `dependencies`. |
| `CliArgs` | class | The parsed command line handed to the executor. |
| `ItemResult` | class | Per-folder outcome: `.success`, `.skipped`, or `.failure`. |
| `ToolRunner` | class | The engine: wires definition + executors, parses args, traverses, aggregates. |
| `ToolResult` | class | The run outcome: `success`, `processedCount`, `failedCount`, `renderRunSummary()`. |

---

## Where to go next

- **The module manual** — [`tom_build_base/README.md`](../../tom_build_base/README.md)
  documents the full API: every nature, every flag, the navigation features, and
  the multi-command model.
- **The advanced sample** — builds a **multi-command** tool (several
  `CommandDefinition`s under one definition) and a tool that does real work per
  project, taking the ideas here past a single operation.
- **The real tools** — `buildkit`, `testkit`, and `issuekit` in
  `tom_ai/xternal/tom_module_basics/` are production `tom_build_base` tools. Once
  this sample clicks, their source reads like more of the same pattern at scale.

---

> **Run it:** `dart run example/run_all_examples.dart` → `5 passed, 0 failed`.
