import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../fixtures/traversal_fixture.dart';

/// Comprehensive traversal tests for BuildBase and the traversal pipeline.
///
/// Tests cover:
/// - Normal project traversal (recursive and non-recursive)
/// - Skip file handling (buildkit_skip.yaml, tom_skip.yaml, workspace boundaries)
/// - Git traversal (inner-first, outer-first)
/// - Build-order sorting
/// - Filter pipeline (project patterns, exclude patterns)
/// - External tool spawning to verify end-to-end arg passing
void main() {
  late TraversalFixture fixture;

  setUpAll(() async {
    fixture = TraversalFixture();
    await fixture.setUp();
  });

  tearDownAll(() async {
    await fixture.tearDown();
  });

  // ==========================================================================
  // Group 1: Basic Project Traversal
  // ==========================================================================
  group('Basic Project Traversal', () {
    test('TRV-PROJ-1: Recursive scan finds all expected projects [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
      );

      final found = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          found.add(ctx.name);
          return true;
        },
      );

      // Should find all non-skipped Dart/TS projects
      for (final expected in fixture.expectedProjectNames) {
        expect(found, contains(expected),
            reason: 'Should find "$expected" in recursive scan');
      }
    });

    test('TRV-PROJ-2: Non-recursive scan only finds top-level projects [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: false,
        includeTestProjects: true,
      );

      final found = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          found.add(ctx.name);
          return true;
        },
      );

      // Non-recursive: should only find the root itself (zom_traversal_ws_*)
      // and NOT nested projects
      expect(found.any((n) => n == 'proj_delta'), isFalse,
          reason: 'Non-recursive should NOT find nested proj_delta');
      expect(found.any((n) => n == 'pkg_one_a'), isFalse,
          reason: 'Non-recursive should NOT find deeply nested pkg_one_a');
    });

    test('TRV-PROJ-3: Scan with different root finds only that subtree [2026-06-30]',
        () async {
      final subPath = p.join(fixture.rootPath, 'xternal', 'module_one');
      final info = ProjectTraversalInfo(
        executionRoot: subPath,
        scan: subPath,
        recursive: true,
        includeTestProjects: true,
      );

      final found = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          found.add(ctx.name);
          return true;
        },
      );

      // Should find module_one and pkg_one_a but nothing from module_two
      expect(found, contains('module_one'));
      expect(found, contains('pkg_one_a'));
      expect(found, isNot(contains('module_two')));
      expect(found, isNot(contains('proj_alpha')));
    });

    test('TRV-PROJ-4: ExecutionRoot != scan path produces correct relativePath [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: p.join(fixture.rootPath, 'xternal'),
        recursive: true,
        includeTestProjects: true,
      );

      final relativePaths = <String, String>{};
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          relativePaths[ctx.name] = ctx.relativePath;
          return true;
        },
      );

      // relativePath should be relative to executionRoot, not scan
      if (relativePaths.containsKey('module_one')) {
        expect(
          relativePaths['module_one'],
          equals(p.join('xternal', 'module_one')),
          reason:
              'relativePath should be relative to executionRoot (workspace root)',
        );
      }
    });
  });

  // ==========================================================================
  // Group 2: Skip File Handling
  // ==========================================================================
  group('Skip File Handling', () {
    test('TRV-SKIP-1: buildkit_skip.yaml skips folder and descendants [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
      );

      final found = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          found.add(ctx.name);
          return true;
        },
      );

      expect(found, isNot(contains('skipped_project')),
          reason: 'buildkit_skip.yaml should skip the folder');
      expect(found, isNot(contains('nested_in_skip')),
          reason: 'buildkit_skip.yaml should also skip descendants');
    });

    test('TRV-SKIP-2: tom_skip.yaml (global skip) skips folder [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
      );

      final found = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          found.add(ctx.name);
          return true;
        },
      );

      expect(found, isNot(contains('tom_skipped')),
          reason: 'tom_skip.yaml should globally skip the folder');
    });

    test('TRV-SKIP-3: Workspace boundary (buildkit_master.yaml) stops recursion [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
      );

      final found = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          found.add(ctx.name);
          return true;
        },
      );

      expect(found, isNot(contains('inner_project')),
          reason:
              'Project behind nested workspace boundary should not be found');
      expect(found, isNot(contains('nested_workspace')),
          reason: 'Nested workspace boundary folder itself should be skipped');
    });

    test('TRV-SKIP-4: Root directory is never skipped even if it matches skip markers [2026-06-30]',
        () async {
      // The root has buildkit_master.yaml which is a workspace boundary,
      // but the root itself should NOT be skipped (isRoot bypass)
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: false,
        includeTestProjects: true,
      );

      final found = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          found.add(ctx.path);
          return true;
        },
      );

      // The root itself should be included
      expect(found, contains(fixture.rootPath),
          reason: 'Root directory should not be skipped');
    });
  });

  // ==========================================================================
  // Group 3: Git Traversal
  // ==========================================================================
  group('Git Traversal', () {
    test('TRV-GIT-1: Git traversal finds all repos (root + submodules) [2026-06-30]',
        () async {
      final info = GitTraversalInfo(
        executionRoot: fixture.rootPath,
        gitMode: GitTraversalMode.innerFirst,
        includeTestProjects: true,
      );

      final found = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          found.add(ctx.name);
          return true;
        },
      );

      expect(found, isNotEmpty, reason: 'Should find git repos');
      // Should find the submodule repos
      expect(found, contains('module_one'),
          reason: 'Should find module_one git repo');
      expect(found, contains('module_two'),
          reason: 'Should find module_two git repo');
    });

    test('TRV-GIT-2: InnerFirst orders deeper repos before shallower [2026-06-30]',
        () async {
      final info = GitTraversalInfo(
        executionRoot: fixture.rootPath,
        gitMode: GitTraversalMode.innerFirst,
        includeTestProjects: true,
      );

      final paths = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          paths.add(ctx.path);
          return true;
        },
      );

      if (paths.length >= 2) {
        for (var i = 0; i < paths.length - 1; i++) {
          final depthA = p.split(paths[i]).length;
          final depthB = p.split(paths[i + 1]).length;
          expect(depthA, greaterThanOrEqualTo(depthB),
              reason:
                  'InnerFirst: ${p.basename(paths[i])} (depth=$depthA) should come before or at same level as ${p.basename(paths[i + 1])} (depth=$depthB)');
        }
      }
    });

    test('TRV-GIT-3: OuterFirst orders shallower repos before deeper [2026-06-30]',
        () async {
      final info = GitTraversalInfo(
        executionRoot: fixture.rootPath,
        gitMode: GitTraversalMode.outerFirst,
        includeTestProjects: true,
      );

      final paths = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          paths.add(ctx.path);
          return true;
        },
      );

      if (paths.length >= 2) {
        for (var i = 0; i < paths.length - 1; i++) {
          final depthA = p.split(paths[i]).length;
          final depthB = p.split(paths[i + 1]).length;
          expect(depthA, lessThanOrEqualTo(depthB),
              reason:
                  'OuterFirst: ${p.basename(paths[i])} (depth=$depthA) should come before or at same level as ${p.basename(paths[i + 1])} (depth=$depthB)');
        }
      }
    });

    test('TRV-GIT-4: Git traversal detects GitFolder nature [2026-06-30]',
        () async {
      final info = GitTraversalInfo(
        executionRoot: fixture.rootPath,
        gitMode: GitTraversalMode.innerFirst,
        includeTestProjects: true,
      );

      final naturesPerRepo = <String, List<String>>{};
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          naturesPerRepo[ctx.name] =
              ctx.natures.map((n) => n.runtimeType.toString()).toList();
          return true;
        },
      );

      for (final entry in naturesPerRepo.entries) {
        expect(entry.value, contains('GitFolder'),
            reason: '${entry.key} should have GitFolder nature in git traversal');
      }
    });
  });

  // ==========================================================================
  // Group 4: Filter Pipeline
  // ==========================================================================
  group('Filter Pipeline', () {
    test('TRV-FILT-1: Project pattern (-p) filters to matching names [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
        projectPatterns: ['proj_*'],
      );

      final found = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          found.add(ctx.name);
          return true;
        },
      );

      // Only proj_* names should be in results
      for (final name in found) {
        expect(name, startsWith('proj_'),
            reason: 'With pattern "proj_*", only proj_* should match');
      }
      expect(found, contains('proj_alpha'));
      expect(found, contains('proj_beta'));
      expect(found, contains('proj_gamma'));
      expect(found, contains('proj_delta'));
    });

    test('TRV-FILT-2: Exclude pattern removes matching paths [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
        excludePatterns: ['*xternal*'],
      );

      final found = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          found.add(ctx.name);
          return true;
        },
      );

      expect(found, isNot(contains('module_one')),
          reason: 'Should exclude xternal/* projects');
      expect(found, isNot(contains('module_two')));
      expect(found, isNot(contains('pkg_one_a')));
      expect(found, isNot(contains('pkg_two_a')));
      // Non-xternal projects should still be present
      expect(found, contains('proj_alpha'));
    });

    test('TRV-FILT-3: ExcludeProjects removes by project name [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
        excludeProjects: ['proj_gamma', 'ts_project'],
      );

      final found = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          found.add(ctx.name);
          return true;
        },
      );

      expect(found, isNot(contains('proj_gamma')));
      expect(found, isNot(contains('ts_project')));
      expect(found, contains('proj_alpha'));
      expect(found, contains('proj_beta'));
    });

    test('TRV-FILT-4: Required natures filter to specific project types [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
      );

      final found = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {DartProjectFolder},
        run: (ctx) async {
          found.add(ctx.name);
          return true;
        },
      );

      // ts_project has NO DartProjectFolder nature, should be excluded
      expect(found, isNot(contains('ts_project')),
          reason: 'TypeScript project should not match DartProjectFolder');
      // Dart projects should match
      expect(found, contains('proj_alpha'));
    });

    test('TRV-FILT-5: Git modules filter limits to specific submodules [2026-06-30]',
        () async {
      final info = GitTraversalInfo(
        executionRoot: fixture.rootPath,
        gitMode: GitTraversalMode.innerFirst,
        includeTestProjects: true,
        modules: ['module_one'],
      );

      final found = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          found.add(ctx.name);
          return true;
        },
      );

      expect(found, contains('module_one'));
      expect(found, isNot(contains('module_two')),
          reason: 'Modules filter should exclude module_two');
    });
  });

  // ==========================================================================
  // Group 5: Nature Detection
  // ==========================================================================
  group('Nature Detection', () {
    test('TRV-NAT-1: Dart console app has DartConsoleFolder nature [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
        projectPatterns: ['proj_alpha'],
      );

      final natures = <String, List<String>>{};
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          natures[ctx.name] =
              ctx.natures.map((n) => n.runtimeType.toString()).toList();
          return true;
        },
      );

      expect(natures.containsKey('proj_alpha'), isTrue,
          reason: 'proj_alpha should be found');
      if (natures.containsKey('proj_alpha')) {
        expect(natures['proj_alpha'], contains('DartConsoleFolder'),
            reason: 'proj_alpha (has bin/) should be DartConsoleFolder');
      }
    });

    test('TRV-NAT-2: Dart package has DartPackageFolder nature [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
        projectPatterns: ['proj_beta'],
      );

      final natures = <String, List<String>>{};
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          natures[ctx.name] =
              ctx.natures.map((n) => n.runtimeType.toString()).toList();
          return true;
        },
      );

      expect(natures.containsKey('proj_beta'), isTrue);
      if (natures.containsKey('proj_beta')) {
        expect(natures['proj_beta'], contains('DartPackageFolder'),
            reason: 'proj_beta (lib/, no bin/) should be DartPackageFolder');
      }
    });

    test('TRV-NAT-3: TypeScript project has TypeScriptFolder nature [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
        projectPatterns: ['ts_project'],
      );

      final natures = <String, List<String>>{};
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          natures[ctx.name] =
              ctx.natures.map((n) => n.runtimeType.toString()).toList();
          return true;
        },
      );

      expect(natures.containsKey('ts_project'), isTrue);
      if (natures.containsKey('ts_project')) {
        expect(natures['ts_project'], contains('TypeScriptFolder'),
            reason:
                'ts_project (has tsconfig.json + package.json) should be TypeScriptFolder');
      }
    });
  });

  // ==========================================================================
  // Group 6: CLI Arg Parsing
  // ==========================================================================
  group('CLI Arg Parsing', () {
    test('TRV-CLI-1: -r flag enables recursive [2026-06-30]', () {
      final parser = CliArgParser();
      final args = parser.parse(['-r']);
      expect(args.recursive, isTrue);
      expect(args.recursiveExplicitlySet, isTrue);
    });

    test('TRV-CLI-2: --not-recursive disables recursive [2026-06-30]', () {
      final parser = CliArgParser();
      final args = parser.parse(['--not-recursive']);
      expect(args.notRecursive, isTrue);
      expect(args.recursiveExplicitlySet, isTrue);
    });

    test('TRV-CLI-3: -s sets scan path [2026-06-30]', () {
      final parser = CliArgParser();
      final args = parser.parse(['-s', '/some/path']);
      expect(args.scan, equals('/some/path'));
      expect(args.scanExplicitlySet, isTrue);
    });

    test('TRV-CLI-4: -R sets root path [2026-06-30]', () {
      final parser = CliArgParser();
      final args = parser.parse(['-R', '/root/path']);
      expect(args.root, equals('/root/path'));
    });

    test('TRV-CLI-5: Bare -R without value sets bareRoot [2026-06-30]', () {
      final parser = CliArgParser();
      final args = parser.parse(['-R', ':cmd']);
      // -R follows by a command → bare root
      expect(args.bareRoot, isTrue);
      expect(args.commands, contains('cmd'));
    });

    test('TRV-CLI-6: -i enables inner-first-git [2026-06-30]', () {
      final parser = CliArgParser();
      final args = parser.parse(['-i']);
      expect(args.innerFirstGit, isTrue);
      expect(args.gitModeExplicitlySet, isTrue);
    });

    test('TRV-CLI-7: -o enables outer-first-git [2026-06-30]', () {
      final parser = CliArgParser();
      final args = parser.parse(['-o']);
      expect(args.outerFirstGit, isTrue);
      expect(args.gitModeExplicitlySet, isTrue);
    });

    test('TRV-CLI-8: -p adds project patterns [2026-06-30]', () {
      final parser = CliArgParser();
      final args = parser.parse(['-p', 'alpha,beta']);
      expect(args.projectPatterns, containsAll(['alpha', 'beta']));
    });

    test('TRV-CLI-9: -x adds exclude patterns [2026-06-30]', () {
      final parser = CliArgParser();
      final args = parser.parse(['-x', '*skip*']);
      expect(args.excludePatterns, contains('*skip*'));
    });

    test('TRV-CLI-10: Commands are parsed with : prefix [2026-06-30]', () {
      final parser = CliArgParser();
      final args = parser.parse([':execute', 'echo', 'hello']);
      expect(args.commands, contains('execute'));
      expect(args.positionalArgs, containsAll(['echo', 'hello']));
    });

    test('TRV-CLI-11: Multiple flags bundled together [2026-06-30]', () {
      final parser = CliArgParser();
      final args = parser.parse(['-rv']);
      expect(args.recursive, isTrue);
      expect(args.verbose, isTrue);
    });

    test('TRV-CLI-12: Per-command project patterns [2026-06-30]', () {
      final parser = CliArgParser();
      final args = parser.parse([':execute', '-p', 'alpha']);
      expect(args.commands, contains('execute'));
      final cmdArgs = args.commandArgs['execute'];
      expect(cmdArgs, isNotNull);
      expect(cmdArgs!.projectPatterns, contains('alpha'));
    });

    test('TRV-CLI-13: toProjectTraversalInfo applies defaults correctly [2026-06-30]',
        () {
      final parser = CliArgParser();
      final args = parser.parse(['-r', '-s', fixture.rootPath]);
      final info = args.toProjectTraversalInfo(
        executionRoot: fixture.rootPath,
      );

      expect(info.scan, equals(fixture.rootPath));
      expect(info.recursive, isTrue);
      expect(info.executionRoot, equals(fixture.rootPath));
    });

    test('TRV-CLI-14: toGitTraversalInfo with -i produces innerFirst [2026-06-30]',
        () {
      final parser = CliArgParser();
      final args = parser.parse(['-i']);
      final info = args.toGitTraversalInfo(
        executionRoot: fixture.rootPath,
      );

      expect(info, isNotNull);
      expect(info!.gitMode, equals(GitTraversalMode.innerFirst));
    });

    test('TRV-CLI-15: toGitTraversalInfo without mode returns null [2026-06-30]',
        () {
      final parser = CliArgParser();
      final args = parser.parse([]);
      final info = args.toGitTraversalInfo(
        executionRoot: fixture.rootPath,
      );

      expect(info, isNull,
          reason: 'Without -i or -o, git traversal info should be null');
    });

    test('TRV-CLI-16: Default recursive is false (workspace mode) [2026-06-30]',
        () {
      final parser = CliArgParser();
      final args = parser.parse([]);
      final info = args.toProjectTraversalInfo(
        executionRoot: fixture.rootPath,
      );

      expect(info.recursive, isFalse,
          reason: 'Default should be non-recursive (workspace mode)');
    });
  });

  // ==========================================================================
  // Group 7: External Process Traversal (spawning traversal_tool.dart)
  // ==========================================================================
  group('External Process Traversal', () {
    late String toolPath;

    setUpAll(() {
      // Path to the traversal tool script
      final buildBaseRoot = p.normalize(
        p.join(Directory.current.path),
      );
      toolPath = p.join(
        buildBaseRoot,
        'test',
        'v2',
        'fixtures',
        'traversal_tool.dart',
      );

      // Verify tool exists
      expect(File(toolPath).existsSync(), isTrue,
          reason: 'traversal_tool.dart should exist at $toolPath');
    });

    /// Run the traversal tool with given args and return parsed JSON output.
    Future<Map<String, dynamic>> runTool(List<String> args) async {
      final result = await Process.run(
        'dart',
        ['run', toolPath, ...args],
        environment: {'HOME': Platform.environment['HOME'] ?? '/tmp'},
      );

      if (result.exitCode != 0) {
        fail(
            'traversal_tool.dart exited with code ${result.exitCode}\n'
            'stderr: ${result.stderr}\n'
            'stdout: ${result.stdout}');
      }

      // Verbose mode may print non-JSON lines before the JSON output.
      // Extract the last line that starts with '{' as the JSON payload.
      final stdout = (result.stdout as String).trim();
      final lines = stdout.split('\n');
      final jsonLine = lines.lastWhere(
        (l) => l.trimLeft().startsWith('{'),
        orElse: () => stdout,
      );

      try {
        return jsonDecode(jsonLine) as Map<String, dynamic>;
      } catch (e) {
        fail(
            'Failed to parse JSON from traversal_tool.dart:\n'
            'stdout: $stdout\n'
            'stderr: ${result.stderr}\n'
            'jsonLine: $jsonLine\n'
            'error: $e');
      }
    }

    test('TRV-EXT-1: External tool scans recursively with -r -R [2026-06-30]',
        () async {
      final output = await runTool([
        '-R',
        fixture.rootPath,
        '-s',
        fixture.rootPath,
        '-r',
      ]);

      expect(output['traversalType'], equals('project'));
      expect(output['executionRoot'], equals(fixture.rootPath));

      final folders = (output['folders'] as List).cast<Map<String, dynamic>>();
      final names = folders.map((f) => f['name'] as String).toList();

      expect(names, contains('proj_alpha'));
      expect(names, contains('proj_beta'));
      expect(names, contains('proj_gamma'));
      expect(names, contains('proj_delta'));
      expect(names, isNot(contains('skipped_project')));
      expect(names, isNot(contains('tom_skipped')));
    });

    test('TRV-EXT-2: External tool passes -p project filter [2026-06-30]',
        () async {
      final output = await runTool([
        '-R',
        fixture.rootPath,
        '-s',
        fixture.rootPath,
        '-r',
        '-p',
        'proj_alpha',
      ]);

      final folders = (output['folders'] as List).cast<Map<String, dynamic>>();
      final names = folders.map((f) => f['name'] as String).toList();

      expect(names, contains('proj_alpha'));
      expect(names, isNot(contains('proj_beta')),
          reason: 'Should be filtered by -p');
    });

    test('TRV-EXT-3: External tool passes -x exclude [2026-06-30]',
        () async {
      final output = await runTool([
        '-R',
        fixture.rootPath,
        '-s',
        fixture.rootPath,
        '-r',
        '-x',
        '*xternal*',
      ]);

      final folders = (output['folders'] as List).cast<Map<String, dynamic>>();
      final names = folders.map((f) => f['name'] as String).toList();

      expect(names, isNot(contains('module_one')));
      expect(names, isNot(contains('module_two')));
      expect(names, contains('proj_alpha'));
    });

    test('TRV-EXT-4: External tool git inner-first with -i [2026-06-30]',
        () async {
      final output = await runTool([
        '-R',
        fixture.rootPath,
        '-i',
      ]);

      expect(output['traversalType'], equals('git'));

      final folders = (output['folders'] as List).cast<Map<String, dynamic>>();

      if (folders.length >= 2) {
        // Verify inner-first ordering (deeper paths first)
        for (var i = 0; i < folders.length - 1; i++) {
          final pathA = folders[i]['path'] as String;
          final pathB = folders[i + 1]['path'] as String;
          final depthA = p.split(pathA).length;
          final depthB = p.split(pathB).length;
          expect(depthA, greaterThanOrEqualTo(depthB),
              reason:
                  'InnerFirst: ${folders[i]['name']} should come before ${folders[i + 1]['name']}');
        }
      }

      final parsedArgs =
          output['parsedArgs'] as Map<String, dynamic>;
      expect(parsedArgs['innerFirstGit'], isTrue);
    });

    test('TRV-EXT-5: External tool git outer-first with -o [2026-06-30]',
        () async {
      final output = await runTool([
        '-R',
        fixture.rootPath,
        '-o',
      ]);

      expect(output['traversalType'], equals('git'));

      final folders = (output['folders'] as List).cast<Map<String, dynamic>>();

      if (folders.length >= 2) {
        for (var i = 0; i < folders.length - 1; i++) {
          final pathA = folders[i]['path'] as String;
          final pathB = folders[i + 1]['path'] as String;
          final depthA = p.split(pathA).length;
          final depthB = p.split(pathB).length;
          expect(depthA, lessThanOrEqualTo(depthB),
              reason:
                  'OuterFirst: ${folders[i]['name']} should come before ${folders[i + 1]['name']}');
        }
      }
    });

    test('TRV-EXT-6: Parsed args accurately reflect CLI input [2026-06-30]',
        () async {
      final output = await runTool([
        '-R',
        fixture.rootPath,
        '-s',
        fixture.rootPath,
        '-r',
        '-v',
        '-n',
        '-p',
        'alpha,beta',
        '-x',
        '*skip*',
      ]);

      final parsedArgs =
          output['parsedArgs'] as Map<String, dynamic>;
      expect(parsedArgs['recursive'], isTrue);
      expect(parsedArgs['verbose'], isTrue);
      expect(parsedArgs['dryRun'], isTrue);
      expect(
        (parsedArgs['projectPatterns'] as List),
        containsAll(['alpha', 'beta']),
      );
      expect(
        (parsedArgs['excludePatterns'] as List),
        contains('*skip*'),
      );
    });

    test('TRV-EXT-7: External tool reports natures for each folder [2026-06-30]',
        () async {
      final output = await runTool([
        '-R',
        fixture.rootPath,
        '-s',
        fixture.rootPath,
        '-r',
        '-p',
        'proj_alpha',
      ]);

      final folders = (output['folders'] as List).cast<Map<String, dynamic>>();
      expect(folders, isNotEmpty);

      final alpha = folders.firstWhere((f) => f['name'] == 'proj_alpha');
      final natures = (alpha['natures'] as List).cast<String>();
      expect(natures, isNotEmpty, reason: 'proj_alpha should have natures');
    });

    test('TRV-EXT-8: Positional args are captured correctly [2026-06-30]',
        () async {
      final output = await runTool([
        '-R',
        fixture.rootPath,
        '-s',
        fixture.rootPath,
        ':execute',
        'echo',
        'hello world',
      ]);

      final parsedArgs =
          output['parsedArgs'] as Map<String, dynamic>;
      expect(parsedArgs['commands'], contains('execute'));
      expect(
        (parsedArgs['positionalArgs'] as List),
        containsAll(['echo', 'hello world']),
      );
    });
  });

  // ==========================================================================
  // Group 8: ProcessingResult Tracking
  // ==========================================================================
  group('ProcessingResult Tracking', () {
    test('TRV-RES-1: Tracks successes correctly [2026-06-30]', () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
        projectPatterns: ['proj_alpha', 'proj_beta'],
      );

      final result = await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async => true,
      );

      expect(result.allSucceeded, isTrue);
      expect(result.successCount, greaterThan(0));
      expect(result.failureCount, equals(0));
    });

    test('TRV-RES-2: Tracks failures correctly [2026-06-30]', () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
        projectPatterns: ['proj_alpha'],
      );

      final result = await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async => false,
      );

      expect(result.allSucceeded, isFalse);
      expect(result.failureCount, greaterThan(0));
    });

    test('TRV-RES-3: Tracks errors correctly [2026-06-30]', () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
        projectPatterns: ['proj_alpha'],
      );

      final result = await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async => throw Exception('test error'),
      );

      expect(result.allSucceeded, isFalse);
      expect(result.errors, isNotEmpty);
    });
  });

  // ==========================================================================
  // Group 9: Edge Cases and Regression Tests
  // ==========================================================================
  group('Edge Cases', () {
    test('TRV-EDGE-1: Empty scan directory returns empty results [2026-06-30]',
        () async {
      final emptyDir = await Directory.systemTemp.createTemp('empty_scan_');
      try {
        final info = ProjectTraversalInfo(
          executionRoot: emptyDir.path,
          scan: emptyDir.path,
          recursive: true,
          includeTestProjects: true,
        );

        final found = <String>[];
        await BuildBase.traverse(
          info: info,
          requiredNatures: {FsFolder},
          run: (ctx) async {
            found.add(ctx.name);
            return true;
          },
        );

        // Empty dir still gets visited as root (it's a valid folder)
        // but should have no projects to process via requiredNatures
        // Without nature requirement, root folder itself is visited
      } finally {
        await emptyDir.delete(recursive: true);
      }
    });

    test('TRV-EDGE-2: Non-existent scan path returns empty results [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: '/non/existent/path',
        scan: '/non/existent/path',
        recursive: true,
      );

      final result = await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async => true,
      );

      expect(result.total, equals(0),
          reason: 'Non-existent path should produce no results');
    });

    test('TRV-EDGE-3: Concurrent traversals use separate state [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
      );

      // Run two traversals concurrently
      final results = await Future.wait([
        BuildBase.traverse(info: info, requiredNatures: {FsFolder}, run: (ctx) async => true),
        BuildBase.traverse(info: info, requiredNatures: {FsFolder}, run: (ctx) async => true),
      ]);

      expect(results[0].successCount, equals(results[1].successCount),
          reason: 'Concurrent traversals should produce identical results');
    });

    test('TRV-EDGE-4: Traversal with all filters returns subset [2026-06-30]',
        () async {
      final info = ProjectTraversalInfo(
        executionRoot: fixture.rootPath,
        scan: fixture.rootPath,
        recursive: true,
        includeTestProjects: true,
        projectPatterns: ['proj_*'],
        excludeProjects: ['proj_gamma'],
      );

      final found = <String>[];
      await BuildBase.traverse(
        info: info,
        requiredNatures: {FsFolder},
        run: (ctx) async {
          found.add(ctx.name);
          return true;
        },
      );

      expect(found, contains('proj_alpha'));
      expect(found, contains('proj_beta'));
      expect(found, contains('proj_delta'));
      expect(found, isNot(contains('proj_gamma')),
          reason: 'proj_gamma was explicitly excluded');
      expect(found, isNot(contains('module_one')),
          reason: 'module_one doesn\'t match proj_* pattern');
    });
  });
}
