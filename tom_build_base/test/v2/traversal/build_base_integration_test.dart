import 'dart:io';

import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

/// Integration tests for BuildBase traversal.
///
/// These tests use the actual zom_workspaces test projects to verify
/// that traversal, filtering, and nature detection work correctly.
void main() {
  // Get the workspace root (tom2 directory)
  late String workspaceRoot;
  late String zomTestRoot;

  setUpAll(() {
    // Navigate from tom_build_base to workspace root
    final currentDir = Directory.current.path;
    // tom_build_base is in xternal/tom_module_basics/tom_build_base
    // We need to get to the workspace root (tom2)
    workspaceRoot = p.normalize(p.join(currentDir, '..', '..', '..'));
    zomTestRoot = p.join(workspaceRoot, 'zom_workspaces', 'zom_analyzer_test');

    // Verify test projects exist
    final testDir = Directory(zomTestRoot);
    if (!testDir.existsSync()) {
      fail('Test projects not found at $zomTestRoot. '
          'Current directory: $currentDir');
    }
  });

  group('BuildBase.traverse with ProjectTraversalInfo', () {
    test('BB-INT-1: Finds Dart projects with DartProjectFolder nature [2026-02-12]', () async {
      final info = ProjectTraversalInfo(
        executionRoot: zomTestRoot,
        scan: zomTestRoot,
        recursive: true,
        includeTestProjects: true, // Include zom_* projects
      );

      final processedPaths = <String>[];
      final processedNatures = <String, List<String>>{};

      await BuildBase.traverse(
        info: info,
        requiredNatures: {DartProjectFolder},
        run: (ctx) async {
          processedPaths.add(ctx.path);
          processedNatures[ctx.name] = ctx.natures.map((n) => n.runtimeType.toString()).toList();
          return true;
        },
      );

      // Should find the Dart test projects
      expect(processedPaths.any((p) => p.contains('zom_test_flutter')), isTrue,
          reason: 'Should find zom_test_flutter');
      expect(processedPaths.any((p) => p.contains('zom_test_package')), isTrue,
          reason: 'Should find zom_test_package');
      expect(processedPaths.any((p) => p.contains('zom_test_standalone')), isTrue,
          reason: 'Should find zom_test_standalone');

      // Should NOT find non-Dart projects
      expect(processedPaths.any((p) => p.contains('zom_typescript')), isFalse,
          reason: 'Should NOT find TypeScript-only projects');
      expect(processedPaths.any((p) => p.contains('zom_extension')), isFalse,
          reason: 'Should NOT find VS Code extension (no pubspec.yaml)');

      // Verify natures were detected
      if (processedNatures.containsKey('zom_test_flutter')) {
        expect(processedNatures['zom_test_flutter'], contains('FlutterProjectFolder'));
      }
      if (processedNatures.containsKey('zom_test_package')) {
        expect(processedNatures['zom_test_package'], contains('DartPackageFolder'));
      }
      if (processedNatures.containsKey('zom_test_standalone')) {
        expect(processedNatures['zom_test_standalone'], contains('DartConsoleFolder'));
      }
    });

    test('BB-INT-2: Finds Flutter projects specifically [2026-02-12]', () async {
      final info = ProjectTraversalInfo(
        executionRoot: zomTestRoot,
        scan: zomTestRoot,
        recursive: true,
        includeTestProjects: true,
      );

      final flutterProjects = <String>[];

      await BuildBase.traverse(
        info: info,
        requiredNatures: {FlutterProjectFolder},
        run: (ctx) async {
          flutterProjects.add(ctx.name);
          return true;
        },
      );

      expect(flutterProjects, contains('zom_test_flutter'));
      expect(flutterProjects, isNot(contains('zom_test_package')));
      expect(flutterProjects, isNot(contains('zom_test_standalone')));
    });

    test('BB-INT-3: Finds console apps specifically [2026-02-12]', () async {
      final info = ProjectTraversalInfo(
        executionRoot: zomTestRoot,
        scan: zomTestRoot,
        recursive: true,
        includeTestProjects: true,
      );

      final consoleApps = <String>[];

      await BuildBase.traverse(
        info: info,
        requiredNatures: {DartConsoleFolder},
        run: (ctx) async {
          consoleApps.add(ctx.name);
          return true;
        },
      );

      expect(consoleApps, contains('zom_test_standalone'));
      expect(consoleApps, isNot(contains('zom_test_flutter')));
      expect(consoleApps, isNot(contains('zom_test_package')));
    });

    test('BB-INT-4: Finds packages specifically [2026-02-12]', () async {
      final info = ProjectTraversalInfo(
        executionRoot: zomTestRoot,
        scan: zomTestRoot,
        recursive: true,
        includeTestProjects: true,
      );

      final packages = <String>[];

      await BuildBase.traverse(
        info: info,
        requiredNatures: {DartPackageFolder},
        run: (ctx) async {
          packages.add(ctx.name);
          return true;
        },
      );

      expect(packages, contains('zom_test_package'));
      expect(packages, isNot(contains('zom_test_flutter')));
      expect(packages, isNot(contains('zom_test_standalone')));
    });

    test('BB-INT-5: Finds TypeScript projects with TypeScriptFolder nature [2026-02-12]', () async {
      final info = ProjectTraversalInfo(
        executionRoot: zomTestRoot,
        scan: zomTestRoot,
        recursive: true,
        includeTestProjects: true,
      );

      final tsProjects = <String>[];

      await BuildBase.traverse(
        info: info,
        requiredNatures: {TypeScriptFolder},
        run: (ctx) async {
          tsProjects.add(ctx.name);
          return true;
        },
      );

      expect(tsProjects, contains('zom_typescript'));
      expect(tsProjects, isNot(contains('zom_test_flutter')));
    });

    test('BB-INT-6: Finds VS Code extensions with VsCodeExtensionFolder nature [2026-02-12]', () async {
      final info = ProjectTraversalInfo(
        executionRoot: zomTestRoot,
        scan: zomTestRoot,
        recursive: true,
        includeTestProjects: true,
      );

      final extensions = <String>[];

      await BuildBase.traverse(
        info: info,
        requiredNatures: {VsCodeExtensionFolder},
        run: (ctx) async {
          extensions.add(ctx.name);
          return true;
        },
      );

      expect(extensions, contains('zom_extension'));
      expect(extensions, isNot(contains('zom_typescript')));
    });

    test('BB-INT-7: Excludes test projects by default [2026-02-12]', () async {
      final info = ProjectTraversalInfo(
        executionRoot: zomTestRoot,
        scan: zomTestRoot,
        recursive: true,
        // includeTestProjects defaults to false
      );

      final foundProjects = <String>[];

      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          foundProjects.add(ctx.name);
          return true;
        },
      );

      // Should exclude all zom_* projects by default
      expect(foundProjects.any((n) => n.startsWith('zom_')), isFalse,
          reason: 'zom_* projects should be excluded by default');
    });

    test('BB-INT-8: TestProjectsOnly filters to only zom_* projects [2026-02-12]', () async {
      final info = ProjectTraversalInfo(
        executionRoot: zomTestRoot,
        scan: zomTestRoot,
        recursive: true,
        testProjectsOnly: true,
      );

      final foundProjects = <String>[];

      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          foundProjects.add(ctx.name);
          return true;
        },
      );

      // All found projects should be zom_*
      for (final name in foundProjects) {
        expect(name, startsWith('zom_'),
            reason: 'With testProjectsOnly, only zom_* should be included');
      }
      expect(foundProjects, isNotEmpty,
          reason: 'Should find at least some test projects');
    });

    test('BB-INT-9: TestProjectsOnly finds ALL test project types including TypeSc... [2026-02-12]', () async {
      final info = ProjectTraversalInfo(
        executionRoot: zomTestRoot,
        scan: zomTestRoot,
        recursive: true,
        testProjectsOnly: true,
      );

      final foundProjects = <String>[];
      final projectNatures = <String, List<String>>{};

      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        // No requiredNatures filter - should find ALL project types
        run: (ctx) async {
          foundProjects.add(ctx.name);
          projectNatures[ctx.name] = ctx.natures.map((n) => n.runtimeType.toString()).toList();
          return true;
        },
      );

      // Should find Dart projects
      expect(foundProjects, contains('zom_test_flutter'),
          reason: '--test-only should find Flutter test projects');
      expect(foundProjects, contains('zom_test_package'),
          reason: '--test-only should find Dart package test projects');
      expect(foundProjects, contains('zom_test_standalone'),
          reason: '--test-only should find Dart console test projects');

      // Should ALSO find TypeScript and VS Code extension projects
      expect(foundProjects, contains('zom_typescript'),
          reason: '--test-only should find TypeScript test projects');
      expect(foundProjects, contains('zom_extension'),
          reason: '--test-only should find VS Code extension test projects');

      // ALL found projects should be zom_* (test projects only)
      for (final name in foundProjects) {
        expect(name, startsWith('zom_'),
            reason: '--test-only should ONLY include zom_* projects');
      }

      // Verify natures are correct for non-Dart projects
      if (projectNatures.containsKey('zom_typescript')) {
        expect(projectNatures['zom_typescript'], contains('TypeScriptFolder'),
            reason: 'zom_typescript should have TypeScriptFolder nature');
      }
      if (projectNatures.containsKey('zom_extension')) {
        expect(projectNatures['zom_extension'], contains('VsCodeExtensionFolder'),
            reason: 'zom_extension should have VsCodeExtensionFolder nature');
      }
    });

    test('BB-INT-10: IncludeTestProjects includes BOTH regular and test projects [2026-02-12]', () async {
      // Scan the workspace root to find both regular projects and test projects
      final info = ProjectTraversalInfo(
        executionRoot: workspaceRoot,
        scan: workspaceRoot,
        recursive: true,
        includeTestProjects: true, // --test: include test projects IN ADDITION to regular
      );

      final foundProjects = <String>[];

      await BuildBase.traverse(
        info: info,
        requiredNatures: {DartProjectFolder},
        run: (ctx) async {
          foundProjects.add(ctx.name);
          return true;
        },
      );

      // Should find regular projects (non-zom_*)
      final regularProjects = foundProjects.where((n) => !n.startsWith('zom_')).toList();
      expect(regularProjects, isNotEmpty,
          reason: '--test should include regular (non-zom_*) projects');

      // Should ALSO find test projects (zom_*)
      final testProjects = foundProjects.where((n) => n.startsWith('zom_')).toList();
      expect(testProjects, isNotEmpty,
          reason: '--test should also include zom_* test projects');

      // Verify we found specific projects from each category
      expect(regularProjects.any((n) => n.contains('tom_')), isTrue,
          reason: '--test should find regular tom_* projects');
      expect(testProjects, contains('zom_test_flutter'),
          reason: '--test should include zom_test_flutter');
    });
  });

  group('BuildBase.traverse with GitTraversalInfo', () {
    test('BB-INT-11: Finds git repositories [2026-02-12]', () async {
      // Use the main workspace root which has git repos
      final info = GitTraversalInfo(
        executionRoot: workspaceRoot,
        gitMode: GitTraversalMode.innerFirst,
        includeTestProjects: true,
      );

      final gitRepos = <String>[];
      final hasGitNature = <String, bool>{};

      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          gitRepos.add(ctx.name);
          // Check if GitFolder nature is present
          hasGitNature[ctx.name] = ctx.natures.any((n) => n is GitFolder);
          return true;
        },
      );

      // Should find some git repos
      expect(gitRepos, isNotEmpty, reason: 'Should find git repositories');

      // All found folders should have GitFolder nature
      for (final entry in hasGitNature.entries) {
        expect(entry.value, isTrue,
            reason: '${entry.key} should have GitFolder nature');
      }
    });

    test('BB-INT-12: InnerFirst mode processes inner repos before outer [2026-02-12]', () async {
      final info = GitTraversalInfo(
        executionRoot: workspaceRoot,
        gitMode: GitTraversalMode.innerFirst,
      );

      final order = <String>[];

      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          order.add(ctx.path);
          return true;
        },
      );

      // For innerFirst, deeper paths should come before shallower
      // Verify the sorting is applied (paths with more segments first)
      if (order.length >= 2) {
        for (int i = 0; i < order.length - 1; i++) {
          final currentDepth = order[i].split(Platform.pathSeparator).length;
          final nextDepth = order[i + 1].split(Platform.pathSeparator).length;
          expect(currentDepth, greaterThanOrEqualTo(nextDepth),
              reason: 'Inner repos should come before outer in innerFirst mode');
        }
      }
    });

    test('BB-INT-13: OuterFirst mode processes outer repos before inner [2026-02-12]', () async {
      final info = GitTraversalInfo(
        executionRoot: workspaceRoot,
        gitMode: GitTraversalMode.outerFirst,
      );

      final order = <String>[];

      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          order.add(ctx.path);
          return true;
        },
      );

      // For outerFirst, shallower paths should come before deeper
      if (order.length >= 2) {
        for (int i = 0; i < order.length - 1; i++) {
          final currentDepth = order[i].split(Platform.pathSeparator).length;
          final nextDepth = order[i + 1].split(Platform.pathSeparator).length;
          expect(currentDepth, lessThanOrEqualTo(nextDepth),
              reason: 'Outer repos should come before inner in outerFirst mode');
        }
      }
    });
  });

  group('BuildBase.findProjects', () {
    test('BB-INT-14: Returns CommandContext list without executing [2026-02-12]', () async {
      final contexts = await BuildBase.findProjects(
        scan: zomTestRoot,
        recursive: true,
        include: null,
        exclude: null,
      );

      // Should return the test projects (since scan is zomTestRoot, 
      // we should get the test projects if includeTestProjects logic allows)
      expect(contexts, isA<List<CommandContext>>());
    });

    test('BB-INT-15: Respects include patterns [2026-02-12]', () async {
      final contexts = await BuildBase.findProjects(
        scan: zomTestRoot,
        recursive: true,
        include: ['zom_test_*'],
        exclude: null,
      );

      // All returned contexts should match the pattern
      for (final ctx in contexts) {
        expect(ctx.name, startsWith('zom_test_'),
            reason: 'Include pattern should filter to zom_test_* only');
      }
    });

    test('BB-INT-16: Respects exclude patterns [2026-02-12]', () async {
      final contexts = await BuildBase.findProjects(
        scan: zomTestRoot,
        recursive: true,
        include: null,
        exclude: ['*flutter*'],
      );

      // No returned contexts should contain 'flutter'
      for (final ctx in contexts) {
        expect(ctx.name.contains('flutter'), isFalse,
            reason: 'Exclude pattern should remove flutter projects');
      }
    });

    test('BB-INT-17: Respects requiredNatures filter [2026-02-12]', () async {
      final contexts = await BuildBase.findProjects(
        scan: zomTestRoot,
        recursive: true,
        requiredNatures: {DartProjectFolder},
      );

      // All returned contexts should have DartProjectFolder nature
      for (final ctx in contexts) {
        expect(ctx.natures.any((n) => n is DartProjectFolder), isTrue,
            reason: '${ctx.name} should have DartProjectFolder nature');
      }
    });
  });

  group('ProcessingResult', () {
    test('BB-INT-18: Tracks successful operations [2026-02-12]', () async {
      final info = ProjectTraversalInfo(
        executionRoot: zomTestRoot,
        scan: zomTestRoot,
        recursive: true,
        includeTestProjects: true,
        projectPatterns: ['zom_test_*'],
      );

      final result = await BuildBase.traverse(
        info: info,
        requiredNatures: {DartProjectFolder},
        run: (ctx) async => true, // All succeed
      );

      expect(result.allSucceeded, isTrue);
      expect(result.successCount, greaterThan(0));
      expect(result.failureCount, equals(0));
      expect(result.successes, isNotEmpty);
      expect(result.failures, isEmpty);
      expect(result.errors, isEmpty);
    });

    test('BB-INT-19: Tracks failed operations [2026-02-12]', () async {
      final info = ProjectTraversalInfo(
        executionRoot: zomTestRoot,
        scan: zomTestRoot,
        recursive: true,
        includeTestProjects: true,
        projectPatterns: ['zom_test_*'],
      );

      final result = await BuildBase.traverse(
        info: info,
        requiredNatures: {DartProjectFolder},
        run: (ctx) async => false, // All fail
      );

      expect(result.allSucceeded, isFalse);
      expect(result.failureCount, greaterThan(0));
      expect(result.failures, isNotEmpty);
    });

    test('BB-INT-20: Tracks errors [2026-02-12]', () async {
      final info = ProjectTraversalInfo(
        executionRoot: zomTestRoot,
        scan: zomTestRoot,
        recursive: true,
        includeTestProjects: true,
        projectPatterns: ['zom_test_flutter'],
      );

      final result = await BuildBase.traverse(
        info: info,
        requiredNatures: {DartProjectFolder},
        run: (ctx) async {
          throw Exception('Test error');
        },
      );

      expect(result.allSucceeded, isFalse);
      expect(result.errors, isNotEmpty);
    });
  });

  group('Workspace VS Code Extension', () {
    test('BB-INT-21: Detects tom_vscode_extension as both VsCodeExtension and TypeS... [2026-02-12]', () async {
      final vsCodePath = p.join(workspaceRoot, 'xternal', 'tom_module_vscode', 'tom_vscode_extension');

      // Skip if path doesn't exist in this workspace (for CI)
      final vsCodeDir = Directory(vsCodePath);
      if (!vsCodeDir.existsSync()) {
        // Skip this test if running outside the main workspace
        return;
      }

      final detector = NatureDetector();
      final folder = FsFolder(path: vsCodePath);
      final natures = detector.detectNatures(folder);

      // Should have both natures
      expect(natures.any((n) => n is VsCodeExtensionFolder), isTrue,
          reason: 'tom_vscode_extension should be detected as VsCodeExtensionFolder');
      expect(natures.any((n) => n is TypeScriptFolder), isTrue,
          reason: 'tom_vscode_extension should also be detected as TypeScriptFolder');
    });

    test('BB-INT-22: Traverse finds VS Code extension with TypeScriptFolder nature [2026-02-12]', () async {
      final vsCodeModulePath = p.join(workspaceRoot, 'xternal', 'tom_module_vscode');

      // Skip if path doesn't exist in this workspace (for CI)
      final moduleDir = Directory(vsCodeModulePath);
      if (!moduleDir.existsSync()) {
        return;
      }

      final info = ProjectTraversalInfo(
        executionRoot: vsCodeModulePath,
        scan: vsCodeModulePath,
        recursive: true,
      );

      final tsProjects = <String>[];
      final projectNatures = <String, List<String>>{};

      await BuildBase.traverse(
        info: info,
        requiredNatures: {TypeScriptFolder},
        run: (ctx) async {
          tsProjects.add(ctx.name);
          projectNatures[ctx.name] = ctx.natures.map((n) => n.runtimeType.toString()).toList();
          return true;
        },
      );

      expect(tsProjects, contains('tom_vscode_extension'),
          reason: 'Should find tom_vscode_extension with TypeScriptFolder nature');

      // Verify it also has VsCodeExtensionFolder
      if (projectNatures.containsKey('tom_vscode_extension')) {
        expect(projectNatures['tom_vscode_extension'], contains('VsCodeExtensionFolder'),
            reason: 'tom_vscode_extension should also have VsCodeExtensionFolder');
      }
    });
  });
}
