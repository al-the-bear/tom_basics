// The cacheability rule: which dependencies can have a reusable summary.
//
// An analyzer summary is keyed by an exact `name@version`, so it is only worth
// caching when that pair is *stable across machines and runs*. That is true for
// `hosted` packages (a pub.dev release is immutable) and `sdk` packages (pinned
// to an SDK version), but not for `path` or `git` dependencies, whose source
// can change under the same version string. `PackageDependency.isCacheable`
// encodes exactly that rule, and `DependencySet.from` partitions a list by it.
//
// This is the pure-data foundation: no files, no traversal, no cache — just the
// classification every later example builds on.
//
// Run with: dart run example/01_the_cacheability_rule_example.dart
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

void main() {
  final deps = <PackageDependency>[
    const PackageDependency(
      name: 'meta',
      version: '1.16.0',
      source: 'hosted',
      hostedUrl: 'https://pub.dev',
    ),
    const PackageDependency(
      name: 'collection',
      version: '1.19.1',
      source: 'hosted',
      hostedUrl: 'https://pub.dev',
    ),
    const PackageDependency(
      name: 'flutter',
      version: '3.27.0',
      source: 'sdk',
      sdkName: 'flutter',
    ),
    const PackageDependency(
      name: 'data_layer',
      version: '1.0.0',
      source: 'path',
      path: '../data',
    ),
    const PackageDependency(
      name: 'local_fork',
      version: 'git',
      source: 'git',
    ),
  ];

  // Each dependency carries its own verdict and cache key.
  for (final dep in deps) {
    final mark = dep.isCacheable ? 'cacheable' : 'uncacheable';
    print('${dep.cacheKey.padRight(18)} ${dep.source.padRight(7)} $mark');
  }

  // DependencySet.from applies the same rule to split a whole list at once.
  final set = DependencySet.from(deps);
  print('---');
  print('cacheable:   ${set.cacheable.map((d) => d.name).join(', ')}');
  print('uncacheable: ${set.uncacheable.map((d) => d.name).join(', ')}');

  // expected output:
  // meta@1.16.0        hosted  cacheable
  // collection@1.19.1  hosted  cacheable
  // flutter@3.27.0     sdk     cacheable
  // data_layer@1.0.0   path    uncacheable
  // local_fork@git     git     uncacheable
  // ---
  // cacheable:   meta, collection, flutter
  // uncacheable: data_layer, local_fork
}
