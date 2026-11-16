# Tom Analyzer Shared — User Guide

Tom Analyzer Shared builds, caches and hands out **analyzer summaries** for the
dependencies of a Dart project, so that a tool built on the Dart `analyzer`
package does not analyse the same stable packages from source on every run. It
is used by the Tom code generators (Tom Reflection Generator, D4rt Generator)
and by tools that ship a summary of their own.

This guide explains the concepts, the main API, how the cache is laid out and
kept correct, and the limits. The [README](../README.md) gives the overview
and installation. The runnable
[example](../example/tom_analyzer_shared_example.dart) creates a small project
in a temporary directory and walks through dependency resolution, the cache
layout, fingerprints, a grouped bundle build and summary stamps.

## Contents

- [Concepts](#concepts)
- [The one-call stage](#the-one-call-stage)
- [Resolving dependencies](#resolving-dependencies)
- [Where the cache lives](#where-the-cache-lives)
- [The summary cache](#the-summary-cache)
- [Generating summaries](#generating-summaries)
- [Grouped package bundles](#grouped-package-bundles)
- [Summary stamps](#summary-stamps)
- [Locating the SDK and Flutter's embedder](#locating-the-sdk-and-flutters-embedder)
- [Cleaning up: `analyzer_cache_gc`](#cleaning-up-analyzer_cache_gc)
- [Errors and limits](#errors-and-limits)

## Concepts

| Term | Meaning |
| ---- | ------- |
| **Summary** (`.sum`) | A binary bundle of analysed type information for a set of libraries, written by the analyzer. An analysis context given summaries reads types from them instead of parsing and resolving the sources. |
| **SDK summary** | A summary of the `dart:` libraries; with Flutter's embedder it also holds `dart:ui`. Package summaries are linked against it. |
| **Package summary** | A summary of one package's `lib/` libraries, one file per package, version and dependency closure. |
| **Cacheable dependency** | A `hosted` (pub.dev or another pub server) or `sdk` dependency. Its version fixes its content, so its summary can be reused. `path` and `git` dependencies are not cacheable and are always analysed from source. |
| **Dependency closure** | The set of cacheable packages a package transitively depends on, each with its resolved version. A package summary is only valid together with the closure it was linked against. |
| **Fingerprint** | A text naming the fingerprint format and the sorted `name@version` list of a package's closure. Its hash is part of the summary's file name. |
| **Tool cache** | A workspace-local directory, normally `<workspace>/.tom/`, where Tom tools keep reusable artefacts. Summaries live in its `analyzer-cache/` sub-directory. |
| **Partition** | `analyzer-cache/<analyzer-major>/<dart-sdk>+d<data-version>/`: the folder for summaries written by one toolchain. A summary is only readable by the analyzer that wrote it, so each toolchain has its own partition. |

## The one-call stage

`runSummaryCacheStage` is what most tools need. Given a project folder, it
resolves the dependencies, builds whatever is missing and returns the paths to
pass to the analyzer:

```dart
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

final result = await runSummaryCacheStage(projectRoot);
final collection = AnalysisContextCollectionImpl(
  includedPaths: [projectRoot],
  sdkSummaryPath: result?.sdkSummaryPath,
  librarySummaryPaths: result?.summaryPaths ?? const [],
);
```

What it does, in order:

1. Reads `pubspec.lock` (and `.dart_tool/package_config.json`) with
   `DependencyResolver`. If that fails, it logs a warning and returns `null`.
2. Keeps the cacheable dependencies, narrowed to `cacheOnlyPackages` when that
   list is not empty.
3. With `showCacheStatus: true`, prints the cache directory, its size, the Dart
   SDK version and one `[CACHED]` / `[MISSING]` line per dependency, then
   returns `null` without building anything.
4. With no cacheable dependency, returns `null`.
5. With `rebuildCache: true`, deletes every file of the current partition.
6. Builds the SDK summary if it is missing.
7. Computes each package's closure fingerprint, finds the summaries that are
   missing and builds them in dependency order. Packages that fail are named
   in the log with their error; the stage carries on.
8. Collects the summaries that now exist, marks each as used (sets its
   modification time, which protects it from cleanup), and returns them.

The result is a `SummaryCacheResult`:

| Field | Meaning |
| ----- | ------- |
| `summaryPaths` | The package summaries, or `null` when there are none. Never an empty list. |
| `sdkSummaryPath` | The SDK summary, or `null` when it could not be built. |
| `isEmpty` | Both are `null`. |

The stage returns `null` instead of an empty result, so callers write
`result?.…` as above. Progress lines go to `log` (default `print`); `verbose:
true` adds one line per summary used. `cacheManager` replaces the default
`SummaryCacheManager`, for example to keep a test's cache in a temporary
directory.

A package without a summary is simply analysed from source by the caller, so a
failed or skipped summary costs time, not correctness.

## Resolving dependencies

```dart
final resolver = DependencyResolver();
final deps = await resolver.resolveVersionedDependencies(projectRoot);
```

`resolveVersionedDependencies` parses `<projectRoot>/pubspec.lock` and returns
one `PackageDependency` per entry, sorted by name:

| Lock `source` | `version` | Extras |
| ------------- | --------- | ------ |
| `hosted` | the locked version | `hostedUrl` (default `https://pub.dev`) |
| `sdk` | for `flutter` SDK packages: the Flutter framework version from `flutter --version --machine` (`0.0.0` when Flutter is not found); for `dart` SDK packages: the running Dart version | `sdkName` (`flutter` or `dart`) |
| `path` | the locked version | `path`, made absolute against `projectRoot` when relative |
| `git` | the locked version, or `git` | — |

Entries without a version (hosted, path) or with an unknown source are skipped.
It throws a `FileSystemException` when `pubspec.lock` is missing; run `dart pub
get` first. A lock file without a `packages:` section gives an empty list.

Related members:

| Member | Purpose |
| ------ | ------- |
| `resolveCacheableDependencies(root)` | Only the hosted and SDK entries. |
| `resolveDependencySet(root)` | A `DependencySet` with `cacheable`, `uncacheable` and `all`. |
| `getHostedPackagePath(dep)` | Where a hosted package's sources are. |
| `getSdkPackagePath(dep)` | Where a Flutter SDK package's sources are. |
| `getFlutterSdkPath()` | `FLUTTER_ROOT`, else the folder of `flutter` on `PATH`. |
| `packageRootFromConfig(name)` | The root recorded in the last project's `package_config.json`. |

Package locations come first from the project's
`.dart_tool/package_config.json`, which pub writes for every platform and pub
cache setting. Only when a package is not listed there does the resolver guess:
`$PUB_CACHE` (else `~/.pub-cache`, or `%LOCALAPPDATA%\Pub\Cache` on Windows)
for hosted packages, and the Flutter SDK's `packages/` or `bin/cache/pkg/` for
SDK packages. Dart SDK packages are not located.

`PackageDependency` itself is a plain value: `isCacheable` is `true` for
`hosted` and `sdk`, `cacheKey` is `name@version`, and equality uses name,
version and source. The `DependencyListExtensions` on `List<PackageDependency>`
give `hosted`, `sdk`, `paths`, `cacheable` and `findByName(name)`.

## Where the cache lives

`ToolCacheLocator.resolve` decides the tool-cache root. The first rule that
applies wins:

1. The `TOM_TOOL_CACHE` environment variable, when it is set and not blank.
2. The `.tom` folder of the nearest ancestor of the start directory that holds
   `buildkit_master.yaml` (the workspace root).
3. `<start directory>/.tom`.

```dart
final root = ToolCacheLocator.resolve(startDirectory: projectRoot);
```

It never chooses a machine-wide location such as `~/.config`, and it does not
create anything; the folder is created when the first summary is written. Pass
`environment:` to resolve against another environment than the process's.

Because rule 2 looks for the workspace root rather than the nearest `.tom`,
every project of a workspace shares one cache.

## The summary cache

`SummaryCacheManager(workspaceRoot)` owns one partition:

```text
<tool cache>/analyzer-cache/<analyzer-major>/<dart-sdk>+d<data-version>/
    sdk@<dart-sdk>.sum
    <package>@<version>+<closure-hash>.sum
```

- `<analyzer-major>` is `analyzerMajorVersion`, the analyzer major this package
  is built against (14).
- `<dart-sdk>+d<data-version>` is `currentToolchainKey()`: the running Dart SDK
  version and the linked analyzer's `AnalysisDriver.DATA_VERSION`
  (`analyzerDataVersion`), for example `3.13.7+d752`. The analyzer raises the
  data version whenever its stored format changes, so this is the exact key of
  the summary format.
- `<closure-hash>` is `SummaryCacheManager.closureHash(fingerprint)`: the first
  16 hex digits of the SHA-256 of the package's fingerprint.

A toolchain change therefore starts in an empty partition, and a change of any
version in a package's closure gives the package a new file name. No summary is
ever read by the wrong analyzer or against the wrong closure, and no run deletes
a summary another run might be reading.

| Member | Purpose |
| ------ | ------- |
| `cacheDirectory` | The partition folder. |
| `getCachePath(name, version, fingerprint:)` | The file name of a package summary. |
| `getSdkSummaryPath()` / `hasSdkSummary()` | The SDK summary. |
| `hasSummary(name, version, fingerprint:)` | The file exists and is not empty. |
| `findMissingSummaries(deps, fingerprints:)` | The cacheable dependencies without a summary. |
| `writeSummary(…)` / `writeSdkSummary(bytes)` | Write through a temporary file of the writer's own and a rename, so readers see a whole file or none. |
| `loadSummary(…)` | A `PackageBundleReader`, or `null`; a file that cannot be read is deleted. |
| `loadSummaries(deps, fingerprints:)` | A `SummaryDataStore` with every available summary. |
| `markUsed(path)` | Sets the file's modification time to now. |
| `listCachedSummaries()` | File stem to path for every `.sum` in the partition. |
| `getStats()` | A `CacheStats` with `summaryCount`, `totalSizeBytes`, `totalSizeMB`. |
| `clearCache()` | Deletes every file of the partition. |

Constructor options: `cacheDirectory:` uses a fixed folder and skips the
locator; `environment:` is passed to the locator; `dartSdkVersion:`,
`analyzerMajor:` and `analyzerDataVersion:` select another partition and are
meant for tests.

## Generating summaries

`SummaryGenerator` does the analysis work behind the stage:

```dart
final generator = SummaryGenerator(
  cacheManager: cache,
  dependencyResolver: resolver,
);
await generator.generateSdkSummary();
final deps = await resolver.resolveCacheableDependencies(projectRoot);
final result = await generator.generateMissingSummaries(
  deps,
  sdkSummaryPath: cache.getSdkSummaryPath(),
  onProgress: (pkg, current, total) => print('($current/$total) $pkg'),
);
print(result); // SummaryGenerationResult(generated: …, skipped: …, failed: …)
```

- `generateSdkSummary()` returns `false` when the SDK summary exists. It
  includes `dart:ui` when a Flutter SDK is found.
- `generateMissingSummaries` builds a dependency graph from each package's
  `pubspec.yaml` `dependencies:`, restricted to the cacheable set, and builds
  the summaries leaves first, so each package is linked with its dependencies'
  summaries. Existing summaries count as `skipped`; failures are counted in
  `failed` and described in `errors` (package name to message); the batch never
  stops at one failure.
- `generateSummary(dep, …)` builds one package.
- `computeDependencyFingerprints(deps)` returns the fingerprint per package;
  `buildDirectDependencyGraph(deps)` the graph; the static
  `dependencyClosure(graph, name)` the closure of one package.

A package summary is refused, not written, when it would be incomplete: a
library under `lib/` that does not resolve or is missing from the bundle, or an
import of the package's own or a declared dependency's library that cannot be
resolved. That raises `IncompleteSummaryException` (`packageName`, `version`,
`problems`), which `generateMissingSummaries` records in `errors`. An
incomplete summary would load without complaint and make some types silently
invalid for its reader; leaving it out means the package is analysed from
source instead.

Each package is analysed with an empty analysis-options file, so a package's
own `analyzer: exclude:` settings cannot leave libraries out of its summary.

## Grouped package bundles

`GroupedPackageBundleBuilder` writes one summary covering every package
reachable from one or more resolved package folders. This is what an embedded
Dart editor loads to analyse code without the SDK sources:

```dart
final bundle = await GroupedPackageBundleBuilder().buildFromDirs(
  ['path/to/app'],
  onLog: print,
);
File('packages.sum').writeAsBytesSync(bundle.bytes);
print(summaryLibraryUris(bundle.bytes)); // the library URIs it holds
```

- Each folder must have a `.dart_tool/package_config.json`;
  `mergePackageRootsForDirs` merges them (a later folder wins on a name
  collision) and throws `SummaryConfigException` when one is missing.
  `readPackageRoots(file)` reads a single config.
- Every `.dart` file under each package's `lib/`, including `lib/src/`, is a
  library of the bundle, addressed by `package:` URIs so the bundle is portable.
- `buildFromPackageRoots(roots)` takes an already merged name-to-root map.
- `sdkPath:` overrides the SDK location (default `resolveDartSdkPath()`).
- For Flutter packages the bundle is linked against the SDK with Flutter's
  embedder libraries (`dart:ui`, …), taken from `embedderYamlPath:` or from the
  `sky_engine` package among the roots. The result names it in
  `embedderYamlPath`; build the SDK summary read with this bundle with the same
  embedder, or the `dart:ui` types Flutter re-exports are undefined.

The result, `GroupedPackageBundle`, has `bytes`, `packageCount`,
`libraryCount` and `embedderYamlPath`. It throws `SummaryConfigException` when
no SDK is found or there is no library to summarise.

## Summary stamps

A tool that keeps one summary file of its own (for example an SDK summary it
ships) records what wrote it in a stamp file beside it, `<summary>.stamp`:

```text
# Written with the summary beside it; it is rebuilt when this differs.
toolchain: 3.13.7+d752
dart-ui: yes
```

```dart
final stamp = SummaryStamp.current(embedderYamlPath: embedder);
if (!stamp.isCurrentFor(summaryPath)) {
  // rebuild the summary, then:
  stamp.writeFor(summaryPath);
}
```

`isCurrentFor` is true only when the summary exists and its stamp equals this
one; a summary without a stamp, or with a stamp that cannot be read, counts as
stale. `dartUi` records whether Flutter's embedder was used, not its path, so a
committed stamp is valid on every machine. `SummaryStamp.readFor`, `decode`,
`encode` and `fileFor` give access to the parts.

`analyzerDataVersionInPackageRoots(roots)` reads the data version of the
analyzer another set of packages resolves (for example an application that
loads summaries this tool writes), so a tool can check that the reader can read
them.

## Locating the SDK and Flutter's embedder

`resolveDartSdkPath()` finds the Dart SDK for analyzer work, which matters in
compiled tools: the analyzer's default looks next to the running executable,
which for a `dart compile exe` binary is the tool itself. It tries, in order,
`DART_SDK`, `DART_HOME`, the running executable, `dart` on `PATH` (following
symlinks and Flutter's wrapper) and `flutter` on `PATH`; every candidate must
pass `looksLikeDartSdk(dir)` (it has `lib/_internal/allowed_experiments.json`).
The result is cached for the process; `null` means "let the analyzer decide".

For Flutter: `flutterEmbedderYamlInSdk(flutterSdkPath)` and
`flutterEmbedderYamlInPackageRoots(roots)` find `sky_engine/lib/_embedder.yaml`;
`dartSdkWithEmbedder(resourceProvider, sdkPath:, embedderYamlPath:)` returns the
SDK with the embedder's libraries added; `summaryLibraryUris(bytes)` lists a
summary's libraries, for example to check that an SDK summary holds `dart:ui`.

## Cleaning up: `analyzer_cache_gc`

Nothing deletes cache files automatically. Old partitions (from SDKs or
analyzers no longer used) and summaries of closures no project resolves any
more stay until someone removes them. The package's command-line tool does
that on request:

```text
analyzer_cache_gc list
analyzer_cache_gc clean --older-than 90
analyzer_cache_gc clean --older-than 30 --dry-run
analyzer_cache_gc clean --older-than 180 --include-current
```

- `list` (alias `ls`, the default) shows each partition with its number of
  summaries, size and last use; the current toolchain's partition is marked.
- `clean` (alias `gc`) deletes partitions not used for more than
  `--older-than` days (default 90), never the current one unless
  `--include-current` is given, and then deletes, in the partitions that stay,
  every file not used since the same cutoff. `--dry-run` only reports.
- `--root <dir>` works on another `analyzer-cache` folder; by default it is
  resolved from the current directory like the cache itself.

"Last used" is a file's modification time, which every run that loads a
summary refreshes. The same operations are available in code through
`AnalyzerCacheGarbageCollector` (`resolve()`, `listPartitions()`,
`collect(cutoff:, keep:, dryRun:)`, `sweepBundles(cutoff:, dryRun:)`, the
static `selectForCollection` and `currentPartitionKey()`), returning
`AnalyzerCachePartition` and `SweptCacheFile` values.

## Errors and limits

- **`dart:io` only.** The package reads the file system and runs processes, so
  it works on desktop, server and command-line hosts, not on the web.
- **Processes.** `resolveVersionedDependencies` runs `flutter --version
  --machine`; `getFlutterSdkPath` may run `which flutter`; `resolveDartSdkPath`
  may run `which`/`where`. A missing Flutter is not an error.
- **Missing inputs.** No `pubspec.lock`: `FileSystemException` from the
  resolver, a warning and `null` from the stage. No `package_config.json`: the
  resolver falls back to its guesses; the grouped bundle builder throws
  `SummaryConfigException`.
- **Only hosted and SDK packages are cached.** Path and git dependencies, and
  the project's own code, are always analysed from source.
- **Summaries are toolchain-specific.** A summary is never shared between
  analyzer data versions or Dart SDK versions; a new toolchain starts with an
  empty partition and builds it once.
- **The first run is slow.** Building the SDK summary and a large dependency
  tree takes as long as analysing them once; later runs only check that the
  files exist.
- **`rebuildCache` and `clearCache` delete files other runs may be reading.**
  Use them only when no other tool is working on the same workspace.
- **Concurrent runs are safe otherwise.** Writes go through private temporary
  files and renames, and file names include the closure, so parallel tools on
  one workspace share summaries without overwriting each other's.
