# Changelog

## 0.7.4

- **Removed dead pre-partition scaffolding from `SummaryCacheManager`.** The
  `cleanOutdated()` no-op method and the two stale "check SDK version
  compatibility from summary metadata" TODOs are all superseded by the
  `<analyzer-major>/<dart-sdk-version>` partition key introduced in 0.7.1:
  toolchain compatibility is now guaranteed *structurally* by the cache path, so
  there is nothing to verify from per-summary metadata and nothing to sweep as
  "outdated" within a partition. `cleanOutdated()` (a documented no-op with no
  callers) is deleted rather than kept as a placeholder. Use
  `cleanUnusedSummaries()` to prune summaries that no longer match the resolved
  dependency set.

## 0.7.3

- **Opt-in garbage collector for orphaned analyzer-cache partitions.** The cache
  is partitioned by `<analyzer-major>/<dart-sdk-version>`, which makes it
  self-freshening (a toolchain change starts from an empty partition) at the
  acknowledged cost that *retired* partitions — from a Dart SDK or analyzer
  major the machine no longer uses — linger on disk forever. There is
  deliberately no automatic pruning, because the shared cache cannot safely know
  a partition is truly dead (another checkout pinned to an older SDK might still
  need it). New `AnalyzerCacheGarbageCollector` / `AnalyzerCachePartition`
  (exported from the package) enumerate partitions with their last-used time and
  size and delete those older than a caller-supplied cutoff, never touching the
  live partition unless explicitly told to. A matching `analyzer_cache_gc` CLI
  (built on the tom_build_base v2 tool framework) exposes `list` and
  `clean --older-than <days> [--dry-run] [--include-current]` so a human or CI
  can reclaim that space deliberately. Adds a `tom_build_base` dependency (CLI
  only) and a new `currentDartSdkVersion()` helper in `analyzer_version.dart`
  (reused by `SummaryCacheManager`).

## 0.7.2

- **Summary bundles invalidated when a *transitive* dependency changes
  version (dependency-closure fingerprinting).** A `.sum` bundle keyed only by
  its own `name@version` was silently stale when a package deeper in its
  dependency closure moved version — the classic case being `tom_crypto@1.0.0`
  linked against `tom_basics@1.0.0` (whose `TomBaseException` lived at
  `src/exception_base.dart`) after `tom_basics` moved to `1.0.1`
  (`src/exceptions/exception_base.dart`). Loading the stale bundle threw
  `Invalid argument(s): Missing library: package:tom_basics/src/exception_base.dart`
  when the analyzer lazily linked a subclass's supertype; code generators
  swallow that error and silently drop the affected classes (observed: the JWT
  bridge surface disappearing from `tom_core_d4rt` on regeneration).
  `SummaryCacheManager` now writes a `{package}@{version}.sum.deps` sidecar
  recording the sorted versioned closure each bundle was linked against.
  `runSummaryCacheStage` computes the expected closure fingerprint for every
  cacheable package, deletes and regenerates any bundle whose recorded
  fingerprint no longer matches (bundles with no sidecar — produced before this
  mechanism existed — are treated as stale so the cache self-heals), and never
  *loads* a bundle that is not fingerprint-fresh. `--rebuild-cache` is no longer
  needed to recover from a transitive-version-change poisoning.

## 0.7.1

- **Cache partitioned by Dart SDK version, not just analyzer major.**
  `SummaryCacheManager` now stores summaries under
  `<tool-cache>/analyzer-cache/<analyzer-major>/<dart-sdk-version>/` (previously
  the innermost segment was the analyzer major only). The analyzer's binary
  `.sum` format has **no stability guarantee within an analyzer major**, so a
  point Dart SDK upgrade can ship a format-incompatible analyzer of the same
  major. Keying only by major let a pre-upgrade bundle be read by the new
  analyzer, which crashed with `RangeError ... StringTable` (string-table
  misalignment) after the 2026-07-16 fleet SDK upgrade. The Dart SDK version is
  the AOT-safe toolchain-identity signal (the analyzer exposes no runtime
  version constant, and AOT-compiled generators cannot path-sniff their own
  `package_config`) and self-freshens on every SDK upgrade, so a toolchain
  change starts from an empty partition automatically — `--rebuild-cache` is
  never needed for *correctness*.

## 0.7.0

- **Workspace-local tool cache only — no machine-global fallback.**
  `ToolCacheLocator.resolve` now resolves the tool-cache root to the workspace's
  `.tom/` directory and **never** falls back to a machine-global location such as
  `~/.config/dart/tom_tool_cache`. Resolution order is now: `TOM_TOOL_CACHE` env
  override → the nearest ancestor **workspace root** (a directory containing
  `tom_workspace.yaml` or `.tom_metadata/tom_master.yaml`), whose `.tom`
  sub-directory is the cache root → `<start>/.tom` when no workspace-root
  ancestor exists. Analyzer summaries therefore live in
  `<workspace>/.tom/analyzer-cache/<analyzer-major>/`, matching the committed
  `.tom/analyzer-cache/` marker.
- **Keys off the workspace-root marker, not the nearest `.tom`.** Because the
  Tom tree contains nested project-level `.tom` directories (with no workspace
  marker), searching for the nearest `.tom` would fragment the cache into a
  nested project. Identifying the *workspace root* by its committed marker means
  every tool in the tree shares the single `<workspace>/.tom/analyzer-cache/`.
- **Fixes the stale-global-cache trap.** The 0.6.0 ancestor branch searched for
  `.tom/tom_tool_cache`, which never matched the committed `.tom/analyzer-cache/`
  layout, so resolution silently fell through to the machine-global Dart tool
  directory. Path-dependent workspaces now keep their cache in-tree where it
  belongs.
- **Breaking:** removed `ToolCacheLocator.defaultDartToolDirectory`, the
  `cacheDirName` constant, and the `dartToolDirectory` parameter of `resolve`
  (the machine-global fallback they served no longer exists). Added the
  `workspaceCacheDirName` constant (`'.tom'`). No workspace consumer referenced
  the removed symbols.

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
