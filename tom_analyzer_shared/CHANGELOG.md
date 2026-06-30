# Changelog

## 0.6.1

- **Auditable cache use.** `runSummaryCacheStage` now emits a per-summary
  trace under `--verbose` — `using {pkg}@{ver}.sum from cache at {path}` for
  every loaded package summary, plus one line for the SDK summary — so a run
  can be inspected to confirm the cache is actually being read rather than
  re-analyzed. Non-verbose output is unchanged (still the single
  `Loading N cached summaries.` line).
- `runSummaryCacheStage` gained an optional `cacheManager` argument so the
  whole stage can be exercised hermetically against a fixed cache directory
  (used by the new `summary_cache_stage_test.dart`). Defaults to the
  shared-cache manager, so existing callers are unaffected.

## 0.6.0

- **Shared tool-cache root for the summary cache.** `SummaryCacheManager` now
  resolves its cache *root* through the new `ToolCacheLocator` — the shared Tom
  tool-cache directory (`TOM_TOOL_CACHE` env override -> an ancestor
  `.tom/tom_tool_cache` -> the platform Dart tool directory) — so the same
  hosted-package summary is generated once and reused across projects and
  sibling generators, instead of a fixed `<workspace>/.tom/analyzer-cache`.
  `ToolCacheLocator.resolve()` only reads the filesystem; the directory is
  created lazily on first write.
- This composes with the analyzer-major partitioning from 0.4.1: summaries are
  stored under `<tool-cache>/analyzer-cache/<analyzer-major>/`, keeping the
  cross-analyzer-version poison guard while gaining the shared root.
- `SummaryCacheManager` gained `cacheDirectory` (bypass resolution entirely —
  used by tests and callers managing their own layout) and `environment`
  (overrides the process environment consulted by `ToolCacheLocator`)
  constructor arguments; the existing `analyzerMajor` argument is retained.
- Exports `ToolCacheLocator`. Folds in the out-of-band `0.3.0`
  (shared-tool-cache change, published on analyzer 8 and not previously in this
  checkout) on top of the analyzer-10 line (0.4.0-0.5.0).

## 0.5.0

- Added `GroupedPackageBundleBuilder` — builds one grouped `packages.sum`
  bundle from the **union** of several package dependency closures, for
  runtime SDK-free analysis in embedded Dart editors. Unlike `SummaryGenerator`
  (one versioned `.sum` per hosted/SDK package), this emits a single bundle
  covering every package reachable from one or more resolved
  `.dart_tool/package_config.json` files.
  - `buildFromDirs(packageDirs)` merges each directory's resolved config and
    summarizes the union; `buildFromPackageRoots(map)` is the lower-level
    counterpart for callers that already hold a name→root map.
  - The package URI resolver is ordered **before** `ResourceUriResolver` so
    emitted library URIs are portable `package:` URIs, never `file:///`.
  - Also exposes `readPackageRoots`, `mergePackageRootsForDirs`, and
    `SummaryConfigException` (the base-first home for this logic, previously
    duplicated in `tom_specs_clitool`).

## 0.4.1

- **Partition the summary cache by analyzer major version.**
  `SummaryCacheManager` now stores `.sum` bundles under
  `.tom/analyzer-cache/<analyzer-major>/` instead of a flat
  `.tom/analyzer-cache/`. `.sum` files use an analyzer-version-specific binary
  format, so a bundle written by analyzer N is undecodable by analyzer M (it
  crashes the reader with a `RangeError`). Because caches were keyed only by
  `package@version`, a cache populated under one analyzer major silently
  poisoned a tool that later ran under a different analyzer major. Keying the
  directory by analyzer major guarantees a tool only ever reads bundles its own
  analyzer can decode.
- Added `analyzerMajorVersion` — the compile-time analyzer-major constant this
  build targets (currently `10`). It is the AOT-safe source of truth for the
  cache partition (Tom code generators run AOT-compiled, where runtime package
  path-sniffing is unavailable). **Bump it in lockstep with the `analyzer`
  constraint in `pubspec.yaml`.**
- `SummaryCacheManager` gained an `analyzerMajor` constructor parameter
  (defaults to `analyzerMajorVersion`); intended for tests exercising the
  partitioning without rebuilding against a different analyzer.

## 0.4.0

- Migrated to `analyzer: ^10.0.0` (from `^8.4.1`). The package only depends on
  the internal summary2 / element APIs (`BundleWriter`,
  `PackageBundleFormat`, `AnalysisContextCollectionImpl`,
  `buildSdkSummary`, `LibraryElementImpl`, `library.fragments`), all of which
  are unchanged across analyzer 8.4 → 10. No source changes were required —
  this is a pure constraint bump. The SDK floor stays `^3.10.4` (analyzer 10
  only requires Dart `^3.9.0`).
- Note: version `0.3.0` was already published to pub.dev on `analyzer ^8.4.1`
  (out of band, not from this checkout), so this analyzer-10 migration ships as
  `0.4.0`.

## 0.2.0

- Added `resolveDartSdkPath()` and `looksLikeDartSdk()` — a robust runtime
  Dart SDK locator (in `src/sdk/dart_sdk_locator.dart`). The analyzer derives
  the SDK from `Platform.resolvedExecutable`, which is correct under `dart run`
  but fails for AOT-compiled tools (`dart compile exe`) where the executable is
  the tool itself, not the `dart` binary. The locator tries `DART_SDK` /
  `DART_HOME`, the resolved executable, and the `dart`/`flutter` executables on
  `PATH` (handling the Flutter `bin/cache/dart-sdk` layout), validating every
  candidate against the SDK marker file before returning it. The result is
  cached for the process lifetime.
- `SummaryGenerator` now uses `resolveDartSdkPath()` to locate the SDK summary
  directory, fixing a `PathNotFoundException` for
  `lib/_internal/allowed_experiments.json` when run from a compiled binary.

## 0.1.0

- Initial release. Extracted summary-caching infrastructure from
  `tom_reflection_generator` into a reusable library so multiple code
  generators (reflection, d4rt bridges, ...) can share the same
  `<workspace>/.tom/analyzer-cache/` directory.
- Public API:
  - `PackageDependency`, `DependencySet`
  - `DependencyResolver` (parses `pubspec.lock`, locates hosted/SDK
    package sources)
  - `SummaryCacheManager` (reads/writes `{name}@{version}.sum` files)
  - `SummaryGenerator` (generates the SDK summary and per-package
    summaries in topological order)
  - `runSummaryCacheStage()` and `SummaryCacheResult` — reusable
    orchestration helper that resolves dependencies, generates missing
    summaries, and returns the paths to pass to
    `AnalysisContextCollectionImpl`.
