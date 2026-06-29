/// Shared analyzer-summary caching infrastructure for Tom code generators.
///
/// This library exposes:
///
/// - [PackageDependency] / [DependencySet] — resolved dependency metadata.
/// - [DependencyResolver] — parses `pubspec.lock` and locates hosted/SDK
///   package source trees in the pub cache and the Flutter SDK.
/// - [ToolCacheLocator] — resolves the shared Tom tool-cache directory
///   (`TOM_TOOL_CACHE` → ancestor `.tom/tom_tool_cache` → Dart tool dir).
/// - [SummaryCacheManager] — reads and writes `.sum` files under the shared
///   tool cache's `analyzer-cache/<analyzer-major>/` sub-directory.
/// - [analyzerMajorVersion] — the analyzer major this build targets; used to
///   partition the cache so analyzer upgrades cannot read stale bundles.
/// - [SummaryGenerator] — generates the SDK summary and per-package
///   summaries in topological order.
/// - [GroupedPackageBundleBuilder] — builds one grouped `packages.sum` from the
///   union of several package dependency closures (for embedded-editor runtime
///   analysis). See [mergePackageRootsForDirs] / [readPackageRoots].
/// - [runSummaryCacheStage] / [SummaryCacheResult] — a reusable
///   orchestration entry-point for CLIs and builders.
/// - [resolveDartSdkPath] — robust Dart SDK location for AOT-compiled tools
///   (where executable-relative SDK detection fails).
///
/// See the package README for motivation and examples.
library;

export 'src/cache/tool_cache_locator.dart' show ToolCacheLocator;
export 'src/sdk/dart_sdk_locator.dart'
    show resolveDartSdkPath, looksLikeDartSdk;
export 'src/summary/analyzer_version.dart' show analyzerMajorVersion;
export 'src/summary/dependency_resolver.dart';
export 'src/summary/grouped_package_bundle.dart';
export 'src/summary/package_dependency.dart';
export 'src/summary/summary_cache_manager.dart';
export 'src/summary/summary_cache_stage.dart';
export 'src/summary/summary_generator.dart';
