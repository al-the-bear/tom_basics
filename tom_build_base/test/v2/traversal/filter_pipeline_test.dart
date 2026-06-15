import 'dart:io';

import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../../fixtures/zom_fixture.dart';

/// Tests for FilterPipeline using the zom_analyzer_test fixture projects.
void main() {
  // A real git working tree enclosing this package (for git-filter tests,
  // whose module assertions match the enclosing repo's folder structure).
  late String workspaceRoot;
  late String zomTestRoot;
  late FilterPipeline filter;
  late List<FsFolder> allFolders;

  setUpAll(() async {
    // Resolve the package root (cwd-independent) before any path helper reads
    // it; the process cwd is shared across concurrently running suites.
    await resolvePackageRoot();
    workspaceRoot = workspaceRootDir();
    // Copy the checked-in zom fixture into a throwaway temp dir for this run.
    zomTestRoot = installZomFixture();

    // Scan all folders to use in filter tests
    final scanner = FolderScanner();
    allFolders = await scanner.scan(zomTestRoot, recursive: true);

    // Detect natures for each folder
    final detector = NatureDetector();
    for (final folder in allFolders) {
      final natures = detector.detectNatures(folder);
      folder.natures.addAll(natures);
    }
  });

  tearDownAll(() {
    removeZomFixture(zomTestRoot);
  });

  setUp(() {
    filter = FilterPipeline();
  });

  group('FilterPipeline.applyProjectFilters', () {
    group('Project include filter (--project, -p)', () {
      test('BB-FLT-1: Filters to matching project names [2026-02-12]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          projectPatterns: ['zom_test_*'],
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        // Should only include zom_test_* folders
        for (final folder in filtered) {
          expect(folder.name, startsWith('zom_test'),
              reason: 'Only zom_test_* should match');
        }
        expect(filtered.length, greaterThan(0));
      });

      test('BB-FLT-2: Filters with exact name match [2026-02-12]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          projectPatterns: ['zom_test_flutter'],
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        expect(filtered.length, equals(1));
        expect(filtered.first.name, equals('zom_test_flutter'));
      });

      test('BB-FLT-3: Filters with multiple patterns [2026-02-12]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          projectPatterns: ['zom_test_flutter', 'zom_test_package'],
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        final names = filtered.map((f) => f.name).toSet();
        expect(names, contains('zom_test_flutter'));
        expect(names, contains('zom_test_package'));
        expect(filtered.length, equals(2));
      });

      test('BB-FLT-4: Empty patterns returns all folders [2026-02-12]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          projectPatterns: [],
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        // Should return same count (test filter will still apply)
        expect(filtered.length, equals(allFolders.length));
      });
    });

    group('Project ID and Name filtering (--project, -p)', () {
      test('BB-FLT-30: Filters by project short-id from tom_project.yaml [2026-02-14]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          projectPatterns: ['ZTF'], // short-id for zom_test_flutter
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        expect(filtered.length, equals(1));
        expect(filtered.first.name, equals('zom_test_flutter'));
      });

      test('BB-FLT-31: Filters by project short-id case-insensitive [2026-02-14]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          projectPatterns: ['ztf'], // lowercase
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        expect(filtered.length, equals(1));
        expect(filtered.first.name, equals('zom_test_flutter'));
      });

      test('BB-FLT-32: Filters by project name from tom_project.yaml [2026-02-14]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          projectPatterns: ['test-flutter'], // name field
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        expect(filtered.length, equals(1));
        expect(filtered.first.name, equals('zom_test_flutter'));
      });

      test('BB-FLT-33: Filters by multiple project IDs [2026-02-14]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          projectPatterns: ['ZTF', 'ZTP'], // flutter and package
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        final names = filtered.map((f) => f.name).toSet();
        expect(names, contains('zom_test_flutter'));
        expect(names, contains('zom_test_package'));
        expect(filtered.length, equals(2));
      });

      test('BB-FLT-34: Mixed ID, name, and folder pattern [2026-02-14]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          projectPatterns: ['ZTF', 'test-cli', 'zom_test_*'], // ID, name, glob
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        // Should find all three test projects
        final names = filtered.map((f) => f.name).toSet();
        expect(names, contains('zom_test_flutter'));
        expect(names, contains('zom_test_standalone'));
        expect(names, contains('zom_test_package'));
      });
    });

    group('Absolute path patterns (--project <abs path>)', () {
      // Regression: tools such as `versioner --project <abs>` pass an absolute
      // filesystem path. It must match the project folder on every platform,
      // regardless of whether the path uses `/` or `\` separators. The Windows
      // failure mode was that a backslash absolute path was not recognised as a
      // path pattern at all (`pattern.contains('/')` is false), so it matched
      // zero projects.
      late FsFolder flutterFolder;

      setUp(() {
        flutterFolder =
            allFolders.firstWhere((f) => f.name == 'zom_test_flutter');
      });

      test('BB-FLT-41: native absolute path matches the project [2026-06-14]',
          () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          projectPatterns: [flutterFolder.path], // native separators
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        expect(filtered.map((f) => f.name), contains('zom_test_flutter'));
        expect(filtered.length, equals(1),
            reason: 'An absolute path should select exactly that project');
      });

      test(
          'BB-FLT-42: forward-slash absolute path matches the project '
          '[2026-06-14]', () {
        final forwardSlash = flutterFolder.path.replaceAll(r'\', '/');
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          projectPatterns: [forwardSlash],
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        expect(filtered.map((f) => f.name), contains('zom_test_flutter'));
      });

      test(
          'BB-FLT-43: backslash absolute path matches the project '
          '[2026-06-14]', () {
        final backslash = flutterFolder.path.replaceAll('/', r'\');
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          projectPatterns: [backslash],
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        expect(filtered.map((f) => f.name), contains('zom_test_flutter'),
            reason: 'A backslash absolute path must still match the folder');
      });

      test('BB-FLT-44: matchesProjectPattern accepts an absolute path '
          '[2026-06-14]', () {
        expect(
          filter.matchesProjectPattern(
            flutterFolder,
            [flutterFolder.path],
            executionRoot: zomTestRoot,
          ),
          isTrue,
        );
        // Separator-flipped variant must also match.
        final flipped = flutterFolder.path.contains(r'\')
            ? flutterFolder.path.replaceAll(r'\', '/')
            : flutterFolder.path.replaceAll('/', r'\');
        expect(
          filter.matchesProjectPattern(
            flutterFolder,
            [flipped],
            executionRoot: zomTestRoot,
          ),
          isTrue,
        );
      });
    });

    group('Project exclude with ID and Name (--exclude-projects)', () {
      test('BB-FLT-35: Excludes by project short-id [2026-02-14]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          excludeProjects: ['ZTF'], // exclude flutter by ID
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        expect(filtered.any((f) => f.name == 'zom_test_flutter'), isFalse);
        expect(filtered.any((f) => f.name == 'zom_test_package'), isTrue);
      });

      test('BB-FLT-36: Excludes by project name [2026-02-14]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          excludeProjects: ['test-pkg'], // exclude package by name
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        expect(filtered.any((f) => f.name == 'zom_test_package'), isFalse);
        expect(filtered.any((f) => f.name == 'zom_test_flutter'), isTrue);
      });
    });

    group('Path exclude filter (--exclude, -x)', () {
      test('BB-FLT-5: Excludes paths matching pattern [2026-02-12]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          excludePatterns: ['*flutter*'],
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        // No flutter folders should remain
        for (final folder in filtered) {
          expect(folder.path.contains('flutter'), isFalse,
              reason: 'Flutter paths should be excluded');
        }
      });

      test('BB-FLT-6: Excludes multiple patterns [2026-02-12]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          excludePatterns: ['*flutter*', '*typescript*'],
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        for (final folder in filtered) {
          expect(folder.path.contains('flutter'), isFalse);
          expect(folder.path.contains('typescript'), isFalse);
        }
      });
    });

    group('Project name exclude filter (--exclude-projects)', () {
      test('BB-FLT-7: Excludes specific project names [2026-02-12]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          excludeProjects: ['zom_test_flutter'],
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        expect(filtered.any((f) => f.name == 'zom_test_flutter'), isFalse,
            reason: 'zom_test_flutter should be excluded');
      });

      test('BB-FLT-8: Excludes with glob pattern [2026-02-12]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          excludeProjects: ['zom_test_*'],
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        for (final folder in filtered) {
          expect(folder.name.startsWith('zom_test_'), isFalse,
              reason: 'All zom_test_* should be excluded');
        }
      });
    });

    group('Test project filter (--test, --test-only)', () {
      test('BB-FLT-9: Excludes zom_* by default [2026-02-12]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          includeTestProjects: false, // Default
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        for (final folder in filtered) {
          expect(folder.name.startsWith('zom_'), isFalse,
              reason: 'zom_* should be excluded by default');
        }
      });

      test('BB-FLT-10: Includes zom_* with includeTestProjects (--test) [2026-02-12]', () {
        // Design spec: "--test: include them" (zom_* projects IN ADDITION to regular)
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        expect(filtered.any((f) => f.name.startsWith('zom_')), isTrue,
            reason: '--test should include zom_* projects');
      });

      test('BB-FLT-11: IncludeTestProjects keeps both regular AND test projects [2026-02-12]', () {
        // Design spec: "--test: include them" means BOTH regular and test
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);
        final regularProjects = filtered.where((f) => !f.name.startsWith('zom_'));
        final testProjects = filtered.where((f) => f.name.startsWith('zom_'));

        expect(regularProjects, isNotEmpty,
            reason: '--test should ALSO keep regular (non-zom_*) projects');
        expect(testProjects, isNotEmpty,
            reason: '--test should include zom_* projects');
      });

      test('BB-FLT-12: TestProjectsOnly returns only zom_* folders (--test-only) [2026-02-12]', () {
        // Design spec: "--test-only: only them" (ONLY zom_* projects, exclude regular)
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          testProjectsOnly: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);
        final regularProjects = filtered.where((f) => !f.name.startsWith('zom_'));

        for (final folder in filtered) {
          expect(folder.name, startsWith('zom_'),
              reason: '--test-only: only zom_* should be included');
        }
        expect(regularProjects, isEmpty,
            reason: '--test-only should EXCLUDE regular projects');
        expect(filtered.length, greaterThan(0),
            reason: '--test-only should find at least some test projects');
      });
    });

    group('Combined filters', () {
      test('BB-FLT-13: Include + exclude works together [2026-02-12]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          projectPatterns: ['zom_test_*'],
          excludeProjects: ['zom_test_flutter'],
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        // Should have zom_test_* but NOT zom_test_flutter
        for (final folder in filtered) {
          expect(folder.name, startsWith('zom_test_'));
          expect(folder.name, isNot(equals('zom_test_flutter')));
        }
      });

      test('BB-FLT-14: Path exclude + name include works together [2026-02-12]', () {
        final info = ProjectTraversalInfo(
          executionRoot: zomTestRoot,
          projectPatterns: ['zom_*'],
          excludePatterns: ['*flutter*'],
          includeTestProjects: true,
        );

        final filtered = filter.applyProjectFilters(allFolders, info);

        for (final folder in filtered) {
          expect(folder.name, startsWith('zom_'));
          expect(folder.path.contains('flutter'), isFalse);
        }
      });
    });
  });

  group('FilterPipeline.applyGitFilters', () {
    late List<FsFolder> gitFolders;

    setUpAll(() async {
      // Find git repos for git filter tests
      final finder = GitRepoFinder();
      gitFolders = await finder.findAll(workspaceRoot);
    });

    group('Module filter (--modules, -m)', () {
      test('BB-FLT-15: Filters to specified modules [2026-02-12]', () {
        final info = GitTraversalInfo(
          executionRoot: workspaceRoot,
          gitMode: GitTraversalMode.innerFirst,
          modules: ['basics'],
        );

        final filtered = filter.applyGitFilters(gitFolders, info);

        // All filtered folders should contain 'basics' in path
        for (final folder in filtered) {
          expect(folder.path.contains('basics'), isTrue,
              reason: 'Should only include basics module');
        }
      });

      test('BB-FLT-16: Filters with multiple modules [2026-02-12]', () {
        final info = GitTraversalInfo(
          executionRoot: workspaceRoot,
          gitMode: GitTraversalMode.innerFirst,
          modules: ['basics', 'd4rt'],
        );

        final filtered = filter.applyGitFilters(gitFolders, info);

        // All filtered folders should contain basics OR d4rt
        for (final folder in filtered) {
          expect(
              folder.path.contains('basics') || folder.path.contains('d4rt'),
              isTrue,
              reason: 'Should include basics or d4rt modules');
        }
      });

      test('BB-FLT-17: Empty modules returns all [2026-02-12]', () {
        final info = GitTraversalInfo(
          executionRoot: workspaceRoot,
          gitMode: GitTraversalMode.innerFirst,
          modules: [],
        );

        final filtered = filter.applyGitFilters(gitFolders, info);

        // Should return all git folders
        expect(filtered.length, equals(gitFolders.length));
      });
    });

    group('Skip modules filter (--skip-modules)', () {
      test('BB-FLT-18: Excludes specified modules [2026-02-12]', () {
        final info = GitTraversalInfo(
          executionRoot: workspaceRoot,
          gitMode: GitTraversalMode.innerFirst,
          skipModules: ['crypto'],
        );

        final filtered = filter.applyGitFilters(gitFolders, info);

        // No filtered folders should contain 'crypto' in path
        for (final folder in filtered) {
          expect(folder.path.contains('crypto'), isFalse,
              reason: 'Should exclude crypto module');
        }
      });
    });

    group('Path exclude filter', () {
      test('BB-FLT-19: Excludes paths matching pattern [2026-02-12]', () {
        final info = GitTraversalInfo(
          executionRoot: workspaceRoot,
          gitMode: GitTraversalMode.innerFirst,
          excludePatterns: ['*xternal*'],
        );

        final filtered = filter.applyGitFilters(gitFolders, info);

        for (final folder in filtered) {
          expect(folder.path.contains('xternal'), isFalse,
              reason: 'xternal should be excluded');
        }
      });
    });

    group('Test project filter', () {
      test('BB-FLT-20: Excludes zom_* by default in git mode [2026-02-12]', () {
        final info = GitTraversalInfo(
          executionRoot: workspaceRoot,
          gitMode: GitTraversalMode.innerFirst,
          includeTestProjects: false,
        );

        final filtered = filter.applyGitFilters(gitFolders, info);

        for (final folder in filtered) {
          expect(folder.name.startsWith('zom_'), isFalse);
        }
      });
    });
  });

  group('FolderScanner', () {
    test('BB-FLT-21: Scans recursively when recursive is true [2026-02-12]', () async {
      final scanner = FolderScanner();
      final folders = await scanner.scan(zomTestRoot, recursive: true);

      // Should find subfolders
      expect(folders.length, greaterThan(1),
          reason: 'Should find multiple folders recursively');
    });

    test('BB-FLT-22: Scans only root when recursive is false [2026-02-12]', () async {
      // The scanner enters container directories but stops at project
      // directories, so a project root with a nested project yields just the
      // root when recursive is false. (The zom fixture root is a *container*,
      // which the scanner always descends into, so it is unsuitable here.)
      final nestedRoot = installNestedProjectFixture();
      try {
        final scanner = FolderScanner();
        final folders = await scanner.scan(nestedRoot, recursive: false);

        // Should only find the root folder
        expect(folders.length, equals(1));
        expect(folders.first.path, equals(nestedRoot));
      } finally {
        removeWorkspace(nestedRoot);
      }
    });

    test('BB-FLT-23: Respects recursionExclude patterns [2026-02-12]', () async {
      final scanner = FolderScanner();
      final folders = await scanner.scan(
        zomTestRoot,
        recursive: true,
        recursionExclude: ['*flutter*'],
      );

      // Should not descend into folders whose NAME matches *flutter*
      for (final folder in folders) {
        final folderName = p.basename(folder.path);
        // Check that no folder NAME matches the exclusion pattern
        expect(folderName.contains('flutter'), isFalse,
            reason: 'Should not include folders matching *flutter* pattern: $folderName');
      }

      // Explicitly verify zom_test_flutter is excluded
      final flutterFolder = folders.where(
        (f) => p.basename(f.path) == 'zom_test_flutter',
      );
      expect(flutterFolder, isEmpty,
          reason: 'zom_test_flutter should be excluded');
    });

    test('BB-FLT-24: Skips hidden directories [2026-02-12]', () async {
      final scanner = FolderScanner();
      final folders = await scanner.scan(zomTestRoot, recursive: true);

      for (final folder in folders) {
        final parts = p.split(folder.path);
        for (final part in parts) {
          if (part != '.') {
            expect(part.startsWith('.'), isFalse,
                reason: 'Should not include hidden directories');
          }
        }
      }
    });
  });

  group('GitRepoFinder', () {
    test('BB-FLT-25: Finds git repositories [2026-02-12]', () async {
      final finder = GitRepoFinder();
      final repos = await finder.findAll(workspaceRoot);

      expect(repos, isNotEmpty, reason: 'Should find git repos');

      // Verify all found folders are git repos
      for (final folder in repos) {
        final gitDir = Directory(p.join(folder.path, '.git'));
        final gitFile = File(p.join(folder.path, '.git'));
        expect(gitDir.existsSync() || gitFile.existsSync(), isTrue,
            reason: '${folder.path} should have .git');
      }
    });

    test('BB-FLT-26: Finds submodules [2026-02-12]', () async {
      final finder = GitRepoFinder();
      final repos = await finder.findAll(workspaceRoot);

      // Should find repos in xternal/ (which are submodules)
      final xternalRepos = repos.where((r) => r.path.contains('xternal'));
      expect(xternalRepos, isNotEmpty,
          reason: 'Should find repos in xternal/ (submodules)');
    });

    test('BB-FLT-27: Returns empty list for non-git folder [2026-02-12]', () async {
      final tempDir = Directory.systemTemp.createTempSync('git_test_');
      try {
        final finder = GitRepoFinder();
        final repos = await finder.findAll(tempDir.path);

        expect(repos, isEmpty);
      } finally {
        tempDir.deleteSync();
      }
    });
  });

  group('FolderSorter', () {
    test('BB-FLT-28: SortByInnerFirst orders deeper paths first [2026-02-12]', () {
      final sorter = FolderSorter();
      final items = [
        '/a',
        '/a/b',
        '/a/b/c',
        '/x',
        '/x/y',
      ];

      final sorted = sorter.sortByInnerFirst(items, (s) => s);

      // Deeper paths should come first
      expect(sorted.indexOf('/a/b/c'), lessThan(sorted.indexOf('/a/b')));
      expect(sorted.indexOf('/a/b'), lessThan(sorted.indexOf('/a')));
      expect(sorted.indexOf('/x/y'), lessThan(sorted.indexOf('/x')));
    });

    test('BB-FLT-29: SortByOuterFirst orders shallower paths first [2026-02-12]', () {
      final sorter = FolderSorter();
      final items = [
        '/a/b/c',
        '/a/b',
        '/a',
        '/x/y',
        '/x',
      ];

      final sorted = sorter.sortByOuterFirst(items, (s) => s);

      // Shallower paths should come first
      expect(sorted.indexOf('/a'), lessThan(sorted.indexOf('/a/b')));
      expect(sorted.indexOf('/a/b'), lessThan(sorted.indexOf('/a/b/c')));
      expect(sorted.indexOf('/x'), lessThan(sorted.indexOf('/x/y')));
    });
  });

  group('RepositoryIdLookup', () {
    // Controlled workspace with tom_repository.yaml markers (BSC/D4/CRPT), so
    // resolution does not depend on whatever metadata exists at the current
    // working directory.
    late String repoIdRoot;

    setUp(() {
      repoIdRoot = installRepoIdFixture();
      RepositoryIdLookup.clearCache(executionRoot: repoIdRoot);
    });

    tearDown(() {
      RepositoryIdLookup.clearCache(executionRoot: repoIdRoot);
      removeWorkspace(repoIdRoot);
    });

    test('BB-FLT-37: Resolves known repository ID to name [2026-02-14]', () {
      expect(RepositoryIdLookup.resolveToName('BSC', executionRoot: repoIdRoot),
          equals('tom_module_basics'));
      expect(RepositoryIdLookup.resolveToName('D4', executionRoot: repoIdRoot),
          equals('tom_module_d4rt'));
      expect(RepositoryIdLookup.resolveToName('CRPT', executionRoot: repoIdRoot),
          equals('tom_module_crypto'));
    });

    test('BB-FLT-38: Repository ID resolution is case-insensitive [2026-02-14]', () {
      expect(RepositoryIdLookup.resolveToName('bsc', executionRoot: repoIdRoot),
          equals('tom_module_basics'));
      expect(RepositoryIdLookup.resolveToName('Bsc', executionRoot: repoIdRoot),
          equals('tom_module_basics'));
    });

    test('BB-FLT-39: Unknown ID returns unchanged [2026-02-14]', () {
      expect(
          RepositoryIdLookup.resolveToName('unknown', executionRoot: repoIdRoot),
          equals('unknown'));
      expect(
          RepositoryIdLookup.resolveToName('tom_module_basics',
              executionRoot: repoIdRoot),
          equals('tom_module_basics'));
    });

    test('BB-FLT-40: isRepositoryId identifies known IDs [2026-02-14]', () {
      expect(RepositoryIdLookup.isRepositoryId('BSC', executionRoot: repoIdRoot),
          isTrue);
      expect(RepositoryIdLookup.isRepositoryId('bsc', executionRoot: repoIdRoot),
          isTrue); // case-insensitive
      expect(
          RepositoryIdLookup.isRepositoryId('unknown', executionRoot: repoIdRoot),
          isFalse);
      expect(
          RepositoryIdLookup.isRepositoryId('tom_module_basics',
              executionRoot: repoIdRoot),
          isFalse);
    });
  });
}
