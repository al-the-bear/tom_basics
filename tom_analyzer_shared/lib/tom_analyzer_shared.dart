/// Shared analyzer-summary caching infrastructure for Tom code generators.
///
/// This library exposes:
///
/// - [PackageDependency] / [DependencySet] — resolved dependency metadata.
/// - [DependencyResolver] — parses `pubspec.lock` and locates hosted/SDK
///   package source trees in the pub cache and the Flutter SDK.
/// - [SummaryCacheManager] — reads and writes `.sum` files under
///   `<workspace>/.tom/analyzer-cache/`.
/// - [SummaryGenerator] — generates the SDK summary and per-package
///   summaries in topological order.
/// - [runSummaryCacheStage] / [SummaryCacheResult] — a reusable
///   orchestration entry-point for CLIs and builders.
/// - [resolveDartSdkPath] — robust Dart SDK location for AOT-compiled tools
///   (where executable-relative SDK detection fails).
///
/// See the package README for motivation and examples.
library;

export 'src/sdk/dart_sdk_locator.dart'
    show resolveDartSdkPath, looksLikeDartSdk;
export 'src/summary/dependency_resolver.dart';
export 'src/summary/package_dependency.dart';
export 'src/summary/summary_cache_manager.dart';
export 'src/summary/summary_cache_stage.dart';
export 'src/summary/summary_generator.dart';
