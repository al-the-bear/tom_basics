// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/sdk/build_sdk_summary.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/summary2/bundle_writer.dart';
import 'package:analyzer/src/summary2/package_bundle_format.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../sdk/dart_sdk_locator.dart';
import 'dependency_resolver.dart';
import 'package_dependency.dart';
import 'summary_cache_manager.dart';

/// Result of generating summaries for a batch of packages.
class SummaryGenerationResult {
  /// Number of summaries successfully generated.
  final int generated;

  /// Number of summaries that were already cached.
  final int skipped;

  /// Number of summaries that failed to generate.
  final int failed;

  /// Error messages for failed packages (keyed by package name).
  final Map<String, String> errors;

  const SummaryGenerationResult({
    required this.generated,
    required this.skipped,
    required this.failed,
    required this.errors,
  });

  /// Total packages processed.
  int get total => generated + skipped + failed;

  @override
  String toString() =>
      'SummaryGenerationResult(generated: $generated, skipped: $skipped, '
      'failed: $failed)';
}

/// Generates analyzer summaries for packages.
///
/// Creates binary `.sum` files containing pre-analyzed type information
/// for stable dependencies (hosted and SDK packages). These summaries
/// can be loaded by the analyzer to skip re-analysis of unchanged packages.
///
/// ## Usage
///
/// ```dart
/// final cacheManager = SummaryCacheManager('/path/to/workspace');
/// final depResolver = DependencyResolver();
/// final generator = SummaryGenerator(
///   cacheManager: cacheManager,
///   dependencyResolver: depResolver,
/// );
///
/// // Generate summaries for all missing dependencies
/// final deps = await depResolver.resolveCacheableDependencies('/path/to/project');
/// final result = await generator.generateMissingSummaries(deps);
/// print('Generated ${result.generated} summaries');
/// ```
class SummaryGenerator {
  /// The cache manager for reading/writing summary files.
  final SummaryCacheManager cacheManager;

  /// The dependency resolver for locating package sources.
  final DependencyResolver dependencyResolver;

  /// Creates a summary generator.
  SummaryGenerator({
    required this.cacheManager,
    required this.dependencyResolver,
  });

  /// Generates a summary for a single package.
  ///
  /// Creates a temporary [AnalysisContextCollectionImpl], analyzes all public
  /// libraries in the package, and writes the summary bundle to cache.
  ///
  /// Does nothing if the summary is already cached.
  ///
  /// Throws if the package path cannot be resolved or analysis fails.
  Future<bool> generateSummary(
    PackageDependency dependency, {
    String? sdkSummaryPath,
    List<String>? librarySummaryPaths,
  }) async {
    if (!dependency.isCacheable) {
      return false;
    }

    // Check if already cached
    if (await cacheManager.hasSummary(dependency.name, dependency.version)) {
      return false;
    }

    // Resolve package path
    final packagePath = await _resolvePackagePath(dependency);
    if (packagePath == null) {
      throw StateError(
        'Could not resolve path for package ${dependency.name}@${dependency.version}',
      );
    }

    // Find all library files (public and internal)
    final libraryFiles = _findAllLibraries(packagePath);
    if (libraryFiles.isEmpty) {
      // No libraries — nothing to summarize
      stdout.writeln('    Skipping ${dependency.name}: no public libraries');
      return false;
    }

    stdout.writeln('    Analyzing ${dependency.name}@${dependency.version} '
        '(${libraryFiles.length} libraries)...');

    // Analyze and create summary bundle
    final summaryBytes = await _analyzeAndCreateBundle(
      packagePath,
      dependency.name,
      libraryFiles,
      sdkSummaryPath: sdkSummaryPath,
      librarySummaryPaths: librarySummaryPaths,
    );

    if (summaryBytes == null) {
      stdout.writeln('    Failed to create bundle for ${dependency.name}');
      return false;
    }

    // Write to cache
    await cacheManager.writeSummary(
      dependency.name,
      dependency.version,
      summaryBytes,
    );

    final sizeKB = (summaryBytes.length / 1024).toStringAsFixed(1);
    stdout.writeln('    Cached ${dependency.name}@${dependency.version} '
        '($sizeKB KB)');

    return true;
  }

  /// Generates the Dart SDK summary and stores it in the cache.
  ///
  /// Uses the analyzer's `buildSdkSummary` API to create a summary of
  /// all `dart:` libraries. For Flutter projects, this also includes
  /// `dart:ui` via the sky_engine embedder.
  ///
  /// Returns `true` if the summary was generated, `false` if already cached.
  Future<bool> generateSdkSummary() async {
    if (await cacheManager.hasSdkSummary()) {
      return false;
    }

    // Locate the SDK robustly. `buildSdkSummary` reads
    // `lib/_internal/allowed_experiments.json` from this directory; deriving it
    // from `Platform.resolvedExecutable` only works under `dart run`, not for an
    // AOT-compiled tool (where the executable is the tool itself). Fall back to
    // the executable-relative path so behaviour under `dart run` is unchanged.
    final sdkPath = resolveDartSdkPath() ??
        p.dirname(p.dirname(Platform.resolvedExecutable));
    stdout.writeln('  Generating SDK summary (Dart ${cacheManager.dartSdkVersion})...');

    // Check for Flutter embedder (sky_engine provides dart:ui)
    String? embedderYamlPath;
    final flutterSdkPath = await dependencyResolver.getFlutterSdkPath();
    if (flutterSdkPath != null) {
      final dartUiPath = p.normalize(
        p.join(flutterSdkPath, 'bin', 'cache', 'pkg', 'sky_engine', 'lib'),
      );
      final embedderFile = File(p.join(dartUiPath, '_embedder.yaml'));
      if (embedderFile.existsSync()) {
        embedderYamlPath = embedderFile.path;
      }
    }

    final summaryBytes = await buildSdkSummary(
      sdkPath: sdkPath,
      resourceProvider: PhysicalResourceProvider.INSTANCE,
      embedderYamlPath: embedderYamlPath,
    );

    await cacheManager.writeSummary(
      'sdk',
      cacheManager.dartSdkVersion,
      summaryBytes,
    );

    final sizeKB = (summaryBytes.length / 1024).toStringAsFixed(1);
    stdout.writeln('  Cached SDK summary ($sizeKB KB)');

    return true;
  }

  /// Generates summaries for all dependencies that are missing from the cache.
  ///
  /// Processes dependencies in topological order (leaves first) so that
  /// each package's summary is generated with its dependencies' summaries
  /// already available. This ensures cross-package type references resolve
  /// correctly instead of becoming `InvalidType`.
  ///
  /// Pass [sdkSummaryPath] to provide the SDK summary (including `dart:ui`
  /// via Flutter embedder) to each package's analysis context.
  ///
  /// Skips dependencies that are already cached or not cacheable.
  /// Continues processing on individual failures, collecting errors.
  Future<SummaryGenerationResult> generateMissingSummaries(
    List<PackageDependency> dependencies, {
    String? sdkSummaryPath,
    void Function(String package, int current, int total)? onProgress,
  }) async {
    final cacheable =
        dependencies.where((d) => d.isCacheable).toList();

    // Build topological generation order so dependencies come first
    final ordered = await _buildGenerationOrder(cacheable);

    // Collect already-cached summary paths as available for new generations
    final availableSummaries = <String>[];
    for (final dep in cacheable) {
      if (await cacheManager.hasSummary(dep.name, dep.version)) {
        availableSummaries.add(
          cacheManager.getCachePath(dep.name, dep.version),
        );
      }
    }

    var generated = 0;
    var skipped = 0;
    var failed = 0;
    final errors = <String, String>{};

    for (var i = 0; i < ordered.length; i++) {
      final dep = ordered[i];
      onProgress?.call(dep.name, i + 1, ordered.length);

      // Check if already cached
      if (await cacheManager.hasSummary(dep.name, dep.version)) {
        skipped++;
        continue;
      }

      try {
        final success = await generateSummary(
          dep,
          sdkSummaryPath: sdkSummaryPath,
          librarySummaryPaths: availableSummaries.isNotEmpty
              ? List.from(availableSummaries)
              : null,
        );
        if (success) {
          generated++;
          // Add newly generated summary to available list for subsequent packages
          availableSummaries.add(
            cacheManager.getCachePath(dep.name, dep.version),
          );
        } else {
          skipped++;
        }
      } catch (e) {
        failed++;
        errors[dep.name] = e.toString();
      }
    }

    return SummaryGenerationResult(
      generated: generated,
      skipped: skipped,
      failed: failed,
      errors: errors,
    );
  }

  /// Resolves the filesystem path for a dependency.
  Future<String?> _resolvePackagePath(PackageDependency dependency) async {
    switch (dependency.source) {
      case 'hosted':
        return dependencyResolver.getHostedPackagePath(dependency);
      case 'sdk':
        return await dependencyResolver.getSdkPackagePath(dependency);
      default:
        return null;
    }
  }

  /// Finds all Dart library files in a package's `lib/` directory.
  ///
  /// Returns absolute, normalized paths for each `.dart` file found,
  /// including files in `lib/src/`. All libraries need to be included
  /// because public libraries may export/re-export symbols from internal
  /// src/ libraries, and those need to be in the summary.
  List<String> _findAllLibraries(String packagePath) {
    final libDir = Directory(p.join(packagePath, 'lib'));
    if (!libDir.existsSync()) {
      return [];
    }

    final libraries = <String>[];

    // Find all .dart files recursively in lib/ (including lib/src/)
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        libraries.add(p.normalize(entity.path));
      }
    }

    return libraries;
  }

  /// Creates a summary bundle from already-resolved library elements.
  ///
  /// Uses [BundleWriter] to serialize each library's type information,
  /// then wraps the result with [PackageBundleBuilder] to create the
  /// final `.sum` binary format.
  Uint8List _createSummaryBundle(List<LibraryElement> libraries) {
    final bundleWriter = BundleWriter();
    final bundleBuilder = PackageBundleBuilder();

    for (final library in libraries) {
      bundleWriter.writeLibraryElement(library as LibraryElementImpl);

      // Register the library URI and its fragment (unit) URIs
      final libraryUri = library.uri.toString();
      final unitUris = library.fragments
          .map((fragment) => fragment.source.uri.toString())
          .toList();
      bundleBuilder.addLibrary(libraryUri, unitUris);
    }

    final writerResult = bundleWriter.finish();
    return bundleBuilder.finish(
      resolutionBytes: writerResult.resolutionBytes,
    );
  }

  /// Analyzes a package and creates its summary bundle.
  ///
  /// Creates a temporary [AnalysisContextCollectionImpl] for the package,
  /// resolves all public libraries, and serializes them using
  /// [_createSummaryBundle].
  ///
  /// Creates a temporary `.dart_tool/package_config.json` to ensure the
  /// analyzer uses proper `package:` URIs instead of `file://` URIs.
  ///
  /// If [librarySummaryPaths] is provided, the analyzer loads those summaries
  /// to resolve cross-package type references. When [sdkSummaryPath] is
  /// non-null it is passed to the analysis context, so `dart:` libraries
  /// resolve from the cached SDK summary (a summary-based SDK) and the on-disk
  /// SDK is not read — see the `SummaryDataStore` note on the context
  /// construction below for the condition that makes this reliable. When
  /// [sdkSummaryPath] is null the analyzer falls back to resolving the SDK
  /// from disk.
  Future<Uint8List?> _analyzeAndCreateBundle(
    String packagePath,
    String packageName,
    List<String> libraryFiles, {
    String? sdkSummaryPath,
    List<String>? librarySummaryPaths,
  }) async {
    AnalysisContextCollectionImpl? collection;
    final dartToolDir = Directory(p.join(packagePath, '.dart_tool'));
    final packageConfigFile = File(p.join(dartToolDir.path, 'package_config.json'));
    final hadDartTool = dartToolDir.existsSync();
    final hadPackageConfig = packageConfigFile.existsSync();

    try {
      // Create minimal package_config.json for proper package: URI resolution
      if (!dartToolDir.existsSync()) {
        dartToolDir.createSync(recursive: true);
      }
      
      // Get language version from pubspec.yaml if possible
      final languageVersion = _getLanguageVersion(packagePath);
      
      // Write a minimal package_config.json
      final packageConfig = '''{
  "configVersion": 2,
  "packages": [
    {
      "name": "$packageName",
      "rootUri": "../",
      "packageUri": "lib/",
      "languageVersion": "$languageVersion"
    }
  ]
}''';
      packageConfigFile.writeAsStringSync(packageConfig);

      // Create analysis context for the package.
      // IMPORTANT: When sdkSummaryPath is provided, librarySummaryPaths MUST
      // also be non-null (even if empty) because the analyzer only creates
      // SummaryDataStore when librarySummaryPaths != null, and the SDK bundle
      // is only registered into that store via `summaryData?.addBundle(...)`.
      // Without a SummaryDataStore, dart:core is not found.
      if (sdkSummaryPath != null || (librarySummaryPaths != null && librarySummaryPaths.isNotEmpty)) {
        collection = AnalysisContextCollectionImpl(
          includedPaths: [p.normalize(p.absolute(packagePath))],
          sdkSummaryPath: sdkSummaryPath,
          librarySummaryPaths: librarySummaryPaths ?? const [],
        );
      } else {
        collection = AnalysisContextCollectionImpl(
          includedPaths: [p.normalize(p.absolute(packagePath))],
        );
      }

      final resolvedLibraries = <LibraryElement>[];

      for (final filePath in libraryFiles) {
        try {
          final context = collection.contextFor(filePath);
          final session = context.currentSession;

          final result = await session.getResolvedLibrary(filePath);
          if (result is! ResolvedLibraryResult) {
            continue;
          }

          final libraryElement = result.element;

          // BundleWriter requires LibraryElementImpl
          if (libraryElement is! LibraryElementImpl) {
            continue;
          }

          resolvedLibraries.add(libraryElement);
        } catch (e) {
          // Skip individual library failures — log but continue
          stderr.writeln(
            'Warning: Failed to analyze ${p.basename(filePath)}: $e',
          );
        }
      }

      if (resolvedLibraries.isEmpty) {
        return null;
      }

      return _createSummaryBundle(resolvedLibraries);
    } finally {
      await collection?.dispose();
      
      // Clean up the temporary package_config.json
      if (!hadPackageConfig && packageConfigFile.existsSync()) {
        packageConfigFile.deleteSync();
      }
      if (!hadDartTool && dartToolDir.existsSync()) {
        try {
          dartToolDir.deleteSync(recursive: true);
        } catch (_) {
          // Ignore cleanup failures
        }
      }
    }
  }
  
  /// Builds a topological generation order for package summaries.
  ///
  /// Reads each package's `pubspec.yaml` to discover its dependencies,
  /// then uses Kahn's algorithm to produce an order where a package's
  /// dependencies are always generated before the package itself.
  ///
  /// Packages with circular dependencies (rare but possible) are appended
  /// at the end after all acyclic packages.
  Future<List<PackageDependency>> _buildGenerationOrder(
    List<PackageDependency> deps,
  ) async {
    final nameToDepMap = <String, PackageDependency>{};
    for (final dep in deps) {
      nameToDepMap[dep.name] = dep;
    }

    // Build dependency graph: dependsOn[A] = {B, C} means A depends on B and C
    final dependsOn = <String, Set<String>>{};
    // Reverse graph: dependedBy[B] = {A} means A depends on B
    final dependedBy = <String, Set<String>>{};

    for (final dep in deps) {
      final path = await _resolvePackagePath(dep);
      final pkgDeps =
          path != null ? _readPackageDependencies(path) : <String>[];
      final filtered =
          pkgDeps.where((d) => nameToDepMap.containsKey(d)).toSet();
      dependsOn[dep.name] = filtered;

      for (final d in filtered) {
        dependedBy.putIfAbsent(d, () => <String>{}).add(dep.name);
      }
    }

    // Kahn's algorithm: start with packages that have no deps in our set
    final inDegree = <String, int>{};
    for (final name in nameToDepMap.keys) {
      inDegree[name] = dependsOn[name]?.length ?? 0;
    }

    final queue = <String>[
      for (final entry in inDegree.entries)
        if (entry.value == 0) entry.key,
    ]..sort(); // Sorted for deterministic output

    final sorted = <String>[];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      sorted.add(current);

      for (final dependent in (dependedBy[current] ?? <String>{})) {
        inDegree[dependent] = inDegree[dependent]! - 1;
        if (inDegree[dependent] == 0) {
          // Insert in sorted position for determinism
          final insertIdx =
              queue.indexWhere((s) => s.compareTo(dependent) > 0);
          if (insertIdx < 0) {
            queue.add(dependent);
          } else {
            queue.insert(insertIdx, dependent);
          }
        }
      }
    }

    // Append any remaining packages (circular deps) at end
    for (final name in nameToDepMap.keys) {
      if (!sorted.contains(name)) {
        sorted.add(name);
      }
    }

    return sorted
        .map((name) => nameToDepMap[name]!)
        .toList();
  }

  /// Reads dependency names from a package's `pubspec.yaml`.
  ///
  /// Returns dependency names from the `dependencies` section only
  /// (not `dev_dependencies`).
  List<String> _readPackageDependencies(String packagePath) {
    final pubspecFile = File(p.join(packagePath, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) return [];

    try {
      final content = pubspecFile.readAsStringSync();
      final yaml = loadYaml(content) as YamlMap?;
      if (yaml == null) return [];

      final deps = <String>[];
      final dependencies = yaml['dependencies'] as YamlMap?;
      if (dependencies != null) {
        deps.addAll(dependencies.keys.cast<String>());
      }
      return deps;
    } catch (_) {
      return [];
    }
  }

  /// Extracts the language version from pubspec.yaml environment constraint.
  /// Returns a default version if not found.
  String _getLanguageVersion(String packagePath) {
    final pubspecFile = File(p.join(packagePath, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      return '2.12'; // Default to null-safety era
    }
    
    final content = pubspecFile.readAsStringSync();
    
    // Look for environment.sdk constraint like "sdk: ^3.0.0" or "sdk: '>=3.0.0 <4.0.0'"
    final sdkMatch = RegExp(r'''sdk:\s*['"]?[>=^]*(\d+\.\d+)''', multiLine: true)
        .firstMatch(content);
    if (sdkMatch != null) {
      return sdkMatch.group(1)!;
    }
    
    return '2.12'; // Default
  }
}
