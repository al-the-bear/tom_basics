# tom_analyzer_shared

Shared analyzer-summary caching infrastructure reused by Tom code
generators. It was extracted from `tom_reflection_generator` so multiple
tools (reflection, d4rt bridges, ...) can share the same summary cache
at `<workspace>/.tom/analyzer-cache/` and avoid rescanning stable
dependencies on every run.

## What it does

For a project with a resolved `pubspec.lock`, this library can:

1. Enumerate all dependencies with their exact versions and source
   types (`hosted`, `sdk`, `path`, `git`).
2. Decide which of them are *cacheable* (hosted pub.dev packages and
   SDK packages — their versions are stable).
3. Build a binary summary (`.sum`) for the Dart SDK (including Flutter
   `dart:ui` via `sky_engine/_embedder.yaml` when Flutter is on the
   path) and for each cacheable package, in topological order so that
   a package's summary can reference its dependencies' summaries.
4. Store all summaries under `<workspace>/.tom/analyzer-cache/` using
   the naming scheme `{package}@{version}.sum` and
   `sdk@{dart-version}.sum`.
5. Return the list of summary paths so callers can pass them to
   `AnalysisContextCollectionImpl(..., librarySummaryPaths:
   summaryPaths, sdkSummaryPath: sdkSummaryPath)` and skip re-analysing
   those packages from sources.

## Public API

Import everything via the top-level library:

```dart
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';
```

Main types and functions:

- `PackageDependency`, `DependencySet` — resolved dependency metadata.
- `DependencyResolver` — parses `pubspec.lock`, resolves hosted and SDK
  package locations.
- `SummaryCacheManager` — reads and writes `.sum` files in the shared
  cache directory.
- `SummaryGenerator` — generates the SDK summary and per-package
  summaries (topological order, progress callback, error aggregation).
- `runSummaryCacheStage()` — convenience entry-point used by CLI tools.
  Resolves dependencies, generates what's missing, and returns a
  `SummaryCacheResult(summaryPaths, sdkSummaryPath)`.

## Typical usage

```dart
final result = await runSummaryCacheStage(
  projectRoot,
  verbose: true,
);

final collection = AnalysisContextCollectionImpl(
  includedPaths: [projectRoot],
  sdkSummaryPath: result?.sdkSummaryPath,
  librarySummaryPaths: result?.summaryPaths ?? const [],
);
```

Both `tom_reflection_generator` and `tom_d4rt_generator` use this stage
to share a single cache directory across runs.
