/// `sumkit` — a cache-coverage reporter that marries the two libraries this
/// sample teaches: `tom_build_base` (workspace traversal) and
/// `tom_analyzer_shared` (analyzer-summary caching).
///
/// A code generator built on the Dart `analyzer` pays a tax on every run: before
/// it can look at *your* code it must analyse *all your dependencies*. For the
/// stable ones (hosted on pub.dev, or shipped with an SDK) that work is
/// repeated, identical, on every run — so `tom_analyzer_shared` caches an
/// analyzer **summary** (`.sum` file) per dependency, keyed by `name@version`,
/// and the next run loads the summary instead of re-analysing the source.
///
/// `sumkit` is the *pre-flight* for that cache. For every Dart project in a
/// workspace it answers: how many dependencies are cacheable, how many of those
/// summaries are already on disk (cache hits), and how many a generator would
/// still have to build (the misses — the work the cache saves). Run it with
/// `--warm` and it fills the cache so the next run reports all-hits — the
/// cold→warm payoff this sample is about.
///
/// ## What is real here, and what is a stand-in
///
/// Everything that *decides* hits vs misses is real `tom_analyzer_shared` code:
/// `DependencyResolver` parses `pubspec.lock`, `DependencySet` partitions by
/// cacheability, and `SummaryCacheManager` is the actual on-disk `.sum` cache
/// (`hasSummary` / `findMissingSummaries` / `getStats`). The *one* thing this
/// sample fakes is the summary **bytes**: producing a genuine analyzer summary
/// needs the SDK and the pub cache and is not hermetic, so `--warm` writes a
/// tiny labelled placeholder instead of invoking the analyzer. The production
/// one-call path that fills the cache for real is
/// `runSummaryCacheStage(projectRoot)` — see the README. The cache-lookup half
/// `sumkit` demonstrates is identical whether the bytes came from the analyzer
/// or from here.
///
/// This file is "the tool". `bin/sumkit.dart` is the thin entrypoint, and the
/// `example/` files each exercise one facet against a throwaway fixture tree.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';
import 'package:tom_build_base/tom_build_base.dart';

/// The declarative description of the tool — an immutable `const` value.
///
/// `mode: ToolMode.singleCommand` means there is exactly one operation, invoked
/// as `sumkit [options]` (not `sumkit <subcommand>`). The tool-level
/// `requiredNatures` filter restricts traversal to Dart projects, and the two
/// `globalOptions` are flags the executor reads from `args.extraOptions`.
const sumkitTool = ToolDefinition(
  name: 'sumkit',
  description: 'Report analyzer-summary cache coverage for the Dart projects '
      'in a workspace (and optionally warm the cache).',
  version: '1.0.0',
  mode: ToolMode.singleCommand,
  requiredNatures: {DartProjectFolder},
  globalOptions: [
    OptionDefinition.flag(
      name: 'warm',
      description: 'Write placeholder summaries for the missing cacheable '
          'dependencies (stand-in for real summary generation).',
    ),
    OptionDefinition.flag(
      name: 'rebuild',
      description: 'Clear the summary cache before scanning.',
    ),
  ],
);

/// The one behaviour the framework cannot supply: what to do per project.
///
/// A single-command tool registers exactly one executor under the key
/// `'default'`. We supply both entry points so the tool is **nestable**:
/// `onExecute` runs during a normal traversal, and `onExecuteWithoutTraversal`
/// runs in `--nested` mode, where a host tool has already walked to a project
/// and we scan the current working directory once. Both funnel through the same
/// [_scan], so a `sumkit` report is identical standalone or nested.
Map<String, CommandExecutor> sumkitExecutors(StringSink out) {
  Future<ItemResult> scan(CommandContext context, CliArgs args) =>
      _scan(context, args, out);

  return {
    'default': CallbackExecutor(
      onExecute: scan,
      onExecuteWithoutTraversal: (args) async {
        final cwd = Directory.current.path;
        final context = CommandContext(
          fsFolder: FsFolder(path: cwd),
          natures: const [],
          executionRoot: cwd,
        );
        return ToolResult.fromItems([await scan(context, args)]);
      },
    ),
  };
}

/// Scan one project: resolve its dependencies, look them up in the shared
/// cache, write one report line, and (optionally) warm the cache.
///
/// The cache lives at `<executionRoot>/.tom/analyzer-cache/` — one cache per
/// *workspace*, deliberately, so projects that share a dependency share its
/// summary. That sharing is why warming `data_layer` (which needs `meta`) makes
/// `meta` a cache hit for every later project that also needs it.
Future<ItemResult> _scan(
  CommandContext context,
  CliArgs args,
  StringSink out,
) async {
  final cache = SummaryCacheManager(context.executionRoot);
  if (args.extraOptions['rebuild'] == true) {
    await cache.clearCache();
  }

  final resolver = DependencyResolver();
  final List<PackageDependency> deps;
  try {
    deps = await resolver.resolveVersionedDependencies(context.path);
  } on FileSystemException {
    // No pubspec.lock — a real generator could not analyse this project yet
    // (`dart pub get` has not run), so there is nothing to cache. Skip it.
    out.writeln('${context.name}: skipped (no pubspec.lock)');
    return ItemResult.skipped(
      path: context.path,
      name: context.name,
      message: 'no pubspec.lock',
    );
  }

  // Only hosted + SDK packages have version-stable, cacheable summaries; path
  // and git dependencies are re-analysed from source every run.
  final set = DependencySet.from(deps);
  final missing = await cache.findMissingSummaries(set.cacheable);
  final hits = set.cacheable.length - missing.length;

  if (args.extraOptions['warm'] == true) {
    for (final dep in missing) {
      await cache.writeSummary(dep.name, dep.version, _placeholderSummary(dep));
    }
    out.writeln('${context.name}: warmed ${missing.length} '
        '($hits already cached, ${set.uncacheable.length} uncacheable)');
    return ItemResult.success(
      path: context.path,
      name: context.name,
      message: 'warmed ${missing.length}',
    );
  }

  out.writeln('${context.name}: ${set.cacheable.length} cacheable, '
      '$hits cached, ${missing.length} missing '
      '(${set.uncacheable.length} uncacheable)');
  return ItemResult.success(
    path: context.path,
    name: context.name,
    message: '${missing.length} missing',
  );
}

/// A placeholder for a real analyzer summary.
///
/// `SummaryCacheManager.hasSummary` only checks that the `.sum` file exists and
/// is non-empty, so any non-empty bytes make a dependency read as "cached". A
/// real summary is the analyzer's serialised type information; this is a clearly
/// labelled stand-in so the cache-lookup half of the pipeline can be exercised
/// offline. See the library doc comment for the real generation path.
Uint8List _placeholderSummary(PackageDependency dep) {
  return Uint8List.fromList('PLACEHOLDER-SUMMARY ${dep.cacheKey}\n'.codeUnits);
}

/// Build a [ToolRunner] for the tool, wired to a single [output] sink.
///
/// The executor writes its report lines to [output]; pass a `StringBuffer` to
/// capture everything for a deterministic, testable run (that is how the
/// `example/` files work). With no sink it writes to `stdout`, which is what
/// `bin/sumkit.dart` wants.
ToolRunner sumkitRunner({StringSink? output}) {
  final sink = output ?? stdout;
  return ToolRunner(
    tool: sumkitTool,
    executors: sumkitExecutors(sink),
    output: sink,
    verbose: false,
  );
}
