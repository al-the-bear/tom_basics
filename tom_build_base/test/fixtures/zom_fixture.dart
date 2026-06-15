import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Test support for the `zom_analyzer_test` workspace fixture.
///
/// The multi-language `zom_workspaces` projects used to live at the real
/// workspace root, which made the traversal/nature tests depend on whatever
/// happened to be checked out there. They are now versioned with this package
/// under `test_fixtures/zom_workspaces/zom_analyzer_test` and copied into a
/// throwaway temp directory for the duration of each test run, so the real
/// workspace is never read or mutated and runs stay hermetic.
///
/// The fixture lives in `test_fixtures/` (a sibling of `test/`) rather than
/// inside `test/` on purpose: the fixture projects contain their own
/// `*_test.dart` files, and `dart test` auto-discovers any such file beneath
/// `test/`. Keeping the fixture out of `test/` stops the runner from trying to
/// execute fixture tests as part of this package's suite.

/// Cwd-independent absolute path to the `tom_build_base` package root.
///
/// `Directory.current` is **process-global** and shared across the isolates
/// that `package:test` spawns for each suite. Tests that `chdir` into a temp
/// workspace (e.g. `features_test`, `tool_runner_test`) therefore mutate the
/// cwd seen by *every* concurrently running suite, which used to make the
/// fixture/workspace-root resolution here intermittently walk up from a temp
/// directory and fail. Resolving the root from the package config instead is
/// independent of the live cwd, so it stays correct under concurrency.
String? _packageRootCache;

/// Resolves and caches the package root via the package config so it does not
/// depend on the mutable process cwd. Call (and `await`) this once in
/// `setUpAll` before using any path helper below.
Future<String> resolvePackageRoot() async {
  final cached = _packageRootCache;
  if (cached != null) return cached;
  final libUri = await Isolate.resolvePackageUri(
    Uri.parse('package:tom_build_base/tom_build_base.dart'),
  );
  if (libUri == null) {
    throw StateError(
      'Could not resolve package:tom_build_base — is the package config '
      'available to this test isolate?',
    );
  }
  // libUri => <root>/lib/tom_build_base.dart, so the package root is two
  // directories up from the resolved library file.
  final root = p.dirname(p.dirname(libUri.toFilePath()));
  return _packageRootCache = root;
}

/// The resolved package root once [resolvePackageRoot] has run. Falls back to
/// the process cwd only for legacy callers that never resolved it (which
/// reintroduces the cwd race — every helper here should be reached after a
/// `resolvePackageRoot()` in `setUpAll`).
String get _packageRoot => _packageRootCache ?? Directory.current.path;

/// Absolute path to the checked-in fixture inside this package.
String get zomFixtureSource => p.join(
      _packageRoot,
      'test_fixtures',
      'zom_workspaces',
      'zom_analyzer_test',
    );

/// Copies the checked-in `zom_analyzer_test` fixture into a fresh temporary
/// directory and returns the path to the copied `zom_analyzer_test` root.
///
/// Pair every call with [removeZomFixture] in a `tearDown`/`tearDownAll`.
String installZomFixture() {
  final source = Directory(zomFixtureSource);
  if (!source.existsSync()) {
    throw StateError(
      'zom fixture not found at ${source.path}. Expected it to be checked '
      'into test/fixtures/zom_workspaces/zom_analyzer_test.',
    );
  }
  final tempRoot = Directory.systemTemp.createTempSync('zom_fixture_');
  final dest = Directory(p.join(tempRoot.path, 'zom_analyzer_test'));
  _copyDirectory(source, dest);
  return dest.path;
}

/// Builds a throwaway workspace that contains BOTH the zom fixture (under
/// `zom_workspaces/zom_analyzer_test`) and a synthetic regular (non-zom) Dart
/// package, then returns the workspace root.
///
/// Used by tests that verify regular and test projects are discovered side by
/// side. Remove it with [removeWorkspace].
String installMixedWorkspace() {
  final tempRoot = Directory.systemTemp.createTempSync('zom_mixed_');

  final zomDest = Directory(
    p.join(tempRoot.path, 'zom_workspaces', 'zom_analyzer_test'),
  );
  _copyDirectory(Directory(zomFixtureSource), zomDest);

  // Synthetic regular package: pubspec + lib/src/ → DartPackageFolder, which
  // is a DartProjectFolder, so traversal with that required nature finds it.
  final regular = Directory(p.join(tempRoot.path, 'tom_regular_demo'));
  Directory(p.join(regular.path, 'lib', 'src')).createSync(recursive: true);
  File(p.join(regular.path, 'pubspec.yaml')).writeAsStringSync(
    'name: tom_regular_demo\n'
    'version: 1.0.0\n'
    'environment:\n'
    '  sdk: ">=3.0.0 <4.0.0"\n',
  );
  File(p.join(regular.path, 'lib', 'src', 'tom_regular_demo_base.dart'))
      .writeAsStringSync('const demo = true;\n');
  File(p.join(regular.path, 'lib', 'tom_regular_demo.dart'))
      .writeAsStringSync("export 'src/tom_regular_demo_base.dart';\n");

  return tempRoot.path;
}

/// Builds a throwaway workspace containing three packages, each with a
/// `tom_repository.yaml` declaring a `repository_id` and `name`, then returns
/// the workspace root.
///
/// Used by the RepositoryIdLookup tests so they resolve IDs against controlled
/// fixture metadata instead of whatever `tom_repository.yaml` files happen to
/// exist at the current working directory. Remove it with [removeWorkspace].
String installRepoIdFixture() {
  final tempRoot = Directory.systemTemp.createTempSync('zom_repoid_');

  void writeRepo(String folder, String id, String name) {
    final dir = Directory(p.join(tempRoot.path, folder));
    dir.createSync(recursive: true);
    File(p.join(dir.path, 'tom_repository.yaml')).writeAsStringSync(
      'repository_id: $id\n'
      'name: $name\n',
    );
  }

  writeRepo('basics', 'BSC', 'tom_module_basics');
  writeRepo('d4rt', 'D4', 'tom_module_d4rt');
  writeRepo('crypto', 'CRPT', 'tom_module_crypto');

  return tempRoot.path;
}

/// Builds a throwaway Dart project that itself contains a nested Dart project,
/// then returns the outer project root.
///
/// Used by the FolderScanner non-recursive test: scanning the root with
/// `recursive: false` must stop at the outer project (the scanner enters
/// container directories but not project directories), so only the root is
/// returned. Remove it with [removeWorkspace].
String installNestedProjectFixture() {
  final tempRoot = Directory.systemTemp.createTempSync('zom_nested_');

  File(p.join(tempRoot.path, 'pubspec.yaml')).writeAsStringSync(
    'name: zom_outer\n'
    'version: 1.0.0\n'
    'environment:\n'
    '  sdk: ">=3.0.0 <4.0.0"\n',
  );

  final inner = Directory(p.join(tempRoot.path, 'inner'));
  inner.createSync(recursive: true);
  File(p.join(inner.path, 'pubspec.yaml')).writeAsStringSync(
    'name: zom_inner\n'
    'version: 1.0.0\n'
    'environment:\n'
    '  sdk: ">=3.0.0 <4.0.0"\n',
  );

  return tempRoot.path;
}

/// Returns the nearest ancestor of [start] (default: the resolved package
/// root) that contains a `.git` entry — i.e. a real git working tree.
///
/// The GitFolder tests need an actual repository to inspect; resolving it by
/// walking up keeps them independent of how deeply this package is nested.
String nearestGitRoot([String? start]) {
  var dir = Directory(start ?? _packageRoot).absolute;
  while (true) {
    final gitDir = Directory(p.join(dir.path, '.git'));
    final gitFile = File(p.join(dir.path, '.git'));
    if (gitDir.existsSync() || gitFile.existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'No .git found above ${start ?? Directory.current.path}',
      );
    }
    dir = parent;
  }
}

/// Returns the enclosing multi-repo workspace root — the nearest ancestor of
/// [start] (default: the resolved package root) that contains a
/// `tom_workspace.yaml` marker.
///
/// The git-traversal / submodule / module-filter tests scan the real workspace
/// (which holds many nested repositories under e.g. `xternal/`), so they need
/// the superproject root rather than the leaf repo enclosing this package.
/// Falls back to [nearestGitRoot] when no marker is found.
String workspaceRootDir([String? start]) {
  final base = start ?? _packageRoot;
  var dir = Directory(base).absolute;
  while (true) {
    if (File(p.join(dir.path, 'tom_workspace.yaml')).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      return nearestGitRoot(start);
    }
    dir = parent;
  }
}

/// Removes a temp tree created by [installZomFixture].
///
/// Accepts the `zom_analyzer_test` path it returned; the enclosing temp
/// directory is removed.
void removeZomFixture(String zomAnalyzerTestPath) {
  removeWorkspace(p.dirname(zomAnalyzerTestPath));
}

/// Removes a temp directory tree (workspace root) if it still exists.
void removeWorkspace(String root) {
  final dir = Directory(root);
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
}

void _copyDirectory(Directory source, Directory dest) {
  dest.createSync(recursive: true);
  for (final entity in source.listSync(recursive: false)) {
    final newPath = p.join(dest.path, p.basename(entity.path));
    if (entity is Directory) {
      _copyDirectory(entity, Directory(newPath));
    } else if (entity is File) {
      entity.copySync(newPath);
    }
  }
}
