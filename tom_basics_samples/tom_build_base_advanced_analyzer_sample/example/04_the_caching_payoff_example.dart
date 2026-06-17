// The caching payoff: a miss becomes a hit, and stays one.
//
// This is the whole point of the cache, in miniature. Take the `data` project
// (one cacheable dependency, `meta`). Cold, that dependency is a miss — the work
// a generator would have to do. Write its summary once, and the very next check
// reports zero missing: the generator can load the summary instead of
// re-analysing the source. Run after run, that miss never comes back (until the
// version changes and the cache key with it).
//
// We write a clearly-labelled placeholder instead of a real analyzer summary
// (`hasSummary` only checks the file exists and is non-empty, so any non-empty
// bytes "warm" the cache). Generating the real bytes needs the SDK and the pub
// cache and is not hermetic — the production one-call path is
// `runSummaryCacheStage`, described in the README. The cache-lookup half shown
// here is identical either way.
//
// Run with: dart run example/04_the_caching_payoff_example.dart
import 'dart:typed_data';

import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

import 'fixture.dart';

Future<void> main() async {
  final workspace = await createFixtureWorkspace();
  try {
    final cache = SummaryCacheManager(workspace.path);
    final deps = await DependencyResolver()
        .resolveVersionedDependencies('${workspace.path}/data');
    final cacheable = deps.cacheable;

    // Cold: the work the cache will save.
    final coldMissing = await cache.findMissingSummaries(cacheable);
    print('cold:  ${coldMissing.length} missing '
        '(${coldMissing.map((d) => d.cacheKey).join(', ')})');

    // Warm it: write a (placeholder) summary for each missing dependency.
    for (final dep in coldMissing) {
      await cache.writeSummary(dep.name, dep.version, _placeholder(dep));
    }

    // Warm: the same check now finds nothing to do.
    final warmMissing = await cache.findMissingSummaries(cacheable);
    print('warm:  ${warmMissing.length} missing');
    print('hasSummary(meta@1.16.0): ${await cache.hasSummary('meta', '1.16.0')}');

    final stats = await cache.getStats();
    print('cached summaries on disk: ${stats.summaryCount}');
  } finally {
    await disposeFixture(workspace);
  }

  // expected output:
  // cold:  1 missing (meta@1.16.0)
  // warm:  0 missing
  // hasSummary(meta@1.16.0): true
  // cached summaries on disk: 1
}

/// A clearly-labelled stand-in for a real analyzer summary (see the file's
/// header comment for why the real bytes are out of scope for a hermetic run).
Uint8List _placeholder(PackageDependency dep) =>
    Uint8List.fromList('PLACEHOLDER-SUMMARY ${dep.cacheKey}\n'.codeUnits);
