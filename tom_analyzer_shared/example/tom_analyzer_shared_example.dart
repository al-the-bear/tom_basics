// Runnable example for Tom Analyzer Shared.
//
// Creates a small Dart project in a temporary directory (sources, a
// pubspec.lock and a .dart_tool/package_config.json written by hand, so no
// `pub get` and no network are needed) and walks through the package:
//
//   1. resolve the project's dependencies from pubspec.lock and split them
//      into cacheable and uncacheable ones;
//   2. resolve the tool-cache root and the summary-cache partition;
//   3. compute dependency-closure fingerprints and the cache file names;
//   4. build a real analyzer summary (a grouped package bundle) of the
//      project and list the libraries it holds;
//   5. stamp that summary and check the stamp;
//   6. inspect the cache with the garbage collector (dry run).
//
// Everything is written below the temporary directory, which is deleted at
// the end. Run from the package folder:
//
//     dart run example/tom_analyzer_shared_example.dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

Future<void> main() async {
  final temp = Directory.systemTemp.createTempSync('tom_analyzer_shared_ex_');
  try {
    final project = p.join(temp.path, 'greeter');
    _writeProject(project);
    // Point the tool cache into the temporary directory, so the example never
    // touches a real workspace cache.
    final env = {ToolCacheLocator.envVariable: p.join(temp.path, 'cache')};

    // 1. Dependencies from pubspec.lock.
    print('== 1. Dependencies from pubspec.lock ==');
    final resolver = DependencyResolver();
    final deps = await resolver.resolveVersionedDependencies(project);
    for (final dep in deps) {
      print(
        '  ${dep.cacheKey.padRight(20)} source=${dep.source.padRight(7)}'
        ' cacheable=${dep.isCacheable}',
      );
    }
    final set = DependencySet.from(deps);
    print('  cacheable: ${set.cacheable.map((d) => d.name).toList()}');
    print('  uncacheable: ${set.uncacheable.map((d) => d.name).toList()}');
    print('  hosted only: ${deps.hosted.map((d) => d.name).toList()}');
    print('  findByName("collection"): ${deps.findByName('collection')}');

    // 2. Where the cache lives.
    print('');
    print('== 2. Tool cache and partition ==');
    final cacheRoot = ToolCacheLocator.resolve(
      startDirectory: project,
      environment: env,
    );
    final fallback = ToolCacheLocator.resolve(
      startDirectory: project,
      environment: const {},
    );
    print('  with TOM_TOOL_CACHE : ${_rel(cacheRoot, temp.path)}');
    print(
      '  without it          : ${_rel(fallback, temp.path)}'
      '  (no buildkit_master.yaml above the project)',
    );
    final cache = SummaryCacheManager(project, environment: env);
    print('  partition           : ${_rel(cache.cacheDirectory, temp.path)}');
    print(
      '  toolchain key       : ${currentToolchainKey()}'
      ' (analyzer major $analyzerMajorVersion)',
    );
    print('  SDK summary file    : ${p.basename(cache.getSdkSummaryPath())}');

    // 3. Closure fingerprints and cache file names.
    print('');
    print('== 3. Fingerprints and cache file names ==');
    final generator = SummaryGenerator(
      cacheManager: cache,
      dependencyResolver: resolver,
    );
    final fingerprints = await generator.computeDependencyFingerprints(
      set.cacheable,
    );
    for (final dep in set.cacheable) {
      final fingerprint = fingerprints[dep.name]!;
      print(
        '  ${dep.name}: closure ${fingerprint.split('\n').skip(1).toList()}',
      );
      print(
        '    -> ${p.basename(cache.getCachePath(dep.name, dep.version, fingerprint: fingerprint))}',
      );
    }
    final missing = await cache.findMissingSummaries(
      set.cacheable,
      fingerprints: fingerprints,
    );
    print('  missing from the cache: ${missing.map((d) => d.name).toList()}');

    // 4. A real summary: one grouped bundle of the project's libraries.
    print('');
    print('== 4. Grouped package bundle ==');
    final bundle = await GroupedPackageBundleBuilder().buildFromDirs([project]);
    print(
      '  ${bundle.packageCount} package(s), ${bundle.libraryCount} '
      'libraries, ${bundle.bytes.length} bytes',
    );
    for (final uri in summaryLibraryUris(bundle.bytes)) {
      print('  holds $uri');
    }

    // 5. Stamp the summary with the toolchain that wrote it.
    print('');
    print('== 5. Summary stamp ==');
    final summaryPath = p.join(temp.path, 'packages.sum');
    File(summaryPath).writeAsBytesSync(bundle.bytes);
    final stamp = SummaryStamp.current(
      embedderYamlPath: bundle.embedderYamlPath,
    );
    print(
      '  current for it before stamping: ${stamp.isCurrentFor(summaryPath)}',
    );
    stamp.writeFor(summaryPath);
    print(
      '  current for it after stamping : ${stamp.isCurrentFor(summaryPath)}',
    );
    final other = SummaryStamp(toolchain: '0.0.0+d0', dartUi: stamp.dartUi);
    print(
      '  current for another toolchain : ${other.isCurrentFor(summaryPath)}',
    );

    // 6. The cache seen by the garbage collector.
    print('');
    print('== 6. Cache maintenance (dry run) ==');
    await cache.ensureCacheDirectory();
    final stats = await cache.getStats();
    print('  partition holds ${stats.summaryCount} summaries');
    final gc = AnalyzerCacheGarbageCollector.resolve(
      startDirectory: project,
      environment: env,
    );
    final current = AnalyzerCacheGarbageCollector.currentPartitionKey();
    for (final part in await gc.listPartitions()) {
      final label = part.key == current ? '${part.key} (current)' : part.key;
      print('  partition $label: ${part.summaryCount} summaries');
    }
    final wouldDelete = await gc.collect(
      cutoff: DateTime.now().add(const Duration(days: 1)),
      keep: {current},
      dryRun: true,
    );
    print(
      '  collect(keep: current) would delete ${wouldDelete.length} '
      'partition(s)',
    );
  } finally {
    temp.deleteSync(recursive: true);
  }
}

/// [path] relative to the temporary directory, for stable output.
String _rel(String path, String temp) =>
    '<temp>/${p.posix.joinAll(p.split(p.relative(path, from: temp)))}';

/// A project `greeter` with two libraries, a pubspec.lock naming one hosted,
/// one path and one git dependency, and a package_config.json for itself.
void _writeProject(String root) {
  void write(String rel, String content) {
    File(p.join(root, rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: greeter
version: 1.0.0
environment:
  sdk: ^3.10.0
''');
  write('lib/greeter.dart', '''
export 'src/greeting.dart';

/// Greets [name].
String greet(String name) => 'Hello, \$name!';
''');
  write('lib/src/greeting.dart', '''
/// A greeting with a [text].
class Greeting {
  const Greeting(this.text);
  final String text;
}
''');
  write('pubspec.lock', '''
packages:
  collection:
    dependency: transitive
    description:
      name: collection
      sha256: "0000000000000000000000000000000000000000000000000000000000000000"
      url: "https://pub.dev"
    source: hosted
    version: "1.19.1"
  local_utils:
    dependency: "direct main"
    description:
      path: "../local_utils"
      relative: true
    source: path
    version: "0.1.0"
  forked_lib:
    dependency: "direct main"
    description:
      path: "."
      ref: main
      resolved-ref: "0123456789abcdef0123456789abcdef01234567"
      url: "https://example.com/forked_lib.git"
    source: git
    version: "2.0.0"
sdks:
  dart: ">=3.10.0 <4.0.0"
''');
  write('.dart_tool/package_config.json', '''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "greeter",
      "rootUri": "../",
      "packageUri": "lib/",
      "languageVersion": "3.10"
    }
  ]
}
''');
}
