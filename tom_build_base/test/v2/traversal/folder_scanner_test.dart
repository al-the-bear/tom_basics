import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('BB-V2-SCN: FolderScanner Skip Files [2026-02-14]', () {
    late Directory tempDir;
    late String tempPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('folder_scanner_test_');
      tempPath = tempDir.path;
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    void createDir(String relativePath) {
      Directory(p.join(tempPath, relativePath)).createSync(recursive: true);
    }

    void createFile(String relativePath, [String content = '']) {
      final file = File(p.join(tempPath, relativePath));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    test('BB-V2-SCN-1: skips directory with tom_skip.yaml (global skip)', () async {
      // Setup: root with two subdirectories, one with tom_skip.yaml
      createDir('project_included');
      createFile('project_included/pubspec.yaml');
      createDir('project_skipped');
      createFile('project_skipped/pubspec.yaml');
      createFile('project_skipped/tom_skip.yaml', 'reason: Test skip');

      final scanner = FolderScanner();
      final results = await scanner.scan(tempPath, recursive: true);

      final paths = results.map((f) => p.basename(f.path)).toList();

      expect(paths, contains('project_included'));
      expect(paths, isNot(contains('project_skipped')),
          reason: 'Directory with tom_skip.yaml should be skipped');
    });

    test('BB-V2-SCN-2: skips directory with tool-specific skip file (buildkit_skip.yaml)', () async {
      // Setup: root with two subdirectories, one with buildkit_skip.yaml
      createDir('project_included');
      createFile('project_included/pubspec.yaml');
      createDir('project_skipped');
      createFile('project_skipped/pubspec.yaml');
      createFile('project_skipped/buildkit_skip.yaml', 'reason: Buildkit skip');

      final scanner = FolderScanner(); // Default toolBasename = 'buildkit'
      final results = await scanner.scan(tempPath, recursive: true);

      final paths = results.map((f) => p.basename(f.path)).toList();

      expect(paths, contains('project_included'));
      expect(paths, isNot(contains('project_skipped')),
          reason: 'Directory with buildkit_skip.yaml should be skipped');
    });

    test('BB-V2-SCN-3: skips directory with custom tool skip file (issuekit_skip.yaml)', () async {
      // Setup: root with two subdirectories, one with issuekit_skip.yaml
      createDir('project_included');
      createFile('project_included/pubspec.yaml');
      createDir('project_skipped');
      createFile('project_skipped/pubspec.yaml');
      createFile('project_skipped/issuekit_skip.yaml', 'reason: Issuekit skip');

      // Use issuekit as tool basename
      final scanner = FolderScanner(toolBasename: 'issuekit');
      final results = await scanner.scan(tempPath, recursive: true);

      final paths = results.map((f) => p.basename(f.path)).toList();

      expect(paths, contains('project_included'));
      expect(paths, isNot(contains('project_skipped')),
          reason: 'Directory with issuekit_skip.yaml should be skipped');
    });

    test('BB-V2-SCN-4: tool-specific skip does not affect other tools', () async {
      // Setup: directory with buildkit_skip.yaml
      createDir('project');
      createFile('project/pubspec.yaml');
      createFile('project/buildkit_skip.yaml', 'reason: Buildkit only');

      // Scan with issuekit - should NOT be skipped by buildkit_skip.yaml
      final issuekitScanner = FolderScanner(toolBasename: 'issuekit');
      final issuekitResults = await issuekitScanner.scan(tempPath, recursive: true);

      // Scan with buildkit - SHOULD be skipped
      final buildkitScanner = FolderScanner(toolBasename: 'buildkit');
      final buildkitResults = await buildkitScanner.scan(tempPath, recursive: true);

      final issuekitPaths = issuekitResults.map((f) => p.basename(f.path)).toList();
      final buildkitPaths = buildkitResults.map((f) => p.basename(f.path)).toList();

      expect(issuekitPaths, contains('project'),
          reason: 'issuekit should not be affected by buildkit_skip.yaml');
      expect(buildkitPaths, isNot(contains('project')),
          reason: 'buildkit should be skipped by buildkit_skip.yaml');
    });

    test('BB-V2-SCN-5: tom_skip.yaml affects all tools', () async {
      // Setup: directory with tom_skip.yaml
      createDir('project');
      createFile('project/pubspec.yaml');
      createFile('project/tom_skip.yaml', 'reason: Global skip');

      // Scan with different tools - all should be skipped
      final buildkitScanner = FolderScanner(toolBasename: 'buildkit');
      final issuekitScanner = FolderScanner(toolBasename: 'issuekit');
      final testkitScanner = FolderScanner(toolBasename: 'testkit');

      final buildkitResults = await buildkitScanner.scan(tempPath, recursive: true);
      final issuekitResults = await issuekitScanner.scan(tempPath, recursive: true);
      final testkitResults = await testkitScanner.scan(tempPath, recursive: true);

      final buildkitPaths = buildkitResults.map((f) => p.basename(f.path)).toList();
      final issuekitPaths = issuekitResults.map((f) => p.basename(f.path)).toList();
      final testkitPaths = testkitResults.map((f) => p.basename(f.path)).toList();

      expect(buildkitPaths, isNot(contains('project')),
          reason: 'buildkit should be skipped by tom_skip.yaml');
      expect(issuekitPaths, isNot(contains('project')),
          reason: 'issuekit should be skipped by tom_skip.yaml');
      expect(testkitPaths, isNot(contains('project')),
          reason: 'testkit should be skipped by tom_skip.yaml');
    });

    test('BB-V2-SCN-6: skip file in nested directory stops descent', () async {
      // Setup: nested structure with skip file in middle
      createDir('parent/child_included');
      createFile('parent/child_included/pubspec.yaml');
      createDir('parent/child_skipped/grandchild');
      createFile('parent/child_skipped/pubspec.yaml');
      createFile('parent/child_skipped/grandchild/pubspec.yaml');
      createFile('parent/child_skipped/tom_skip.yaml', 'reason: Skip subtree');

      final scanner = FolderScanner();
      final results = await scanner.scan(tempPath, recursive: true);

      final paths = results.map((f) => p.basename(f.path)).toList();

      expect(paths, contains('parent'));
      expect(paths, contains('child_included'));
      expect(paths, isNot(contains('child_skipped')),
          reason: 'child_skipped should be skipped');
      expect(paths, isNot(contains('grandchild')),
          reason: 'grandchild should be skipped (subtree of skipped folder)');
    });

    test('BB-V2-SCN-7: skipFilename getter returns correct filename', () {
      final buildkitScanner = FolderScanner(); // Default
      final issuekitScanner = FolderScanner(toolBasename: 'issuekit');
      final testkitScanner = FolderScanner(toolBasename: 'testkit');

      expect(buildkitScanner.skipFilename, equals('buildkit_skip.yaml'));
      expect(issuekitScanner.skipFilename, equals('issuekit_skip.yaml'));
      expect(testkitScanner.skipFilename, equals('testkit_skip.yaml'));
    });

    test('BB-V2-SCN-8: kTomSkipYaml constant is correct', () {
      expect(kTomSkipYaml, equals('tom_skip.yaml'));
    });
  });

  group('BB-V2-SCN-WS: FolderScanner Workspace Boundaries [2026-02-14]', () {
    late Directory tempDir;
    late String tempPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('folder_scanner_ws_test_');
      tempPath = tempDir.path;
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    void createDir(String relativePath) {
      Directory(p.join(tempPath, relativePath)).createSync(recursive: true);
    }

    void createFile(String relativePath, [String content = '']) {
      final file = File(p.join(tempPath, relativePath));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    test('BB-V2-SCN-WS-1: stops at nested workspace (tom_workspace.yaml)', () async {
      createDir('project');
      createFile('project/pubspec.yaml');
      createDir('nested_workspace/project');
      createFile('nested_workspace/tom_workspace.yaml');
      createFile('nested_workspace/project/pubspec.yaml');

      final scanner = FolderScanner();
      final results = await scanner.scan(tempPath, recursive: true);

      final paths = results.map((f) => p.basename(f.path)).toList();

      expect(paths, contains('project'));
      expect(paths, isNot(contains('nested_workspace')),
          reason: 'Nested workspace should be skipped');
    });

    test('BB-V2-SCN-WS-2: stops at tool master config (buildkit_master.yaml)', () async {
      createDir('project');
      createFile('project/pubspec.yaml');
      createDir('sub_workspace/project');
      createFile('sub_workspace/buildkit_master.yaml');
      createFile('sub_workspace/project/pubspec.yaml');

      final scanner = FolderScanner(); // toolBasename = 'buildkit'
      final results = await scanner.scan(tempPath, recursive: true);

      final paths = results.map((f) => p.basename(f.path)).toList();

      expect(paths, contains('project'));
      expect(paths, isNot(contains('sub_workspace')),
          reason: 'Sub-workspace with buildkit_master.yaml should be skipped');
    });

    test('BB-V2-SCN-WS-3: tool-specific master config for different tool', () async {
      createDir('project');
      createFile('project/pubspec.yaml');
      createDir('sub_workspace/project');
      createFile('sub_workspace/issuekit_master.yaml');
      createFile('sub_workspace/project/pubspec.yaml');

      // Scan with issuekit - should stop at issuekit_master.yaml
      final issuekitScanner = FolderScanner(toolBasename: 'issuekit');
      final issuekitResults = await issuekitScanner.scan(tempPath, recursive: true);

      // Scan with buildkit - should NOT stop (different tool)
      final buildkitScanner = FolderScanner(toolBasename: 'buildkit');
      final buildkitResults = await buildkitScanner.scan(tempPath, recursive: true);

      final issuekitPaths = issuekitResults.map((f) => p.basename(f.path)).toList();
      final buildkitPaths = buildkitResults.map((f) => p.basename(f.path)).toList();

      expect(issuekitPaths, isNot(contains('sub_workspace')),
          reason: 'issuekit should stop at issuekit_master.yaml');
      expect(buildkitPaths, contains('sub_workspace'),
          reason: 'buildkit should not stop at issuekit_master.yaml');
    });
  });

  group('BB-V2-GIT: GitRepoFinder.findTopRepo [2026-02-14]', () {
    late Directory tempDir;
    late String tempPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('git_repo_finder_test_');
      tempPath = tempDir.path;
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    void createDir(String relativePath) {
      Directory(p.join(tempPath, relativePath)).createSync(recursive: true);
    }

    test('BB-V2-GIT-1: returns null when no git repo in path', () {
      createDir('project');

      final finder = GitRepoFinder();
      final result = finder.findTopRepo(p.join(tempPath, 'project'));

      expect(result, isNull,
          reason: 'Should return null when no .git found in path');
    });

    test('BB-V2-GIT-2: finds single git repo in path', () {
      createDir('repo/.git');
      createDir('repo/project');

      final finder = GitRepoFinder();
      final result = finder.findTopRepo(p.join(tempPath, 'repo/project'));

      expect(result, equals(p.join(tempPath, 'repo')),
          reason: 'Should find the repo containing .git');
    });

    test('BB-V2-GIT-3: finds topmost git repo with nested repos', () {
      // Outer repo
      createDir('outer/.git');
      // Inner (nested) repo
      createDir('outer/inner/.git');
      createDir('outer/inner/project');

      final finder = GitRepoFinder();
      final result = finder.findTopRepo(p.join(tempPath, 'outer/inner/project'));

      expect(result, equals(p.join(tempPath, 'outer')),
          reason: 'Should find the topmost (outermost) repo');
    });

    test('BB-V2-GIT-4: finds topmost git repo with multiple nesting levels', () {
      // Level 1 (topmost)
      createDir('l1/.git');
      // Level 2
      createDir('l1/l2/.git');
      // Level 3
      createDir('l1/l2/l3/.git');
      createDir('l1/l2/l3/project');

      final finder = GitRepoFinder();
      final result = finder.findTopRepo(p.join(tempPath, 'l1/l2/l3/project'));

      expect(result, equals(p.join(tempPath, 'l1')),
          reason: 'Should find the topmost repo with deep nesting');
    });

    test('BB-V2-GIT-5: works when starting from repo root', () {
      createDir('repo/.git');

      final finder = GitRepoFinder();
      final result = finder.findTopRepo(p.join(tempPath, 'repo'));

      expect(result, equals(p.join(tempPath, 'repo')),
          reason: 'Should find repo when starting at repo root');
    });

    test('BB-V2-GIT-6: handles .git file (submodule worktree)', () {
      // .git can be a file in submodules pointing to the real .git directory
      createDir('repo');
      File(p.join(tempPath, 'repo/.git')).writeAsStringSync('gitdir: ../.git/modules/repo');
      createDir('repo/project');

      final finder = GitRepoFinder();
      final result = finder.findTopRepo(p.join(tempPath, 'repo/project'));

      expect(result, equals(p.join(tempPath, 'repo')),
          reason: 'Should detect .git file as well as .git directory');
    });
  });
}
