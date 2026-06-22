# Changelog

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
