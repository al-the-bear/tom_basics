# tom_build_base — Advanced Analyzer-Caching Sample

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause.

A runnable, article-grade walkthrough that marries two libraries: the
command-line foundation [`tom_build_base`](../../tom_build_base/) (workspace
traversal) and the analyzer-summary cache
[`tom_analyzer_shared`](../../tom_analyzer_shared/). Together they build
**`sumkit`** — a *nestable, single-command* build tool that walks the Dart
projects in a workspace and reports how much of each project's analyzer work a
shared cache can save. Every example runs against a throwaway workspace
assembled in a temp directory, so the **whole sample runs offline**: no real
pub cache, no network, no Dart analyzer invoked, no global setup.

> **Read the `tom_build_base` introduction first.** This README assumes you
> already know that a tool is a `const ToolDefinition`, that an executor
> supplies the one behaviour the framework can't, and that `run()` returns a
> `ToolResult` you turn into an exit code. If those sentences are new, start
> with
> [`tom_build_base_introduction_sample/README.md`](../tom_build_base_introduction_sample/README.md),
> then the
> [advanced (multi-command) sample](../tom_build_base_advanced_sample/README.md).

> **Pairs with** the module manual at
> [`tom_ai/basics/tom_analyzer_shared/README.md`](../../tom_analyzer_shared/README.md),
> which documents the caching API in full, and
> [`tom_ai/basics/tom_build_base/README.md`](../../tom_build_base/README.md) for
> the tool framework.

---

## The problem: a generator re-analyses the world on every run

A code generator built on the Dart `analyzer` package — a reflection emitter, a
serialization builder, a linter with cross-file rules — cannot look at *your*
code in isolation. To resolve a type you wrote, the analyzer must also resolve
everything that type touches: its supertypes, the classes it references, the
packages those come from. In practice that means **before a generator can do its
own job, it analyses all of your dependencies.**

Most of those dependencies never change between runs. A package you depend on
from pub.dev at `meta 1.16.0` is *immutable*: that exact version is the same
bytes on every machine, forever. Re-analysing it on every generator run is pure
waste — the answer is identical each time. The same is true of SDK packages,
pinned to an SDK version.

`tom_analyzer_shared` removes that waste with an **analyzer summary cache**. A
summary is the analyzer's serialised type information for one package, written
once to a `.sum` file keyed by `name@version`. The next run loads the summary
instead of re-analysing the source. The first ("cold") run pays the full cost;
every run after ("warm") skips the cached dependencies entirely. That cold→warm
difference is the payoff this sample is about.

But not every dependency can be cached. A `path` dependency points at a local
folder whose contents can change *without* the version string changing; a `git`
dependency can be force-pushed under the same ref. Their `name@version` is not a
stable key, so they are re-analysed from source every run. **Cacheability is a
property of the dependency's source**, and getting that classification right is
the first thing the cache has to do.

`sumkit` is the *pre-flight* for that cache. It doesn't generate code; it
answers the question a generator implicitly asks at startup: for every project
in this workspace, how many dependencies are cacheable, how many of those
summaries are already on disk (hits), and how many would still have to be built
(misses — the work the cache saves)? Run it with `--warm` and it fills the
cache so the next report reads all-hits.

---

## What is real here, and what is a stand-in

This sample is honest about a boundary, and it is worth stating up front because
it shapes every example.

Everything that **decides** hits versus misses is real `tom_analyzer_shared`
code:

- `DependencyResolver` parses a real `pubspec.lock` into versioned dependencies.
- `PackageDependency.isCacheable` / `DependencySet` apply the real cacheability
  rule.
- `SummaryCacheManager` is the actual on-disk `.sum` cache —
  `hasSummary`, `findMissingSummaries`, `writeSummary`, `getStats`, `clearCache`
  are the production methods, operating on real files.

The **one** thing the sample fakes is the summary **bytes**. Producing a genuine
analyzer summary needs the SDK and the populated pub cache, and is neither
hermetic nor offline nor deterministic — exactly the properties a sample must
have. So where a generator would invoke the analyzer and serialise its output,
`--warm` writes a tiny, clearly-labelled placeholder instead. `hasSummary` only
checks that the `.sum` file exists and is non-empty, so a placeholder reads as
"cached" for the purpose of the cache-lookup half — which is the half `sumkit`
demonstrates, and which is **identical** whether the bytes came from the
analyzer or from here.

The production one-call path that fills the cache for real is
`runSummaryCacheStage(projectRoot)` (documented in the
[`tom_analyzer_shared` README](../../tom_analyzer_shared/README.md)). This sample
references it in prose but never runs it, precisely because it is not hermetic.

---

## What you will learn

Six concepts, each isolated in one runnable example file:

1. **The cacheability rule is a property of the dependency's source.**
   `PackageDependency.isCacheable` is true only for `hosted` and `sdk` packages;
   `path` and `git` are re-analysed every run. `DependencySet` partitions a list
   by that rule. Pure data — no files, no cache.

2. **Exact versions come from `pubspec.lock`.** `DependencyResolver` parses the
   lock file `dart pub get` writes into versioned `PackageDependency` values,
   and the `DependencyListExtensions` (`.hosted`, `.paths`, `.cacheable`,
   `.findByName`) slice them the way a generator would.

3. **The cache is one `.sum` file per dependency, and a miss is just a missing
   file.** `SummaryCacheManager` owns `<workspace>/.tom/analyzer-cache/`;
   `hasSummary` is an existence-and-non-empty check, and `findMissingSummaries`
   runs it over the cacheable dependencies.

4. **The payoff is a miss becoming a hit.** Write a summary once and the next
   check reports zero missing for that dependency — the cold→warm transition, in
   miniature, on one project.

5. **A tool turns that into a workspace report.** `sumkit` walks the workspace in
   build order and reports per project; `--warm` fills one shared cache, so a
   dependency warmed for an early project is already a hit for the projects that
   follow.

6. **`--nested` reports one project against the current directory, no
   traversal.** This is how a host tool delegates: it has already walked to a
   project, so the nested tool scans the cwd once.

---

## Quick start

Run the whole set from this folder:

```bash
cd tom_ai/basics/tom_basics_samples/tom_build_base_advanced_analyzer_sample
dart pub get
dart run example/run_all_examples.dart
```

You should see six sections run and a final `6 passed, 0 failed`. The runner
exits non-zero if any example throws, so it doubles as a smoke test.

Run any single concept on its own:

```bash
dart run example/04_the_caching_payoff_example.dart
```

Or run the actual tool against a real workspace (one with `pubspec.lock` files
present — i.e. after `dart pub get`):

```bash
dart run bin/sumkit.dart -R /path/to/ws --scan /path/to/ws -r
dart run bin/sumkit.dart --warm -R /path/to/ws --scan /path/to/ws -r
dart run bin/sumkit.dart --rebuild -R /path/to/ws --scan /path/to/ws -r
dart run bin/sumkit.dart --help
dart run bin/sumkit.dart --version
```

---

## How the sample is laid out

```text
tom_build_base_advanced_analyzer_sample/
├── pubspec.yaml                       # path deps on tom_build_base + tom_analyzer_shared
├── analysis_options.yaml              # include: ../analysis_options.yaml
├── README.md                          # this file
├── lib/
│   └── sumkit.dart                    # THE TOOL: definition + executor + runner
├── bin/
│   └── sumkit.dart                    # thin runnable entrypoint
└── example/
    ├── fixture.dart                   # builds the throwaway workspace (support code)
    ├── 01_the_cacheability_rule_example.dart
    ├── 02_resolving_dependencies_example.dart
    ├── 03_the_cache_directory_example.dart
    ├── 04_the_caching_payoff_example.dart
    ├── 05_scanning_a_workspace_example.dart
    ├── 06_nested_invocation_example.dart
    └── run_all_examples.dart          # runs every example, tallies, exits non-zero on failure
```

The four library pieces map to the two responsibilities the sample teaches:
`lib/sumkit.dart` is the **tool** (how `tom_build_base` turns a per-project scan
into a workspace walk), and it calls into **`tom_analyzer_shared`** for the cache
logic. Examples 01–04 exercise `tom_analyzer_shared` directly so you see the
moving parts; examples 05–06 run the assembled tool.

---

## The fixture: a *nested* workspace in a temp directory

`sumkit` reports on a tree of Dart projects, so every example builds a throwaway
workspace, runs against it, and deletes it. The builder lives in
`example/fixture.dart`. Each project gets **two** files for a reason:

- a **`pubspec.yaml`**, so the traversal recognises the folder as a Dart project
  (the tool filters on `DartProjectFolder`), and so build order can be computed
  from the path dependencies declared there;
- a **`pubspec.lock`**, so `DependencyResolver` has exact versions to classify.

The tree is shaped so each project says something different about caching:

```text
<temp>/
├── app/       app_runner    hosted: meta, collection, http   path: service_layer
├── service/   service_layer hosted: meta, collection         path: data_layer
├── data/      data_layer    hosted: meta
└── draft/     draft_pkg     pubspec.yaml only — NO pubspec.lock
```

- **`data_layer`** is a leaf: one cacheable dependency (`meta`), nothing else. It
  is processed first in build order, so warming it seeds `meta` for the projects
  that follow.
- **`service_layer`** shares `meta` with `data_layer` and adds `collection`; it
  also has one **uncacheable** path dependency (`data_layer`).
- **`app_runner`** shares `meta` + `collection` and adds `http`; its path
  dependency (`service_layer`) is likewise uncacheable. Because it depends on the
  others it is processed last — by which point the shared dependencies are
  already cached.
- **`draft_pkg`** has no `pubspec.lock`: its `dart pub get` has "not run", so a
  real generator could not analyse it yet. `sumkit` skips it cleanly rather than
  crashing.

Two deliberate constraints keep the sample deterministic:

1. **Only `hosted` and `path` sources appear — never `sdk`.** The resolver
   probes `flutter --version` to version SDK dependencies; with no SDK-source
   deps in the fixture, that probe's result is unused and the output is identical
   whether or not Flutter is installed.
2. **The cache lives inside the temp tree** (`<temp>/.tom/analyzer-cache/`), so
   `disposeFixture` removes it with everything else — no state leaks between
   examples.

The lock files are rendered by a small helper in `fixture.dart` that emits
exactly the shape `DependencyResolver` parses: a `packages:` map keyed by name,
each entry carrying a `source`, a `version`, and a source-specific
`description`.

---

## The tool: `sumkit` in three pieces

`lib/sumkit.dart` is the whole tool. It is a *single-command* tool — one
operation, invoked as `sumkit [options]`, not `sumkit :subcommand`. That makes
it the natural counterpart to the multi-command `relkit` from the previous
sample: same framework, the simpler shape.

### 1 · The definition — a `const` value

```dart
const sumkitTool = ToolDefinition(
  name: 'sumkit',
  description: 'Report analyzer-summary cache coverage for the Dart projects '
      'in a workspace (and optionally warm the cache).',
  version: '1.0.0',
  mode: ToolMode.singleCommand,
  requiredNatures: {DartProjectFolder},
  globalOptions: [
    OptionDefinition.flag(name: 'warm', description: '…'),
    OptionDefinition.flag(name: 'rebuild', description: '…'),
  ],
);
```

`mode: ToolMode.singleCommand` means the `commands` list is empty and there is
exactly one behaviour. `requiredNatures: {DartProjectFolder}` restricts the walk
to Dart projects, so the framework's traversal never even offers `sumkit` a
non-Dart folder. The two `globalOptions` are flags; the framework parses them
and surfaces their values in `args.extraOptions` (`'warm' → true` when present).

### 2 · The behaviour — one executor, two entry points

A single-command tool registers exactly one executor, under the key `'default'`.
`sumkit` supplies **both** entry points so the tool is nestable:

```dart
Map<String, CommandExecutor> sumkitExecutors(StringSink out) {
  Future<ItemResult> scan(CommandContext context, CliArgs args) =>
      _scan(context, args, out);

  return {
    'default': CallbackExecutor(
      onExecute: scan,                       // normal traversal
      onExecuteWithoutTraversal: (args) async {
        final cwd = Directory.current.path;  // --nested mode
        final context = CommandContext(
          fsFolder: FsFolder(path: cwd),
          natures: const [],
          executionRoot: cwd,
        );
        return ToolResult.fromItems([await scan(context, args)]);
      },
    ),
  };
}
```

`onExecute` runs once per project during a traversal. `onExecuteWithoutTraversal`
runs in `--nested` mode, where a host tool has already walked to a project and we
scan the current directory once. Both funnel through the same `_scan`, so a
`sumkit` report is identical standalone or nested. (Note that in nested mode the
framework attaches no detected natures — which is fine, because `_scan` reads
`pubspec.lock` from the context path directly and doesn't depend on a nature.)

### 3 · The scan — resolve, look up, report, optionally warm

`_scan` is the one function that cannot be supplied by the framework, and it is
worth reading in full because it is the entire integration between the two
libraries:

```dart
Future<ItemResult> _scan(CommandContext context, CliArgs args, StringSink out) async {
  final cache = SummaryCacheManager(context.executionRoot);
  if (args.extraOptions['rebuild'] == true) {
    await cache.clearCache();
  }

  final List<PackageDependency> deps;
  try {
    deps = await DependencyResolver().resolveVersionedDependencies(context.path);
  } on FileSystemException {
    out.writeln('${context.name}: skipped (no pubspec.lock)');
    return ItemResult.skipped(path: context.path, name: context.name, message: 'no pubspec.lock');
  }

  final set = DependencySet.from(deps);
  final missing = await cache.findMissingSummaries(set.cacheable);
  final hits = set.cacheable.length - missing.length;

  if (args.extraOptions['warm'] == true) {
    for (final dep in missing) {
      await cache.writeSummary(dep.name, dep.version, _placeholderSummary(dep));
    }
    out.writeln('${context.name}: warmed ${missing.length} '
        '($hits already cached, ${set.uncacheable.length} uncacheable)');
    return ItemResult.success(path: context.path, name: context.name, message: 'warmed ${missing.length}');
  }

  out.writeln('${context.name}: ${set.cacheable.length} cacheable, '
      '$hits cached, ${missing.length} missing (${set.uncacheable.length} uncacheable)');
  return ItemResult.success(path: context.path, name: context.name, message: '${missing.length} missing');
}
```

Three things are worth calling out:

- **The cache is keyed on `context.executionRoot`, not `context.path`.** That is
  deliberate: one cache per *workspace*, so projects that share a dependency
  share its summary. This is what makes warming `data_layer` (which needs `meta`)
  turn `meta` into a hit for every later project that also needs it.
- **A single-command tool prints its own body.** Unlike a multi-command tool —
  which renders a `>>> folder` tree from your `ItemResult`s — a single-command
  traversal prints no per-folder lines for you. So `_scan` writes its report
  line to the sink itself (the framework still renders the *summary* block:
  skipped and error counts).
- **The missing `pubspec.lock` is a domain condition, not an error.** A project
  whose dependencies aren't resolved yet is reported as *skipped*, not *failed* —
  exactly how a generator should treat a project it cannot analyse yet.

The placeholder is four lines:

```dart
Uint8List _placeholderSummary(PackageDependency dep) =>
    Uint8List.fromList('PLACEHOLDER-SUMMARY ${dep.cacheKey}\n'.codeUnits);
```

— the one stand-in described in [the boundary section](#what-is-real-here-and-what-is-a-stand-in).

---

## The examples

Six files, each a single concept, each ending with an `// expected output`
comment that matches what the example prints. Examples 01–04 use
`tom_analyzer_shared` directly (no traversal); 05–06 run the assembled tool.

The aggregator prints each example under a `=== name ===` header; the per-example
sections below show the body each one prints.

---

## 1 · The cacheability rule

[`01_the_cacheability_rule_example.dart`](example/01_the_cacheability_rule_example.dart)

The pure-data foundation. A summary is keyed by `name@version`, so it is only
worth caching when that pair is stable across machines and runs — true for
`hosted` and `sdk` sources, false for `path` and `git`.
`PackageDependency.isCacheable` encodes the rule; `DependencySet.from` applies it
to a whole list.

```dart
final deps = <PackageDependency>[
  const PackageDependency(name: 'meta', version: '1.16.0', source: 'hosted', hostedUrl: 'https://pub.dev'),
  const PackageDependency(name: 'collection', version: '1.19.1', source: 'hosted', hostedUrl: 'https://pub.dev'),
  const PackageDependency(name: 'flutter', version: '3.27.0', source: 'sdk', sdkName: 'flutter'),
  const PackageDependency(name: 'data_layer', version: '1.0.0', source: 'path', path: '../data'),
  const PackageDependency(name: 'local_fork', version: 'git', source: 'git'),
];

for (final dep in deps) {
  final mark = dep.isCacheable ? 'cacheable' : 'uncacheable';
  print('${dep.cacheKey.padRight(18)} ${dep.source.padRight(7)} $mark');
}

final set = DependencySet.from(deps);
print('cacheable:   ${set.cacheable.map((d) => d.name).join(', ')}');
print('uncacheable: ${set.uncacheable.map((d) => d.name).join(', ')}');
```

```text
meta@1.16.0        hosted  cacheable
collection@1.19.1  hosted  cacheable
flutter@3.27.0     sdk     cacheable
data_layer@1.0.0   path    uncacheable
local_fork@git     git     uncacheable
---
cacheable:   meta, collection, flutter
uncacheable: data_layer, local_fork
```

`hosted` and `sdk` land in `cacheable`; `path` and `git` land in `uncacheable`.
Everything downstream is built on this one rule.

---

## 2 · Resolving dependencies from a lock file

[`02_resolving_dependencies_example.dart`](example/02_resolving_dependencies_example.dart)

Cacheability needs exact versions, and the only place those live is
`pubspec.lock`. `DependencyResolver.resolveVersionedDependencies` parses that
file into `PackageDependency` values (sorted by name), and the list extensions
slice them. This resolves the fixture's `app` project — three hosted deps and
one path dep — straight from a real (fixture) lock file.

```dart
final deps = await DependencyResolver()
    .resolveVersionedDependencies('${workspace.path}/app');

print('resolved ${deps.length} dependencies (sorted by name):');
for (final dep in deps) {
  print('  ${dep.cacheKey.padRight(20)} ${dep.source}');
}
print('hosted:    ${deps.hosted.map((d) => d.name).join(', ')}');
print('paths:     ${deps.paths.map((d) => d.name).join(', ')}');
print('cacheable: ${deps.cacheable.map((d) => d.name).join(', ')}');
print('findByName(http): ${deps.findByName('http')?.cacheKey}');
```

```text
resolved 4 dependencies (sorted by name):
  collection@1.19.1    hosted
  http@1.2.2           hosted
  meta@1.16.0          hosted
  service_layer@1.2.0  path
hosted:    collection, http, meta
paths:     service_layer
cacheable: collection, http, meta
findByName(http): http@1.2.2
```

The resolver is the bridge from "a file on disk" to "typed dependencies the cache
can reason about." Note the path dependency (`service_layer`) is resolved and
listed, but it is *not* in `cacheable` — the rule from example 1, now applied to
real data.

---

## 3 · The cache directory, cold

[`03_the_cache_directory_example.dart`](example/03_the_cache_directory_example.dart)

`SummaryCacheManager` owns one cache per workspace, at
`<workspace>/.tom/analyzer-cache/`, with one `{name}@{version}.sum` file per
cached dependency. A "hit" is nothing more than that file existing and being
non-empty (`hasSummary`); `findMissingSummaries` runs that check over the
cacheable dependencies. Pointed at a fresh workspace — a **cold cache** —
everything is missing.

```dart
final cache = SummaryCacheManager(workspace.path);

print('cache file for meta@1.16.0: '
    '${p.basename(cache.getCachePath('meta', '1.16.0'))}');

final deps = await DependencyResolver()
    .resolveVersionedDependencies('${workspace.path}/service');
final cacheable = deps.cacheable;
final missing = await cache.findMissingSummaries(cacheable);

print('hasSummary(meta@1.16.0): ${await cache.hasSummary('meta', '1.16.0')}');
print('cacheable: ${cacheable.length}, missing: ${missing.length}');
print('missing names: ${missing.map((d) => d.name).join(', ')}');
print('cached summaries on disk: ${(await cache.getStats()).summaryCount}');
```

```text
cache file for meta@1.16.0: meta@1.16.0.sum
hasSummary(meta@1.16.0): false
cacheable: 2, missing: 2
missing names: collection, meta
cached summaries on disk: 0
```

`service`'s two cacheable dependencies (`collection`, `meta`) are both misses,
and the cache holds zero summaries. This is the cost a generator pays on a cold
run — and the next example removes it.

---

## 4 · The caching payoff

[`04_the_caching_payoff_example.dart`](example/04_the_caching_payoff_example.dart)

This is the whole point of the cache, in miniature. Take the `data` project (one
cacheable dependency, `meta`). Cold, it is a miss — the work a generator would
do. Write the summary once, and the next check reports zero missing: the
generator can load the summary instead of re-analysing the source. Run after run,
that miss never comes back (until the version, and the cache key, changes).

```dart
final cache = SummaryCacheManager(workspace.path);
final deps = await DependencyResolver()
    .resolveVersionedDependencies('${workspace.path}/data');
final cacheable = deps.cacheable;

final coldMissing = await cache.findMissingSummaries(cacheable);
print('cold:  ${coldMissing.length} missing '
    '(${coldMissing.map((d) => d.cacheKey).join(', ')})');

for (final dep in coldMissing) {
  await cache.writeSummary(dep.name, dep.version, _placeholder(dep));
}

final warmMissing = await cache.findMissingSummaries(cacheable);
print('warm:  ${warmMissing.length} missing');
print('hasSummary(meta@1.16.0): ${await cache.hasSummary('meta', '1.16.0')}');
print('cached summaries on disk: ${(await cache.getStats()).summaryCount}');
```

```text
cold:  1 missing (meta@1.16.0)
warm:  0 missing
hasSummary(meta@1.16.0): true
cached summaries on disk: 1
```

Cold: one miss. Write one summary. Warm: zero misses, one summary on disk. That
transition — repeated across every cacheable dependency of every project — is the
time a real generator saves. (The bytes written here are the labelled
placeholder; see [the boundary section](#what-is-real-here-and-what-is-a-stand-in).)

---

## 5 · Scanning a workspace with the tool

[`05_scanning_a_workspace_example.dart`](example/05_scanning_a_workspace_example.dart)

Examples 01–04 used the libraries directly; this one runs the assembled tool.
`sumkitRunner` walks the fixture in build order (leaves first), and its
single-command executor writes one report line per project. `draft` has no
`pubspec.lock`, so it is skipped. Three passes tell the cold→warm story against
one shared cache.

```dart
Future<String> scan(List<String> extra) async {
  final out = StringBuffer();
  await sumkitRunner(output: out).run([
    '-R', workspace.path, '--scan', workspace.path, '-r', ...extra,
  ]);
  return out.toString().trimRight();
}

print('--- cold scan ---');
print(await scan(const []));
print('--- warm the cache ---');
print(await scan(const ['--warm']));
print('--- scan again (warm) ---');
print(await scan(const []));
```

```text
--- cold scan ---
data: 1 cacheable, 0 cached, 1 missing (0 uncacheable)
draft: skipped (no pubspec.lock)
service: 2 cacheable, 0 cached, 2 missing (1 uncacheable)
app: 3 cacheable, 0 cached, 3 missing (1 uncacheable)
--- warm the cache ---
data: warmed 1 (0 already cached, 0 uncacheable)
draft: skipped (no pubspec.lock)
service: warmed 1 (1 already cached, 1 uncacheable)
app: warmed 1 (2 already cached, 1 uncacheable)
--- scan again (warm) ---
data: 1 cacheable, 1 cached, 0 missing (0 uncacheable)
draft: skipped (no pubspec.lock)
service: 2 cacheable, 2 cached, 0 missing (1 uncacheable)
app: 3 cacheable, 3 cached, 0 missing (1 uncacheable)
```

Read the **`--warm`** block top to bottom and you can see the shared cache pay
off. `data` warms `meta` with **0 already cached**. By the time the walk reaches
`service`, `meta` is a hit, so its `already cached` count is **1** — only
`collection` is new. By `app`, both `meta` and `collection` are hits, so
`already cached` is **2** and only `http` is new. One summary per dependency,
shared across every project that needs it, exactly because the cache is keyed on
the workspace root and not the project.

The third pass confirms the steady state: every project reports **0 missing** —
the all-hits report a generator gets on every run after the first. (Report lines
key on the *folder* name — `data`, `service`, `app` — which is what
`CommandContext.name` carries; the package names live inside each `pubspec.yaml`.)

---

## 6 · Nested invocation

[`06_nested_invocation_example.dart`](example/06_nested_invocation_example.dart)

`--nested` is how a tool runs *inside* another tool's traversal: the host has
already walked to a project directory, so the nested tool skips its own walk and
reports the current working directory once. A single-command tool makes this work
by supplying `onExecuteWithoutTraversal`; `sumkit` builds a one-off context for
the cwd and runs the same scan, so a nested report is identical to a standalone
one. You get a `ToolResult` back to render yourself — no per-folder output.

```dart
Directory.current = Directory('${workspace.path}/data');

final out = StringBuffer();
final result = await sumkitRunner(output: out).run(['--nested']);

print('report line: ${out.toString().trim()}');
print('processed:   ${result.processedCount}');
print('success:     ${result.success}');
```

```text
report line: data: 1 cacheable, 0 cached, 1 missing (0 uncacheable)
processed:   1
success:     true
```

One project, one report line, no traversal tree. In nested mode the cache root is
the cwd, so the lookup happens under `data/.tom/` — which the fixture cleanup
removes with everything else. This is the mechanism that lets one `sumkit` work
both standalone (its own walk) and as a step inside a larger tool's walk, with no
change to the scan logic.

---

## How this sample stays hermetic

Every example runs offline and deterministically, by construction:

- **No network, no pub cache, no analyzer.** The only real I/O is reading and
  writing files inside a temp directory. The summary *bytes* are a placeholder;
  the real generation path (`runSummaryCacheStage`) is referenced but never run.
- **No `sdk`-source dependencies.** The resolver's `flutter --version` probe is
  therefore irrelevant to output — the sample produces the same lines with or
  without a Flutter SDK installed.
- **The cache lives inside the fixture.** It is created under
  `<temp>/.tom/analyzer-cache/` (or `<project>/.tom/` in nested mode) and removed
  by `disposeFixture`, so no example leaves state behind for the next one.
- **Fixed-content placeholders.** Each placeholder's bytes are derived from the
  dependency's cache key, so file presence and counts are reproducible.

This is why `run_all_examples.dart` is also the verifier: every example is
self-contained, so running them all and checking the tally is a complete,
repeatable smoke test.

---

## Concept reference

| Concept | Type / member | Where it shows up |
| ------- | ------------- | ----------------- |
| Cacheability rule | `PackageDependency.isCacheable` | Example 1 |
| Cache key | `PackageDependency.cacheKey` (`name@version`) | Examples 1, 4 |
| Partition by cacheability | `DependencySet.from` → `.cacheable` / `.uncacheable` | Examples 1, 5 |
| Resolve exact versions | `DependencyResolver.resolveVersionedDependencies` | Examples 2–4, tool |
| Slice a dependency list | `.hosted` / `.paths` / `.cacheable` / `.findByName` | Example 2 |
| Cache location | `SummaryCacheManager` → `<root>/.tom/analyzer-cache/` | Examples 3–5 |
| Cache-file path | `getCachePath(name, version)` | Example 3 |
| Hit check | `hasSummary` / `findMissingSummaries` | Examples 3–5 |
| Fill the cache | `writeSummary` | Examples 4–5 |
| Cache stats | `getStats().summaryCount` | Examples 3, 4 |
| Clear the cache | `clearCache` (`--rebuild`) | tool |
| Single-command tool | `ToolDefinition(mode: ToolMode.singleCommand)` | tool, Example 5 |
| Dart-only traversal | `requiredNatures: {DartProjectFolder}` | tool |
| Custom flags | `OptionDefinition.flag` → `args.extraOptions` | tool |
| Nestable executor | `onExecuteWithoutTraversal` + `--nested` | tool, Example 6 |
| Skip vs fail | `ItemResult.skipped` for an unresolved project | tool, Example 5 |
| Real generation path | `runSummaryCacheStage` (prose only) | boundary section |

---

## Where to go next

- **The cache, in full.** [`tom_analyzer_shared`](../../tom_analyzer_shared/)
  documents the production path — `runSummaryCacheStage`, real summary
  generation, SDK summaries — that this sample stands in for.
- **The tool framework.** [`tom_build_base`](../../tom_build_base/) is the full
  manual for `ToolDefinition`, traversal, options, and `ToolResult`.
- **The multi-command shape.** The
  [advanced sample](../tom_build_base_advanced_sample/) builds `relkit`, a tool
  with several `:commands` under one definition — the counterpart to `sumkit`'s
  single command.
- **The starting point.** The
  [introduction sample](../tom_build_base_introduction_sample/) builds the
  simplest possible tool, if any of the framework mechanics here felt assumed.
- **The whole set.** [`tom_basics_samples`](../) is the canonical home for these
  runnable samples; its aggregator runs `sumkit`'s examples as part of the suite.
