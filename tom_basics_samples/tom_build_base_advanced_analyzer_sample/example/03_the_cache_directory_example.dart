// The cache directory: where summaries live and how a miss is detected.
//
// `SummaryCacheManager` owns one on-disk cache per workspace, at
// `<workspace>/.tom/analyzer-cache/`, with one `{name}@{version}.sum` file per
// cached dependency. A "cache hit" is nothing more exotic than *that file
// existing and being non-empty* (`hasSummary`); `findMissingSummaries` is just
// that check run over a list, keeping only the cacheable ones that are absent.
//
// This example points a cache manager at a fresh workspace — a **cold cache** —
// and confirms the obvious: every cacheable dependency is missing, and the
// cache holds zero summaries. The next example fills it.
//
// Run with: dart run example/03_the_cache_directory_example.dart
import 'package:path/path.dart' as p;
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

import 'fixture.dart';

Future<void> main() async {
  final workspace = await createFixtureWorkspace();
  try {
    final cache = SummaryCacheManager(workspace.path);

    // The cache file for a dependency is named after its cache key.
    print('cache file for meta@1.16.0: '
        '${p.basename(cache.getCachePath('meta', '1.16.0'))}');

    // Resolve one project's cacheable dependencies and check them, cold.
    final deps = await DependencyResolver()
        .resolveVersionedDependencies('${workspace.path}/service');
    final cacheable = deps.cacheable;
    final missing = await cache.findMissingSummaries(cacheable);

    print('hasSummary(meta@1.16.0): ${await cache.hasSummary('meta', '1.16.0')}');
    print('cacheable: ${cacheable.length}, missing: ${missing.length}');
    print('missing names: ${missing.map((d) => d.name).join(', ')}');

    final stats = await cache.getStats();
    print('cached summaries on disk: ${stats.summaryCount}');
  } finally {
    await disposeFixture(workspace);
  }

  // expected output:
  // cache file for meta@1.16.0: meta@1.16.0.sum
  // hasSummary(meta@1.16.0): false
  // cacheable: 2, missing: 2
  // missing names: collection, meta
  // cached summaries on disk: 0
}
