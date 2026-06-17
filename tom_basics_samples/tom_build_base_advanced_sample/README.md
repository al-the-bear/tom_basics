# tom_build_base — Advanced Sample

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause.

A runnable, article-grade **advanced** walkthrough of
[`tom_build_base`](../../tom_build_base/) — the foundation every Tom command-line
tool is built on (`buildkit`, `testkit`, `issuekit`, and the rest). Where the
[introduction sample](../tom_build_base_introduction_sample/) built a one-operation
tool, this sample builds **`relkit`**, a *nestable, multi-command* release kit
that bundles three related operations under one definition and runs them
individually, in sequence, or nested inside another tool's traversal. Every
example runs against a throwaway workspace assembled in a temp directory, so —
like the introduction — **the whole sample runs offline**: no real repository, no
network, no global setup.

> **Read the introduction first.** This README assumes you already know that a
> tool is a `const ToolDefinition`, that an executor supplies the one behaviour
> the framework can't, and that `run()` returns a `ToolResult` you turn into an
> exit code. If those sentences are new, start with
> [`tom_build_base_introduction_sample/README.md`](../tom_build_base_introduction_sample/README.md).

> **Pairs with** the module manual at
> [`tom_ai/basics/tom_build_base/README.md`](../../tom_build_base/README.md),
> which documents the full API surface.

---

## From one operation to a toolbox

The introduction sample's `projreport` did exactly one thing: print a line per
project. That is the right shape for a tool with a single verb. But most real
build tools are *toolboxes* — `buildkit` cleans, compiles, runs, bumps, and
publishes; `git` commits, pushes, and rebases. These are not five separate
programs. They share a workspace, a traversal, a set of global flags, and a help
system; only the per-verb behaviour differs.

`tom_build_base` models that directly. A **multi-command tool** is one
`ToolDefinition` carrying a *list of commands*. Each command is itself a value —
its own name, description, options, and folder filter — and the framework gives
you, for free, everything that makes a toolbox feel like one coherent program:

- **One calling convention.** Commands are named with a leading colon:
  `relkit :report`, `relkit :audit`, `relkit :bump`. Global flags
  (`--scan`, `-r`, `-R`) work the same for all of them.
- **One traversal, many commands.** `relkit :audit :report` walks the workspace
  **once** and runs both commands per folder — not two separate walks.
- **Per-command options.** `:report --with-path` and `:bump --part=minor` attach
  options to the command they follow, parsed from that command's own definition.
- **A default command.** `relkit` with no `:command` runs whichever command the
  definition nominates as the default.
- **Nested invocation.** `relkit --nested :report` runs one command against the
  current directory with no traversal — which is how one tool runs *inside*
  another tool's walk.

This sample's tool, **`relkit`** ("release kit"), is the smallest interesting
example of all five. It has three commands that share a single notion of "what we
know about a package," and a fixture workspace shaped so each command has
something distinct to say.

---

## What you will learn

Six concepts, each isolated in one runnable example file:

1. **A multi-command tool is a value with a list of commands.** `relkit`'s
   identity — three commands, each with its own options and filter, plus a
   default — is one `const ToolDefinition`. You can inspect every command and its
   options without running anything.

2. **Running one command prints a folder-by-folder tree.** `relkit :report`
   walks the workspace and the *framework* renders `>>> folder` headers and
   `  -> :command <message>` lines from the `ItemResult`s your executor returns —
   the executor itself prints nothing.

3. **Options attach to the command they follow.** `:report --with-path` flips a
   flag declared on the report command; `:bump --part=minor` passes a value
   option whose allowed values and default live in the bump command's definition.

4. **A command can fail, and failure becomes an exit code.**
   `:audit` returns `ItemResult.failure` for projects that aren't release-ready;
   one failure flips the run's `success` to false, which `main` turns into a
   non-zero exit. `:audit` is therefore usable as a CI gate.

5. **Several commands share one traversal, and a failure short-circuits a
   folder.** `relkit :audit :report` runs both per folder in order; if `:audit`
   fails for a folder, that folder's `:report` is skipped while every other
   project still gets both.

6. **`--nested` runs one command against the current directory, no traversal.**
   This is how a host tool delegates: it has already walked to a project, so the
   nested tool skips traversal and reports a single `ToolResult` for the caller
   to render.

---

## Quick start

Run the whole set from this folder:

```bash
cd tom_ai/basics/tom_basics_samples/tom_build_base_advanced_sample
dart pub get
dart run example/run_all_examples.dart
```

You should see six sections run and a final `6 passed, 0 failed`. The runner
exits non-zero if any example throws, so it doubles as a smoke test.

Run any single concept on its own:

```bash
dart run example/04_audit_and_exit_codes_example.dart
```

Or run the actual tool against a real workspace:

```bash
dart run bin/relkit.dart :report -R /path/to/ws --scan /path/to/ws -r
dart run bin/relkit.dart :audit :report -R /path/to/ws --scan /path/to/ws -r
dart run bin/relkit.dart :bump --part=minor -R /path/to/ws --scan /path/to/ws -r
dart run bin/relkit.dart --help
dart run bin/relkit.dart --version
```

---

## How the sample is laid out

This package is shaped like a *real* Tom tool, because the layout is part of the
lesson. The declarative tool lives in `lib/`; the thin entrypoint that runs it
lives in `bin/`; the examples import and exercise the *same* tool the entrypoint
ships.

| Path | Role |
| ---- | ---- |
| [`lib/relkit.dart`](lib/relkit.dart) | **The tool.** The `ToolDefinition` with its three `CommandDefinition`s, the three executors, the shared `PackageFacts` value, and a `relkitRunner()` helper. This is the file you would publish. |
| [`bin/relkit.dart`](bin/relkit.dart) | **The entrypoint.** A ~10-line `main` that builds the runner, prints the summary, and sets the exit code. Identical in shape to the introduction's — multi-command changes nothing here. |
| [`example/fixture.dart`](example/fixture.dart) | **Support code.** Builds a throwaway, deliberately *nested* workspace of five mini packages in a temp directory so every example is hermetic. |
| [`example/0N_*_example.dart`](example/) | **The lessons.** One concept per file, each a self-contained `main()` with inline expected output. |
| [`example/run_all_examples.dart`](example/run_all_examples.dart) | **The aggregator.** Runs all six examples and reports a pass/fail tally. |

That the entrypoint is *unchanged* from the single-command introduction is itself
a lesson: the multi-command machinery — `:command` parsing, per-command options,
sequencing, `--nested` — is entirely inside the framework. `main` still just
builds a runner, runs the args, prints the summary, and exits.

---

## The fixture: a *nested* workspace in a temp directory

A multi-command tool that traverses needs a real tree to walk, and `relkit`'s
fixture is deliberately **nested** so recursion has something to find.
[`example/fixture.dart`](example/fixture.dart) lays down five mini packages:

```text
<temp>/
├── app/      app_runner     v0.9.0   long description, depends on service_layer
│   └── tool/ app_tools      v0.1.0   short-but-valid description, no deps
├── service/  service_layer  v1.2.0   description, depends on data_layer
├── data/     data_layer     v1.0.0   5-char description ("Data."), no deps
└── draft/    draft_pkg      (no version, no description)
```

Every package was chosen to make a different command interesting:

- **`app/tool/` is a package *inside* another package.** Only a recursive (`-r`)
  walk finds it — which is what makes this a *tree* rather than a flat list, and
  why it appears under its own `>>> app/tool` header in every traversal.
- **`draft_pkg` has neither a version nor a description.** `:audit` fails it,
  `:bump` skips it (nothing to bump), and `:report` still lists it as
  `(no version)`. One package, three different reactions.
- **`data_layer`'s description is exactly 5 characters.** It passes the default
  `:audit` (which only requires *a* description) but fails `:audit --min-desc=20`.
  That single package is how example 4 shows an option changing a pass into a
  fail.
- **`app_runner` and `service_layer` carry dependencies**, so their `:report`
  lines show `1 deps` rather than `0`.

The caller deletes the returned directory in a `finally`, so nothing the fixture
writes survives the run, and no `dart pub get` ever runs against it.

---

## The tool itself

Here is the whole of `relkit`, in three pieces: the shared value the commands
agree on, the declarative definition, and the three executors.

### One shared value — `PackageFacts`

All three commands need the same handful of facts about a package. Rather than
have each re-read the pubspec, they share one immutable value:

```dart
class PackageFacts {
  final String name;
  final String? version;
  final String description;
  final int dependencyCount;

  const PackageFacts({
    required this.name,
    required this.version,
    required this.description,
    required this.dependencyCount,
  });

  bool get hasVersion => version != null && version!.isNotEmpty;
  bool get hasDescription => description.trim().isNotEmpty;
}
```

The interesting part is *how* a command gets one. `packageFactsFor(context)`
prefers the nature the framework already detected, and falls back to reading the
pubspec from disk:

```dart
PackageFacts? packageFactsFor(CommandContext context) {
  final dart = context.tryGetNature<DartProjectFolder>();
  if (dart != null) {
    return PackageFacts(
      name: dart.projectName,
      version: dart.version,
      description: (dart.pubspec['description'] ?? '').toString(),
      dependencyCount: dart.dependencies.length,
    );
  }
  return _factsFromPubspecFile(context.path); // the --nested path
}
```

That two-branch resolution is what lets the *same* command work in two very
different contexts. In normal traversal the framework attaches a
`DartProjectFolder` nature, so the facts come straight off the context. In
`--nested` mode (example 6) the host hands `relkit` a bare working directory with
**no natures**, so it parses `pubspec.yaml` itself via the `yaml` package. Same
`PackageFacts` either way — which is exactly what makes one tool usable both
standalone and nested. (This is the single reason this sample depends on `yaml`.)

### The definition — three commands under one tool

```dart
const relkitTool = ToolDefinition(
  name: 'relkit',
  description: 'Release kit: report, audit, and (dry-run) bump the Dart '
      'projects in a workspace.',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  defaultCommand: 'report',
  commands: [
    CommandDefinition(
      name: 'report',
      description: 'Print one line per Dart project (name, version, deps).',
      requiredNatures: {DartProjectFolder},
      options: [
        OptionDefinition.flag(
          name: 'with-path',
          description: 'Append each project\'s path to its line.',
        ),
      ],
      examples: ['relkit :report', 'relkit :report --with-path'],
    ),
    CommandDefinition(
      name: 'audit',
      description: 'Fail projects that are not release-ready.',
      requiredNatures: {DartProjectFolder},
      options: [
        OptionDefinition.option(
          name: 'min-desc',
          description: 'Minimum required description length (0 = any).',
          defaultValue: '0',
          valueName: 'n',
        ),
      ],
      examples: ['relkit :audit', 'relkit :audit --min-desc=20'],
    ),
    CommandDefinition(
      name: 'bump',
      description: 'Show the next version each project would get (dry-run).',
      requiredNatures: {DartProjectFolder},
      options: [
        OptionDefinition.option(
          name: 'part',
          description: 'Which version part to bump.',
          defaultValue: 'patch',
          allowedValues: ['major', 'minor', 'patch'],
          valueName: 'part',
        ),
      ],
      examples: ['relkit :bump', 'relkit :bump --part=minor'],
    ),
  ],
);
```

Read this against the introduction's single-command definition and three things
stand out:

- **`mode: ToolMode.multiCommand`** is the switch. It turns on the `:command`
  calling convention, per-command help, and folder-by-folder sequencing.
- **`commands:`** is a list of values. Each `CommandDefinition` is self-contained:
  its own `name`, `description`, `requiredNatures` filter (here all three want
  `{DartProjectFolder}`, but they need not), `options`, and `examples`.
- **`defaultCommand: 'report'`** names which command runs when the user types
  `relkit` with no `:command`.

Note the two flavours of option. `OptionDefinition.flag` is a boolean presence
switch (`--with-path` → `true`). `OptionDefinition.option` takes a value, can
declare a `defaultValue`, and can constrain input with `allowedValues`
(`--part` only accepts `major`/`minor`/`patch`). You declare them; the framework
parses them.

### The behaviour — one executor per command

A single-command tool registers one executor under the key `'default'`. A
multi-command tool registers **one executor per command, keyed by command name**:

```dart
Map<String, CommandExecutor> relkitExecutors() {
  return {
    'report': CallbackExecutor(onExecute: _report),
    'audit': CallbackExecutor(onExecute: _audit),
    'bump': CallbackExecutor(onExecute: _bump),
  };
}
```

Each executor reads its own per-command option and returns an `ItemResult`
describing the outcome — and **prints nothing**. In multi-command traversal the
framework renders the per-folder tree (`>>> folder`, then `  -> :command
<message>`) from those results, so an executor that also wrote to the sink would
double the output. The report command is representative:

```dart
Future<ItemResult> _report(CommandContext context, CliArgs args) async {
  final facts = packageFactsFor(context);
  if (facts == null) {
    return ItemResult.skipped(
      path: context.path, name: context.name, message: 'not a Dart project');
  }
  final withPath = args.commandArgs['report']?.options['with-path'] == true;
  final version = facts.hasVersion ? 'v${facts.version}' : '(no version)';
  final suffix = withPath ? '  [${context.relativePath}]' : '';
  return ItemResult.success(
    path: context.path,
    name: context.name,
    message: '${facts.name} $version — ${facts.dependencyCount} deps$suffix',
  );
}
```

The line `args.commandArgs['report']?.options['with-path']` is the per-command
option lookup: the parser collects everything that followed `:report` into that
command's own bag, and the executor reads it by name. `:audit` and `:bump` read
`['audit']` and `['bump']` the same way — each sees only its own options.

---

## The examples

Ordered from "what is a multi-command tool" to "running nested". Each file is a
self-contained `main()` with its expected output pasted in as a trailing
`// expected output` comment, so every snippet below is provably runnable.

| # | File | Concept |
| - | ---- | ------- |
| 1 | [`01_a_multi_command_tool_example.dart`](example/01_a_multi_command_tool_example.dart) | A multi-command `ToolDefinition` is a value with a list of commands; inspect each command and its options |
| 2 | [`02_running_a_command_example.dart`](example/02_running_a_command_example.dart) | Running one command; the framework's folder-by-folder tree |
| 3 | [`03_per_command_options_example.dart`](example/03_per_command_options_example.dart) | Flag and value options that attach to the command they follow |
| 4 | [`04_audit_and_exit_codes_example.dart`](example/04_audit_and_exit_codes_example.dart) | A command that can fail; the errors summary and exit code |
| 5 | [`05_sequencing_commands_example.dart`](example/05_sequencing_commands_example.dart) | Several commands, one traversal, with per-folder short-circuit |
| 6 | [`06_nested_invocation_example.dart`](example/06_nested_invocation_example.dart) | `--nested`: one command against the current directory, no traversal |

---

## 1 · A multi-command tool is a value

> [`example/01_a_multi_command_tool_example.dart`](example/01_a_multi_command_tool_example.dart)

A multi-command tool is just as declarative as a single-command one — there is
simply more to inspect. The whole identity, including every command and its
options, is a `const` value:

```dart
print('name:            ${relkitTool.name}');
print('mode:            ${relkitTool.mode}');
print('default command: ${relkitTool.defaultCommand}');
print('commands:');
for (final c in relkitTool.commands) {
  final opts = c.options.map((o) => o.name).join(', ');
  print('  :${c.name} — ${c.description} [options: $opts]');
}

// --version is handled entirely by the framework from that same value.
final buf = StringBuffer();
await relkitRunner(output: buf).run(['--version']);
print('--version prints: ${buf.toString().trim()}');
```

```text
name:            relkit
mode:            ToolMode.multiCommand
default command: report
commands:
  :report — Print one line per Dart project (name, version, deps). [options: with-path]
  :audit — Fail projects that are not release-ready. [options: min-desc]
  :bump — Show the next version each project would get (dry-run). [options: part]
--version prints: relkit v1.0.0
```

Nobody wrote code to handle `--version`, and nobody assembled that command list —
both are projections of the same `const relkitTool`. The framework's `--help`
output is built from exactly this data: command names, descriptions, and the
options each one declares. The definition is the single source of truth, and
everything the user can discover about the tool is computed from it.

---

## 2 · Running a command

> [`example/02_running_a_command_example.dart`](example/02_running_a_command_example.dart)

Invoke a command by naming it with a leading colon. The global navigation flags
(`-R`, `--scan`, `-r`) work exactly as in the introduction sample:

```dart
final out = StringBuffer();
await relkitRunner(output: out).run([
  ':report',
  '-R', workspace.path,
  '--scan', workspace.path,
  '-r',
]);
print(out.toString().trimRight());
```

```text
>>> app/tool
  -> :report app_tools v0.1.0 — 0 deps
>>> data
  -> :report data_layer v1.0.0 — 0 deps
>>> draft
  -> :report draft_pkg (no version) — 0 deps
>>> service
  -> :report service_layer v1.2.0 — 1 deps
>>> app
  -> :report app_runner v0.9.0 — 1 deps
```

This is the **multi-command rendering**, and it is the framework's, not the
tool's. For each folder it walks, it prints a `>>> <relativePath>` header, then a
`  -> :<command> <message>` line per command — the message being whatever the
executor returned in its `ItemResult`. The `_report` executor returned strings
like `app_tools v0.1.0 — 0 deps`; the tree structure around them is free.

Two things to notice in the order. `app/tool` appears under its own header,
proving the recursive walk found the nested package. And the order is
*dependency order* (the default): `service_layer` precedes `app_runner` because
`app_runner` depends on it, and `data_layer` precedes `service_layer` for the
same reason — the same topological traversal the introduction sample explained,
now applied across commands.

---

## 3 · Per-command options

> [`example/03_per_command_options_example.dart`](example/03_per_command_options_example.dart)

Options written *after* a `:command` attach to that command. This is the heart of
the multi-command model: each command has its own option namespace, parsed from
its own `CommandDefinition`.

A **flag** on `:report`:

```dart
await relkitRunner(output: report).run([':report', '--with-path', ...base]);
```

```text
>>> app/tool
  -> :report app_tools v0.1.0 — 0 deps  [app/tool]
>>> data
  -> :report data_layer v1.0.0 — 0 deps  [data]
>>> draft
  -> :report draft_pkg (no version) — 0 deps  [draft]
>>> service
  -> :report service_layer v1.2.0 — 1 deps  [service]
>>> app
  -> :report app_runner v0.9.0 — 1 deps  [app]
```

`--with-path` is the boolean flag declared on the report command. The executor
read it with `args.commandArgs['report']?.options['with-path'] == true` and
appended `  [<path>]` to each line.

A **value option** with allowed values and a default, on `:bump`:

```dart
await relkitRunner(output: bump).run([':bump', '--part=minor', ...base]);
```

```text
>>> app/tool
  -> :bump would bump 0.1.0 -> 0.2.0 (minor)
>>> data
  -> :bump would bump 1.0.0 -> 1.1.0 (minor)
>>> draft
  -> :bump no version to bump
>>> service
  -> :bump would bump 1.2.0 -> 1.3.0 (minor)
>>> app
  -> :bump would bump 0.9.0 -> 0.10.0 (minor)
```

`--part=minor` is the value option whose `allowedValues: ['major', 'minor',
'patch']` and `defaultValue: 'patch'` live in the bump command's definition. Use
the `--opt=value` form to be unambiguous about which token is the value. `:bump`
is a *dry run* — it computes `nextVersion` without touching any pubspec — and it
skips `draft_pkg`, which has no version to bump (`ItemResult.skipped`, rendered
as the `no version to bump` message).

The mechanism is uniform: the framework parses each command's tokens against that
command's `OptionDefinition`s and hands the executor a bag it reads by name. No
command can see another's options.

---

## 4 · A command that can fail, and the exit code

> [`example/04_audit_and_exit_codes_example.dart`](example/04_audit_and_exit_codes_example.dart)

`:audit` is the first command that can say "no". It returns `ItemResult.failure`
for any project that is not release-ready, and a single failure flips the run's
`success` to false — which `main` turns into a non-zero exit code. That makes
`:audit` usable as a CI gate.

The default audit (only a version and *some* description required):

```dart
final r1 = await relkitRunner(output: audit).run([':audit', ...base]);
print(audit.toString().trimRight());
print(r1.renderRunSummary().trimRight());
print('exit ${r1.success ? 0 : 1}');
```

```text
>>> app/tool
  -> :audit release-ready
>>> data
  -> :audit release-ready
>>> draft
  -> :audit ERROR: no version, no description
>>> service
  -> :audit release-ready
>>> app
  -> :audit release-ready
=== Errors ===
  draft_pkg :audit — no version, no description
1 error(s) in 1 project(s).
exit 1
```

Only `draft_pkg` fails. Notice the per-folder line for a failure renders as
`ERROR: <reason>` rather than a success message — that formatting is the
framework's reaction to an `ItemResult.failure`. The failure is also collected
into the `=== Errors ===` summary block, and `success` is false, so the exit code
is `1`.

Raise the bar with the command's value option:

```dart
final r2 = await relkitRunner(output: strict)
    .run([':audit', '--min-desc=20', ...base]);
```

```text
>>> app/tool
  -> :audit release-ready
>>> data
  -> :audit ERROR: description too short (5 < 20)
>>> draft
  -> :audit ERROR: no version, no description
>>> service
  -> :audit release-ready
>>> app
  -> :audit release-ready
=== Errors ===
  data_layer :audit — description too short (5 < 20)
  draft_pkg :audit — no version, no description
2 error(s) in 2 project(s).
exit 1
```

`--min-desc=20` now also fails `data_layer`, whose description (`"Data."`) is only
5 characters. The summary collects *both* failures, and the count line reads
`2 error(s) in 2 project(s).` One option turned a passing project into a failing
one — and the executor never formatted any of that summary text; it returned a
typed `ItemResult.failure` and the framework rendered the rest.

---

## 5 · Sequencing commands

> [`example/05_sequencing_commands_example.dart`](example/05_sequencing_commands_example.dart)

Name more than one command and they run *both, in one traversal*, folder by
folder:

```dart
final result = await relkitRunner(output: out).run([
  ':audit', ':report',
  '-R', workspace.path, '--scan', workspace.path, '-r',
]);
print(out.toString().trimRight());
print('--- summary ---');
print(result.renderRunSummary().trimRight());
print('processed ${result.processedCount}, exit ${result.success ? 0 : 1}');
```

```text
>>> app/tool
  -> :audit release-ready
  -> :report app_tools v0.1.0 — 0 deps
>>> data
  -> :audit release-ready
  -> :report data_layer v1.0.0 — 0 deps
>>> draft
  -> :audit ERROR: no version, no description
>>> service
  -> :audit release-ready
  -> :report service_layer v1.2.0 — 1 deps
>>> app
  -> :audit release-ready
  -> :report app_runner v0.9.0 — 1 deps
--- summary ---
=== Errors ===
  draft_pkg :audit — no version, no description
1 error(s) in 1 project(s).
processed 9, exit 1
```

Two behaviours to read here.

**One traversal, not two.** Every folder is visited once, and both commands run
under the same `>>> folder` header in the order given (`:audit` then `:report`).
A naïve toolbox would walk the tree twice — once per command — and lose the
per-folder grouping. The framework interleaves instead.

**Failure short-circuits the folder.** `draft` fails `:audit`, so its `:report`
line never appears — while every *other* project still gets both commands. The
short-circuit is scoped to the failing folder, not the whole run: traversal
continues to the next project. The run's overall `success` reflects the audit
failure (exit `1`), and `processedCount` is `9` — eight command-executions that
ran (four folders × `:audit` + four folders × `:report`, with `draft`'s report
skipped giving 5 + 4 = 9 counted executions).

This is the pipeline pattern real tools use: `buildkit :clean :compile :test`
runs each stage per project and stops a project's pipeline the moment a stage
fails, without abandoning the other projects.

---

## 6 · Nested invocation

> [`example/06_nested_invocation_example.dart`](example/06_nested_invocation_example.dart)

`--nested` is how a tool runs *inside* another tool's traversal. The host has
already walked to a project directory, so the nested tool **skips traversal
entirely** and runs one command against the current working directory:

```dart
Directory.current = Directory('${workspace.path}/service');

final out = StringBuffer();
final result = await relkitRunner(output: out).run(['--nested', ':report']);

print('processed: ${result.processedCount}');
for (final item in result.itemResults) {
  print('report line: ${item.message}');
}
print('success: ${result.success}');
```

```text
processed: 1
report line: service_layer v1.2.0 — 1 deps
success: true
```

Three differences from a normal run, all of them the point:

- **No traversal, no tree.** There are no `>>> folder` headers because nothing was
  walked. Nested mode runs the command once, against `Directory.current`, and
  hands you back a `ToolResult` with a single item.
- **You render the result.** The framework prints nothing in nested mode; the
  caller reads `result.itemResults` and renders them however the host wants. That
  is exactly what a host tool does when it embeds `relkit` in its own output.
- **No natures are attached.** Because the host did no detection, the
  `CommandContext` arrives with an empty nature list — which is why
  `packageFactsFor` falls back to reading `pubspec.yaml` from disk. This is the
  payoff of the two-branch `PackageFacts` resolution from
  [the tool walkthrough](#one-shared-value--packagefacts): the *same* `:report`
  executor works both standalone (nature-driven) and nested (pubspec-driven)
  without knowing which mode it is in.

Nested mode is what lets `tom_build_base` tools compose. A higher-level
orchestrator can traverse a workspace once and, at each project, invoke several
specialised tools in `--nested` mode — each contributing one line to a combined
report — instead of every tool re-walking the tree.

---

## How this sample stays hermetic

Every example is deterministic and offline because of three choices, the same
three the introduction sample relies on:

1. **The workspace is synthetic and temporary.** `createFixtureWorkspace()`
   writes five `pubspec.yaml` files into a fresh temp directory and
   `disposeFixture()` deletes the tree in a `finally`. Example 6 additionally
   saves and restores `Directory.current` so changing the working directory
   never leaks out of the example.

2. **No `dart pub get` runs against the fixture.** `relkit` only *reads* pubspecs
   — through the detected nature, or by parsing the file in nested mode — it never
   resolves them. That is why the fixture can declare `service_layer: ^1.2.0`
   without any of those packages existing on pub.dev.

3. **Output is captured through a `StringSink`.** Each example passes a
   `StringBuffer` to `relkitRunner(output: ...)`, so the framework's tree and
   summary are data the example can assert on rather than text that escapes to
   the terminal.

The result: `dart run example/run_all_examples.dart` produces identical output on
every machine, with no setup beyond `dart pub get` for the package itself.

---

## Concept reference

A compact map from the names this sample adds (beyond the introduction's) to
where they live in `tom_build_base`. The
[module manual](../../tom_build_base/README.md) documents each in full.

| Name | Kind | What it is here |
| ---- | ---- | --------------- |
| `ToolMode.multiCommand` | enum value | Multi-verb calling convention; executors keyed by command name. |
| `CommandDefinition` | class (`const`) | One command's identity: name, description, `requiredNatures`, options, examples. |
| `defaultCommand` | field (`String?`) | Which command runs when the user names none. |
| `OptionDefinition.flag` | named constructor | A boolean presence option (`--with-path`). |
| `OptionDefinition.option` | named constructor | A value option with optional `defaultValue` and `allowedValues` (`--part`). |
| `args.commandArgs['<cmd>']` | parsed value | A command's own option bag; `.options['<name>']` reads one option. |
| per-folder tree | rendering | `>>> folder` + `  -> :command <message>`, rendered by the framework from `ItemResult`s. |
| command sequencing | run behaviour | `:a :b` runs both per folder in order; a failure short-circuits that folder. |
| `--nested` | run mode | Skip traversal; run one command against the current directory, no natures attached. |
| `tryGetNature<T>()` | `CommandContext` method | Returns the detected nature or `null` — used to support the nature-less nested path. |

For the foundational names (`ToolDefinition`, `CommandExecutor`,
`CallbackExecutor`, `CommandContext`, `ItemResult`, `ToolRunner`, `ToolResult`,
`DartProjectFolder`), see the
[introduction sample's reference table](../tom_build_base_introduction_sample/README.md#concept-reference).

---

## Where to go next

- **The introduction sample** —
  [`tom_build_base_introduction_sample/README.md`](../tom_build_base_introduction_sample/README.md)
  builds the single-command `projreport` and explains "a tool is a value,"
  executors, the run summary, and dependency-order navigation. Start there if any
  of those felt assumed above.
- **The module manual** — [`tom_build_base/README.md`](../../tom_build_base/README.md)
  documents the full API: every nature, every flag, the navigation features, and
  the complete multi-command model.
- **The real tools** — `buildkit`, `testkit`, and `issuekit` in
  `tom_ai/xternal/tom_module_basics/` are production multi-command
  `tom_build_base` tools. `buildkit` in particular is `relkit` at scale: many
  commands, real per-project work, and pipelines like `:clean :compile :test`
  built on exactly the sequencing model in example 5.

---

> **Run it:** `dart run example/run_all_examples.dart` → `6 passed, 0 failed`.
