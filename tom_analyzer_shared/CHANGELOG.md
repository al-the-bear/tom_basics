# Changelog

## 0.3.0

- Added `ToolCacheLocator` — resolves a shared **Tom tool-cache directory**
  reused across projects and tools, so the same hosted-package summary is
  generated once and shared everywhere. Resolution order:
  1. the `TOM_BUILD_CACHE` environment variable (explicit override),
  2. an existing `.tom/tom_tool_cache` directory in any ancestor of the start
     directory (repo-local shared cache),
  3. a `tom_tool_cache` sub-directory of the platform's default Dart tool
     directory (`%APPDATA%\dart`, `~/Library/Application Support/dart`, or
     `$XDG_CONFIG_HOME`/`~/.config/dart`).
  `resolve()` only reads the filesystem; the directory is created lazily on
  first write.
- `SummaryCacheManager` now stores summaries in the shared tool cache's
  `analyzer-cache/` sub-directory (resolved by `ToolCacheLocator` from the
  workspace root) instead of a fixed `<workspace>/.tom/analyzer-cache`.
  Consumers calling `runSummaryCacheStage()` get the shared cache
  automatically. A new `cacheDirectory` constructor argument overrides the
  resolution (used by tests and callers that manage their own layout); a new
  `environment` argument overrides the process environment consulted by the
  locator.

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
