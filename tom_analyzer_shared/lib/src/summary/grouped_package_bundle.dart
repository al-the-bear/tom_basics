// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:analyzer/file_system/file_system.dart'
    show Folder, ResourceProvider;
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/source/file_source.dart' show FileSource;
import 'package:analyzer/source/source.dart' show Source;
import 'package:analyzer/src/context/packages.dart';
import 'package:analyzer/src/dart/analysis/analysis_options.dart';
import 'package:analyzer/src/dart/analysis/analysis_options_map.dart';
import 'package:analyzer/src/dart/analysis/byte_store.dart';
import 'package:analyzer/src/dart/analysis/driver.dart';
import 'package:analyzer/src/dart/analysis/performance_logger.dart';
import 'package:analyzer/src/dart/sdk/sdk.dart';
import 'package:analyzer/src/file_system/file_system.dart'
    show ResourceUriResolver;
import 'package:analyzer/src/generated/source.dart'
    show DartUriResolver, SourceFactory, UriResolver;
import 'package:path/path.dart' as p;

import '../sdk/dart_sdk_locator.dart';

/// Raised when a package directory has no resolved
/// `.dart_tool/package_config.json` (i.e. `pub get` has not been run there),
/// or when a grouped bundle cannot be built (no SDK / no libraries).
class SummaryConfigException implements Exception {
  SummaryConfigException(this.message);

  final String message;

  @override
  String toString() => 'SummaryConfigException: $message';
}

/// Result of building a grouped `packages.sum` bundle from several package
/// closures.
class GroupedPackageBundle {
  /// The serialized `packages.sum` bytes.
  final Uint8List bytes;

  /// Number of distinct packages whose libraries were summarized.
  final int packageCount;

  /// Total number of `.dart` libraries written into the bundle.
  final int libraryCount;

  const GroupedPackageBundle({
    required this.bytes,
    required this.packageCount,
    required this.libraryCount,
  });

  @override
  String toString() => 'GroupedPackageBundle(packages: $packageCount, '
      'libraries: $libraryCount, ${bytes.length} bytes)';
}

/// Reads a resolved `.dart_tool/package_config.json` and returns a map of
/// package-name → absolute package **root** directory (the directory that
/// contains `lib/`).
///
/// `rootUri`s in the config may be relative to the config file's own location,
/// so they are resolved against [packageConfigFile]'s URI and normalised to a
/// platform path.
Map<String, String> readPackageRoots(io.File packageConfigFile) {
  final config =
      jsonDecode(packageConfigFile.readAsStringSync()) as Map<String, dynamic>;
  final packageList = config['packages'] as List<dynamic>;
  final roots = <String, String>{};
  for (final pkg in packageList) {
    final pkgMap = pkg as Map<String, dynamic>;
    final name = pkgMap['name'] as String;
    final rootUri = pkgMap['rootUri'] as String;
    final resolved = Uri.parse(packageConfigFile.uri.toString())
        .resolve(rootUri.endsWith('/') ? rootUri : '$rootUri/');
    roots[name] = p.normalize(resolved.toFilePath());
  }
  return roots;
}

/// Merges the package roots resolved from each given package directory's
/// `.dart_tool/package_config.json` into a single name→root map.
///
/// This is what lets one `packages.sum` bundle cover the **union** of several
/// dependency closures — e.g. an editor's deps *and* a UI package whose widgets
/// a code-typed field references — without the editor having to depend on that
/// package directly (the bundle is loaded at runtime, never compiled against).
/// On a name collision the later directory wins; within one workspace these are
/// path deps resolving to the same root, so collisions are benign.
///
/// Throws [SummaryConfigException] if any directory lacks a resolved config.
Map<String, String> mergePackageRootsForDirs(Iterable<String> packageDirs) {
  final merged = <String, String>{};
  for (final dir in packageDirs) {
    final configFile =
        io.File(p.join(dir, '.dart_tool', 'package_config.json'));
    if (!configFile.existsSync()) {
      throw SummaryConfigException(
          '${configFile.path} not found — run `flutter pub get` / '
          '`dart pub get` in $dir first.');
    }
    merged.addAll(readPackageRoots(configFile));
  }
  return merged;
}

/// Builds one `packages.sum` bundle from the **union** of several package
/// dependency closures.
///
/// Unlike [SummaryGenerator] (which produces one `.sum` per cacheable hosted /
/// SDK package, keyed by version), this produces a single grouped bundle
/// covering every package reachable from one or more resolved
/// `.dart_tool/package_config.json` files. It is the entry-point used to build
/// the runtime `packages.sum` an embedded Dart editor loads for SDK-free
/// analysis of code-typed fields.
///
/// The resolver order inside [buildFromDirs] is **load-bearing**: the package
/// resolver MUST precede [ResourceUriResolver], otherwise `pathToUri()` emits
/// `file:///` URIs instead of `package:` URIs and the bundle is non-portable.
class GroupedPackageBundleBuilder {
  /// The resource provider used for analysis (defaults to the physical FS).
  final ResourceProvider resourceProvider;

  /// Creates a grouped package-bundle builder.
  GroupedPackageBundleBuilder({ResourceProvider? resourceProvider})
      : resourceProvider = resourceProvider ?? PhysicalResourceProvider.INSTANCE;

  /// Builds a grouped `packages.sum` from the union of every package reachable
  /// from each directory in [packageDirs] (each must have run `pub get`).
  ///
  /// [sdkPath] overrides SDK location; when null, [resolveDartSdkPath] is used.
  /// [onLog] receives human-readable progress lines (defaults to silent).
  ///
  /// Throws [SummaryConfigException] if a config is missing, no SDK can be
  /// located, or no libraries are found to summarize.
  Future<GroupedPackageBundle> buildFromDirs(
    List<String> packageDirs, {
    String? sdkPath,
    void Function(String message)? onLog,
  }) async {
    final normalizedDirs =
        packageDirs.map((d) => p.normalize(p.absolute(d))).toList();
    final packageRoots = mergePackageRootsForDirs(normalizedDirs);
    return buildFromPackageRoots(
      packageRoots,
      sdkPath: sdkPath,
      onLog: onLog,
    );
  }

  /// Builds a grouped `packages.sum` from a pre-resolved name→root map.
  ///
  /// Lower-level counterpart to [buildFromDirs] for callers that already hold a
  /// merged package map (or want to construct one without a config file).
  Future<GroupedPackageBundle> buildFromPackageRoots(
    Map<String, String> packageRoots, {
    String? sdkPath,
    void Function(String message)? onLog,
  }) async {
    final log = onLog ?? (_) {};

    final resolvedSdkPath = sdkPath ?? resolveDartSdkPath();
    if (resolvedSdkPath == null) {
      throw SummaryConfigException(
          'Could not locate the Dart SDK; pass sdkPath explicitly.');
    }
    log('Using SDK: $resolvedSdkPath');
    log('Found ${packageRoots.length} packages.');

    final packages = Packages({
      for (final entry in packageRoots.entries)
        entry.key: Package(
          name: entry.key,
          rootFolder: resourceProvider.getFolder(p.normalize(entry.value)),
          libFolder: resourceProvider.getFolder(p.join(entry.value, 'lib')),
          languageVersion: null,
        ),
    });

    // List ALL .dart files recursively under each lib/ (including src/): the
    // resolution bytes reference imported/exported internal URIs, so each must
    // be a library entry or the consumer's InSummaryUriResolver fails to
    // deserialize.
    final libraryUris = <Uri>[];
    for (final entry in packageRoots.entries) {
      final libDir = io.Directory(p.join(entry.value, 'lib'));
      if (!libDir.existsSync()) continue;
      var count = 0;
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is io.File && entity.path.endsWith('.dart')) {
          final rel = p.relative(entity.path, from: libDir.path);
          libraryUris.add(Uri.parse(
              'package:${entry.key}/${rel.replaceAll('\\', '/')}'));
          count++;
        }
      }
      if (count > 0) log('  ${entry.key}: $count dart files');
    }
    log('Total libraries to summarize: ${libraryUris.length}');
    if (libraryUris.isEmpty) {
      throw SummaryConfigException('No libraries found to summarize.');
    }

    final sdk = FolderBasedDartSdk(
        resourceProvider, resourceProvider.getFolder(resolvedSdkPath));
    final logger = PerformanceLog(StringBuffer());
    final scheduler = AnalysisDriverScheduler(logger);
    final byteStore = MemoryByteStore();
    final optionsMap =
        AnalysisOptionsMap.forSharedOptions(AnalysisOptionsImpl());

    // _PackageMapUriResolver MUST come before ResourceUriResolver (see header).
    final sourceFactory = SourceFactory([
      DartUriResolver(sdk),
      _PackageMapUriResolver(resourceProvider, {
        for (final entry in packageRoots.entries)
          entry.key: resourceProvider.getFolder(p.join(entry.value, 'lib')),
      }),
      ResourceUriResolver(resourceProvider),
    ]);

    final analysisDriver = AnalysisDriver(
      scheduler: scheduler,
      logger: logger,
      resourceProvider: resourceProvider,
      byteStore: byteStore,
      sourceFactory: sourceFactory,
      analysisOptionsMap: optionsMap,
      packages: packages,
      withFineDependencies: false,
    );
    scheduler.start();

    log('Building package bundle...');
    final bytes = await analysisDriver.buildPackageBundle(uriList: libraryUris);

    return GroupedPackageBundle(
      bytes: bytes,
      packageCount: packageRoots.length,
      libraryCount: libraryUris.length,
    );
  }
}

/// Maps `package:` URIs to file-system paths (and back) for the bundle build.
class _PackageMapUriResolver extends UriResolver {
  _PackageMapUriResolver(this._resourceProvider, this._packageMap);

  final ResourceProvider _resourceProvider;
  final Map<String, Folder> _packageMap;

  @override
  Uri? pathToUri(String path) {
    for (final entry in _packageMap.entries) {
      final pkgPath = entry.value.path;
      if (path.startsWith(pkgPath)) {
        final relative = path.substring(pkgPath.length);
        if (relative.startsWith('/') ||
            relative.startsWith(io.Platform.pathSeparator)) {
          return Uri.parse(
              'package:${entry.key}${relative.replaceAll('\\', '/')}');
        }
      }
    }
    return null;
  }

  @override
  Source? resolveAbsolute(Uri uri) {
    if (uri.scheme != 'package') return null;
    final parts = uri.pathSegments;
    if (parts.isEmpty) return null;
    final folder = _packageMap[parts[0]];
    if (folder == null) return null;
    final file =
        _resourceProvider.getFile('${folder.path}/${parts.skip(1).join('/')}');
    if (!file.exists) return null;
    return FileSource(file, uri);
  }
}
