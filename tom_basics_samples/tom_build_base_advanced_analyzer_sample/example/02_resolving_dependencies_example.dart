// Resolving a project's dependencies from its pubspec.lock.
//
// Cacheability needs *exact* versions, and the only place those live is
// `pubspec.lock` — the file `dart pub get` writes once the dependency graph is
// solved. `DependencyResolver.resolveVersionedDependencies` parses that file
// into `PackageDependency` values (sorted by name), and the
// `DependencyListExtensions` (`.hosted`, `.paths`, `.cacheable`, `.findByName`)
// slice the result the way a generator would.
//
// This example resolves the `app` project from the fixture: three hosted
// dependencies plus one path dependency. Where example 01 hand-built the
// values, here they come from a real (fixture) lock file.
//
// Run with: dart run example/02_resolving_dependencies_example.dart
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

import 'fixture.dart';

Future<void> main() async {
  final workspace = await createFixtureWorkspace();
  try {
    final resolver = DependencyResolver();
    final deps = await resolver
        .resolveVersionedDependencies('${workspace.path}/app');

    print('resolved ${deps.length} dependencies (sorted by name):');
    for (final dep in deps) {
      print('  ${dep.cacheKey.padRight(20)} ${dep.source}');
    }

    print('hosted:    ${deps.hosted.map((d) => d.name).join(', ')}');
    print('paths:     ${deps.paths.map((d) => d.name).join(', ')}');
    print('cacheable: ${deps.cacheable.map((d) => d.name).join(', ')}');
    print('findByName(http): ${deps.findByName('http')?.cacheKey}');
  } finally {
    await disposeFixture(workspace);
  }

  // expected output:
  // resolved 4 dependencies (sorted by name):
  //   collection@1.19.1    hosted
  //   http@1.2.2           hosted
  //   meta@1.16.0          hosted
  //   service_layer@1.2.0  path
  // hosted:    collection, http, meta
  // paths:     service_layer
  // cacheable: collection, http, meta
  // findByName(http): http@1.2.2
}
