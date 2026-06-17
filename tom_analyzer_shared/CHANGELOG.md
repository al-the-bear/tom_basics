# Changelog

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
