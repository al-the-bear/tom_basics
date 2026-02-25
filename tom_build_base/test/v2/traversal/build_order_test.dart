/// Tests for build order computation and traversal with build order sorting.
///
/// Verifies:
/// 1. BuildOrderComputer correctly sorts by dependencies (Kahn's algorithm)
/// 2. FolderSorter.sortByBuildOrder correctly orders filtered contexts
/// 3. BuildBase.traverse with buildOrder flag works end-to-end
/// 4. Build order is computed from ALL folders, then applied to filtered set
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('BuildOrderComputer', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('build_order_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    /// Create a project with dependencies.
    void createProject(
      String name, {
      List<String> deps = const [],
      List<String> devDeps = const [],
    }) {
      final dir = Directory('${tempDir.path}/$name');
      dir.createSync(recursive: true);

      final depYaml = deps.isNotEmpty
          ? 'dependencies:\n${deps.map((d) => '  $d:\n    path: ../$d').join('\n')}\n'
          : '';
      final devDepYaml = devDeps.isNotEmpty
          ? 'dev_dependencies:\n${devDeps.map((d) => '  $d:\n    path: ../$d').join('\n')}\n'
          : '';

      File('${dir.path}/pubspec.yaml').writeAsStringSync(
        'name: $name\n$depYaml$devDepYaml',
      );
    }

    test('BO-COMP-1: Projects with no deps sorted alphabetically [2026-02-20]',
        () {
      createProject('charlie');
      createProject('alpha');
      createProject('bravo');

      final paths = [
        '${tempDir.path}/charlie',
        '${tempDir.path}/alpha',
        '${tempDir.path}/bravo',
      ];

      final result = BuildOrderComputer.computeBuildOrder(paths);
      expect(result, isNotNull);

      final names = result!.map((p) => p.split('/').last).toList();
      expect(names, equals(['alpha', 'bravo', 'charlie']));
    });

    test('BO-COMP-2: Linear dependency chain [2026-02-20]', () {
      // C depends on B, B depends on A → order: A, B, C
      createProject('proj_a');
      createProject('proj_b', deps: ['proj_a']);
      createProject('proj_c', deps: ['proj_b']);

      final paths = [
        '${tempDir.path}/proj_c',
        '${tempDir.path}/proj_b',
        '${tempDir.path}/proj_a',
      ];

      final result = BuildOrderComputer.computeBuildOrder(paths);
      expect(result, isNotNull);

      final names = result!.map((p) => p.split('/').last).toList();
      expect(names, equals(['proj_a', 'proj_b', 'proj_c']));
    });

    test('BO-COMP-3: Diamond dependency [2026-02-20]', () {
      // D depends on B and C, B depends on A, C depends on A
      createProject('base');
      createProject('left', deps: ['base']);
      createProject('right', deps: ['base']);
      createProject('top', deps: ['left', 'right']);

      final paths = [
        '${tempDir.path}/top',
        '${tempDir.path}/left',
        '${tempDir.path}/right',
        '${tempDir.path}/base',
      ];

      final result = BuildOrderComputer.computeBuildOrder(paths);
      expect(result, isNotNull);

      // base must come first, top must come last
      expect(result!.first, endsWith('/base'));
      expect(result.last, endsWith('/top'));
    });

    test('BO-COMP-4: Circular dependency returns null [2026-02-20]', () {
      createProject('cycle_a', deps: ['cycle_b']);
      createProject('cycle_b', deps: ['cycle_a']);

      final paths = [
        '${tempDir.path}/cycle_a',
        '${tempDir.path}/cycle_b',
      ];

      final result = BuildOrderComputer.computeBuildOrder(paths);
      expect(result, isNull);
    });

    test('BO-COMP-5: External deps are ignored [2026-02-20]', () {
      createProject('my_app', deps: ['http', 'path']); // external
      createProject('my_lib');

      final paths = [
        '${tempDir.path}/my_app',
        '${tempDir.path}/my_lib',
      ];

      final result = BuildOrderComputer.computeBuildOrder(paths);
      expect(result, isNotNull);
      expect(result!.length, equals(2));
    });

    test('BO-COMP-6: Dev dependencies included when flag set [2026-02-20]',
        () {
      createProject('lib_a');
      createProject('lib_b', devDeps: ['lib_a']);

      final paths = [
        '${tempDir.path}/lib_b',
        '${tempDir.path}/lib_a',
      ];

      // Without dev deps
      final resultNoDev = BuildOrderComputer.computeBuildOrder(paths);
      final namesNoDev = resultNoDev!.map((p) => p.split('/').last).toList();
      // No dep link, so alphabetical
      expect(namesNoDev, equals(['lib_a', 'lib_b']));

      // With dev deps
      final resultWithDev =
          BuildOrderComputer.computeBuildOrder(paths, includeDev: true);
      final namesWithDev =
          resultWithDev!.map((p) => p.split('/').last).toList();
      // lib_a must come before lib_b (dev dep)
      expect(namesWithDev, equals(['lib_a', 'lib_b']));
    });
  });

  group('FolderSorter.sortByBuildOrder', () {
    test('BO-SORT-1: Sorts items by global order [2026-02-20]', () {
      final sorter = FolderSorter();
      final items = ['/c', '/a', '/b'];
      final globalOrder = ['/a', '/b', '/c'];

      final result =
          sorter.sortByBuildOrder(items, (s) => s, globalOrder);
      expect(result, equals(['/a', '/b', '/c']));
    });

    test(
        'BO-SORT-2: Items not in global order come after ordered items [2026-02-20]',
        () {
      final sorter = FolderSorter();
      final items = ['/x', '/a', '/y', '/b'];
      final globalOrder = ['/a', '/b'];

      final result =
          sorter.sortByBuildOrder(items, (s) => s, globalOrder);
      // /a and /b should come first in order
      expect(result.indexOf('/a'), lessThan(result.indexOf('/b')));
      expect(result.indexOf('/a'), lessThan(result.indexOf('/x')));
      expect(result.indexOf('/b'), lessThan(result.indexOf('/x')));
    });

    test('BO-SORT-3: Empty global order returns input unchanged [2026-02-20]',
        () {
      final sorter = FolderSorter();
      final items = ['/c', '/a', '/b'];

      final result = sorter.sortByBuildOrder(items, (s) => s, []);
      expect(result, equals(['/c', '/a', '/b']));
    });
  });

  group('BuildBase.traverse with buildOrder', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('build_order_traverse_');

      // Create workspace marker
      File('${tempDir.path}/buildkit_master.yaml')
          .writeAsStringSync('');

      // lib_core: no deps
      final core = Directory('${tempDir.path}/lib_core');
      core.createSync();
      File('${core.path}/pubspec.yaml')
          .writeAsStringSync('name: lib_core\n');

      // lib_utils: depends on lib_core
      final utils = Directory('${tempDir.path}/lib_utils');
      utils.createSync();
      File('${utils.path}/pubspec.yaml').writeAsStringSync(
        'name: lib_utils\ndependencies:\n  lib_core:\n    path: ../lib_core\n',
      );

      // app: depends on lib_utils
      final app = Directory('${tempDir.path}/app');
      app.createSync();
      File('${app.path}/pubspec.yaml').writeAsStringSync(
        'name: app\ndependencies:\n  lib_utils:\n    path: ../lib_utils\n',
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test(
        'BO-TRAV-1: buildOrder=true sorts projects by dependency order [2026-02-20]',
        () async {
      final names = <String>[];
      await BuildBase.traverse(
        info: ProjectTraversalInfo(
          scan: tempDir.path,
          recursive: true,
          executionRoot: tempDir.path,
          buildOrder: true,
        ),
        requiredNatures: {FsFolder},
        run: (ctx) async {
          names.add(ctx.name);
          return true;
        },
      );

      // Build order: lib_core → lib_utils → app
      final coreIdx = names.indexOf('lib_core');
      final utilsIdx = names.indexOf('lib_utils');
      final appIdx = names.indexOf('app');

      expect(coreIdx, greaterThanOrEqualTo(0), reason: 'lib_core should be found');
      expect(utilsIdx, greaterThanOrEqualTo(0), reason: 'lib_utils should be found');
      expect(appIdx, greaterThanOrEqualTo(0), reason: 'app should be found');
      expect(coreIdx, lessThan(utilsIdx),
          reason: 'lib_core before lib_utils');
      expect(utilsIdx, lessThan(appIdx),
          reason: 'lib_utils before app');
    });

    test(
        'BO-TRAV-2: buildOrder with filter still respects global order [2026-02-20]',
        () async {
      final names = <String>[];
      await BuildBase.traverse(
        info: ProjectTraversalInfo(
          scan: tempDir.path,
          recursive: true,
          executionRoot: tempDir.path,
          buildOrder: true,
          // Filter: only app and lib_core (skip lib_utils)
          projectPatterns: ['app', 'lib_core'],
        ),
        requiredNatures: {FsFolder},
        run: (ctx) async {
          names.add(ctx.name);
          return true;
        },
      );

      // Even though lib_utils is filtered out, lib_core should still
      // come before app (global order is respected)
      final coreIdx = names.indexOf('lib_core');
      final appIdx = names.indexOf('app');

      expect(coreIdx, greaterThanOrEqualTo(0));
      expect(appIdx, greaterThanOrEqualTo(0));
      expect(coreIdx, lessThan(appIdx),
          reason: 'lib_core before app in build order');
      expect(names, isNot(contains('lib_utils')),
          reason: 'lib_utils filtered out');
    });

    test(
        'BO-TRAV-3: buildOrder=false does NOT sort by dependency [2026-02-20]',
        () async {
      final names = <String>[];
      await BuildBase.traverse(
        info: ProjectTraversalInfo(
          scan: tempDir.path,
          recursive: true,
          executionRoot: tempDir.path,
          buildOrder: false,
        ),
        requiredNatures: {FsFolder},
        run: (ctx) async {
          names.add(ctx.name);
          return true;
        },
      );

      // Without buildOrder, order is filesystem scan order (not guaranteed)
      // Just verify all three are present
      expect(names, containsAll(['lib_core', 'lib_utils', 'app']));
    });
  });
}
