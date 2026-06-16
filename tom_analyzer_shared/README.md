# tom_analyzer_shared

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause, see [LICENSE](LICENSE).

Shared analyzer-summary caching infrastructure reused by Tom code generators
(reflection, d4rt bridges, …).

Every tool that builds on the Dart `analyzer` package pays the same tax: before
it can look at *your* code, the analyzer must resolve and analyse *all of your
dependencies* — Flutter, `provider`, `meta`, the SDK itself. For a code
generator that runs repeatedly, re-analysing the same stable packages on every
run is pure waste. `tom_analyzer_shared` removes that waste by building analyzer
**summaries** (`.sum` files) for the dependencies whose versions cannot change
between runs, caching them in a shared workspace directory, and handing the
paths back so the analyzer loads pre-digested type information instead of
re-scanning sources.

It was extracted from `tom_reflection_generator` so that more than one
generator could share one cache, and it is consumed today by both the
reflection generator and the d4rt bridge generator.

---

## Overview

The analyzer can be told, when it constructs an analysis context, "here are some
pre-built summaries — trust them instead of reading these packages from source":

```dart
AnalysisContextCollectionImpl(
  includedPaths: [projectRoot],
  sdkSummaryPath: ...,        // a prebuilt SDK summary
  librarySummaryPaths: ...,   // prebuilt package summaries
);
```

The hard part is producing those summaries correctly: knowing *which* packages
are safe to cache, locating their sources in the pub cache and the SDK, building
each summary **after** the summaries it depends on, and storing them under a
stable, version-keyed name so the next run finds them. `tom_analyzer_shared`
owns that pipeline:

```text
pubspec.lock ──▶ DependencyResolver ──▶ which deps are cacheable?
                                          │  (hosted + SDK = stable versions)
                                          ▼
                 SummaryGenerator ──▶ build SDK summary, then each package
                                          │  summary in topological order
                                          ▼
                 SummaryCacheManager ──▶ <workspace>/.tom/analyzer-cache/
                                          │  {package}@{version}.sum
                                          ▼
            SummaryCacheResult { summaryPaths, sdkSummaryPath } ──▶ analyzer
```

The whole pipeline is wrapped by one function — `runSummaryCacheStage` — that a
CLI tool calls once and then feeds the result straight into its analysis
context. The individual stages are public too, for tools that need finer
control.

### Why only some dependencies are cached

A summary is keyed by `{package}@{version}`. That key is only trustworthy when
the version pins the *content* — which is true for **hosted** (pub.dev) and
**SDK** packages, and false for **path** and **git** dependencies, whose files
can change without the version changing. So `tom_analyzer_shared` caches hosted
and SDK packages and leaves path/git dependencies to be analysed from source
every run. This is the single rule encoded in `PackageDependency.isCacheable`.

---

## Installation

```yaml
dependencies:
  tom_analyzer_shared: ^0.1.0
```

Or from the command line:

```sh
dart pub add tom_analyzer_shared
```

Then import the single entry point:

```dart
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';
```

Requires Dart SDK `^3.10.4`. It depends on `analyzer`, `path`, and `yaml`. It is
a `dart:io` package (it reads `pubspec.lock`, the pub cache, and the SDK), so it
runs on desktop, server, and CLI hosts.

---

## Features

| API | Kind | Purpose |
| --- | --- | --- |
| `runSummaryCacheStage` | function | The one-call orchestration entry point used by CLI tools |
| `SummaryCacheResult` | class | The returned `summaryPaths` + `sdkSummaryPath`, ready for the analyzer |
| `DependencyResolver` | class | Parses `pubspec.lock`; resolves hosted/SDK source locations |
| `PackageDependency` | class | One resolved dependency: name, version, source, cacheability |
| `DependencySet` | class | Dependencies split into `cacheable` / `uncacheable` |
| `DependencyListExtensions` | extension | `hosted` / `sdk` / `paths` / `cacheable` / `findByName` |
| `SummaryGenerator` | class | Builds the SDK summary and per-package summaries in topological order |
| `SummaryGenerationResult` | class | Counts of generated / skipped / failed + per-package errors |
| `SummaryCacheManager` | class | Reads/writes `.sum` files; cache paths, stats, cleanup |
| `CacheStats` | class | Cache directory size and file count |

---

## Quick start

Most callers need exactly one function. Resolve, generate what's missing, and
get the paths to hand to the analyzer:

```dart
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

Future<void> analyse(String projectRoot) async {
  final result = await runSummaryCacheStage(projectRoot, verbose: true);

  final collection = AnalysisContextCollectionImpl(
    includedPaths: [projectRoot],
    sdkSummaryPath: result?.sdkSummaryPath,
    librarySummaryPaths: result?.summaryPaths ?? const [],
  );
  // … use `collection` to analyse the project's own sources …
}
```

`runSummaryCacheStage` resolves dependencies from `pubspec.lock`, builds any
summaries not already in `<projectRoot>/.tom/analyzer-cache/`, and returns a
`SummaryCacheResult`. On the first run it generates the cache; on later runs it
finds everything present and returns immediately. It returns `null` when no
dependencies could be resolved or no summaries are available, so the
null-aware `result?.…` is the intended usage.

---

## Example projects

> This package is consumed *inside* code-generator CLIs rather than run
> standalone, so it ships no `example/` program. A worked
> `tom_build_base_advanced_analyzer_sample` — a small traversal-driven tool
> that calls `runSummaryCacheStage` per project and reports cache hits — is
> planned under `../tom_basics_samples/`. Until it lands, the
> [usage](#usage) sections below and the consumers named under
> [ecosystem](#ecosystem) are the reference.

---

## Usage

### The one-call stage

`runSummaryCacheStage` takes the project root and a handful of optional flags
that mirror what a generator CLI exposes:

```dart
final result = await runSummaryCacheStage(
  projectRoot,
  verbose: true,                 // detail each generated/failed package
  rebuildCache: false,           // true → clear the cache first
  showCacheStatus: false,        // true → print status and return null
  cacheOnlyPackages: const [],   // non-empty → only these packages
  log: print,                    // redirect output (defaults to print)
);
```

- `rebuildCache` clears `<root>/.tom/analyzer-cache/` before generating — use it
  when a summary may be stale (e.g. after an SDK upgrade).
- `showCacheStatus` prints a per-package CACHED/MISSING report and returns
  `null` without doing heavy work — the implementation behind a `--cache-status`
  flag.
- `cacheOnlyPackages` narrows generation to named packages for targeted
  rebuilds.
- `log` redirects the human-readable progress lines to your own sink.

### Resolving dependencies

When you need the dependency list itself — to inspect it, filter it, or drive a
custom generation — use `DependencyResolver`. It parses `pubspec.lock` and
classifies every entry:

```dart
final resolver = DependencyResolver();
final deps = await resolver.resolveVersionedDependencies(projectRoot);

for (final dep in deps) {
  print('${dep.cacheKey}  source=${dep.source}  cacheable=${dep.isCacheable}');
}
```

A `PackageDependency` carries the `name`, exact `version`, `source` (`hosted`,
`sdk`, `path`, `git`), and the source-specific extras (`hostedUrl`, `sdkName`,
`path`). Its two derived members are the heart of the package:

- `isCacheable` — `true` only for `hosted` and `sdk` sources.
- `cacheKey` — `'{name}@{version}'`, the cache file stem.

```dart
const dep = PackageDependency(name: 'provider', version: '6.1.2', source: 'hosted');
print(dep.isCacheable); // true
print(dep.cacheKey);    // provider@6.1.2
```

`DependencySet.from(deps)` splits a list into `cacheable` / `uncacheable`, and
the `DependencyListExtensions` give you focused views:

```dart
final set = DependencySet.from(deps);
print(set.cacheable.length);        // hosted + sdk
print(deps.hosted.map((d) => d.name));  // hosted only
print(deps.findByName('flutter')?.cacheKey);
```

### The cache directory

`SummaryCacheManager` owns `<workspace>/.tom/analyzer-cache/` and the file
naming. You construct it with the workspace root and ask it for paths or status
— it never guesses a layout the analyzer can't find:

```dart
final cache = SummaryCacheManager(projectRoot);

print(cache.cacheDirectory);                       // …/.tom/analyzer-cache
print(cache.getCachePath('provider', '6.1.2'));    // …/provider@6.1.2.sum
print(cache.getSdkSummaryPath());                  // …/sdk@<dart-version>.sum

final stats = await cache.getStats();              // CacheStats
print('${stats.summaryCount} files, ${stats.totalSizeMB.toStringAsFixed(1)} MB');
```

It also offers `hasSummary`, `findMissingSummaries`, `loadSummary`,
`clearCache`, `cleanOutdated`, and `cleanUnusedSummaries` for tools that manage
the cache lifecycle directly.

### Generating summaries directly

`SummaryGenerator` is the engine `runSummaryCacheStage` drives. Use it directly
when you want to control SDK-vs-package ordering or capture per-package errors:

```dart
final generator = SummaryGenerator(
  cacheManager: cache,
  dependencyResolver: resolver,
);

await generator.generateSdkSummary();              // dart:core / dart:ui first

final cacheable = await resolver.resolveCacheableDependencies(projectRoot);
final result = await generator.generateMissingSummaries(
  cacheable,
  onProgress: (pkg, current, total) => print('  ($current/$total) $pkg'),
);

print('generated=${result.generated} skipped=${result.skipped} '
    'failed=${result.failed} total=${result.total}');
for (final entry in result.errors.entries) {
  print('  ${entry.key}: ${entry.value}');         // why a package failed
}
```

The SDK summary is built **first** because package summaries resolve `dart:core`
(and, under Flutter, `dart:ui`) from it. Package summaries are then built in
**topological order** so each can reference its dependencies' summaries. A
single package failing to summarise is recorded in `errors` and does not abort
the rest — the analyzer simply falls back to analysing that one from source.

---

## Architecture

```text
package:tom_analyzer_shared/tom_analyzer_shared.dart   (single entry point)
        │
        ├── runSummaryCacheStage()  ── orchestration ──┐
        │        returns SummaryCacheResult            │
        │                                              ▼
        ├── DependencyResolver  ── pubspec.lock ──▶ List<PackageDependency>
        │        resolveVersionedDependencies / resolveCacheableDependencies
        │        getHostedPackagePath / getSdkPackagePath / getFlutterSdkPath
        │
        ├── SummaryGenerator  ── generateSdkSummary / generateMissingSummaries
        │        topological order ──▶ SummaryGenerationResult
        │
        └── SummaryCacheManager  ── <workspace>/.tom/analyzer-cache/
                 getCachePath / getSdkSummaryPath / getStats / clearCache
```

| Type | Role |
| --- | --- |
| `runSummaryCacheStage` | One-call stage: resolve → generate missing → return paths |
| `SummaryCacheResult` | `summaryPaths` + `sdkSummaryPath` for the analysis context |
| `DependencyResolver` | Parses `pubspec.lock`; locates hosted/SDK sources |
| `PackageDependency` | One resolved dependency (`isCacheable`, `cacheKey`) |
| `DependencySet` | Cacheable / uncacheable partition of a dependency list |
| `SummaryGenerator` | Builds SDK + package summaries, topologically ordered |
| `SummaryGenerationResult` | generated / skipped / failed counts + error map |
| `SummaryCacheManager` | The `.sum` cache directory: paths, stats, cleanup |
| `CacheStats` | Cache file count and total size |

The cache is keyed purely by package name and version, so it is safe to share
across tools and across runs: two generators pointed at the same workspace reuse
each other's summaries, and nothing in the key depends on which tool wrote it.

---

## Ecosystem

`tom_analyzer_shared` is the analyzer-tooling member of the
[`tom_ai/basics`](../) foundation layer. Its consumers are Tom's code
generators, which all need a resolved analysis context fast:

- **`tom_reflection_generator`** — generates reflection metadata; the package
  was originally extracted from it.
- **`tom_d4rt_generator`** — generates d4rt bridge classes for native Dart APIs.

Both declare `tom_analyzer_shared` as a dependency and call
`runSummaryCacheStage` so they share one `.tom/analyzer-cache/` directory per
workspace. Adding a third generator is a matter of the same one-call stage — the
cache it shares is already there.

Sibling foundation packages:
[`tom_basics`](../tom_basics/) ·
[`tom_basics_console`](../tom_basics_console/) ·
[`tom_basics_network`](../tom_basics_network/) ·
[`tom_build_base`](../tom_build_base/).

---

## Further documentation

- [`../README.md`](../README.md) — the `tom_ai/basics` package map.
- The `analyzer` package's `AnalysisContextCollectionImpl` is the consumer of
  this package's output; its `sdkSummaryPath` / `librarySummaryPaths` parameters
  are what `SummaryCacheResult` is built to fill.

---

## Status

- **Version:** 0.1.0
- **Tests:** a `test/summary/` suite covering dependency resolution, the cache
  manager, summary generation, and an end-to-end integration test
  (`dart test` / `testkit :test`).
- **Analysis:** clean under `package:lints` (`dart analyze` — no issues).
- **Platforms:** any Dart runtime with `dart:io` (desktop, server, CLI).
