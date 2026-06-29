@TestOn('!browser')
@Timeout(Duration(seconds: 120))
library; // ignore: unnecessary_library_name

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/test_workspace.dart';

/// Integration tests for shared ToolBase functionality.
///
/// Tests features common to ALL tools (version info, help, list, exclude,
/// workspace root discovery) using the versioner tool as representative.
/// The versioner is used because it has a config section and is lightweight.
void main() {
  late TestWorkspace ws;
  late TestLogger log;

  setUpAll(() async {
    ws = TestWorkspace();
    print('');
    print('╔══════════════════════════════════════════════════════╗');
    print('║          ToolBase Integration Tests                  ║');
    print('╚══════════════════════════════════════════════════════╝');
    print('Workspace root:  ${ws.workspaceRoot}');
    print('Buildkit root:   ${ws.buildkitRoot}');

    // Full workspace protection protocol
    await ws.requireCleanWorkspace();
    await ws.saveHeadRefs();
  });

  setUp(() async {
    log = TestLogger(ws);
    await ws.installFixture('exclusion');
  });

  tearDown(() async {
    log.finish();
    await ws.revertAll();
  });

  tearDownAll(() async {
    print('');
    print('  ── ToolBase Tests: Tear-down ──');
    await ws.verifyHeadRefs();
    // Symmetric with requireCleanWorkspace's deprovision at suite start:
    // remove the test-provisioned `_build` so the tree is clean post-run.
    await ws.deprovisionBuildProject();
    print('  ── ToolBase Tests: Complete ──');
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Parse `--list` output into project relative paths.
  ///
  /// The --list output format uses 2-space indented lines for project paths.
  List<String> parseListOutput(String stdout) {
    return stdout
        .split('\n')
        .where((line) => line.startsWith('  ') && line.trim().isNotEmpty)
        .map((line) => line.trim())
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------------

  group('version argument', () {
    test('displays version info with "version" as first arg', () async {
      log.start('TB_VER01', 'displays version info');
      final result = await ws.runTool('versioner', ['version']);
      log.capture('versioner version', result);

      final stdout = (result.stdout as String).trim();
      expect(result.exitCode, equals(0),
          reason: 'Expected exit code 0 for version command');

      // Output should contain version-like info (tool name or semver)
      final hasVersionInfo = stdout.toLowerCase().contains('version') ||
          stdout.contains('versioner') ||
          RegExp(r'\d+\.\d+').hasMatch(stdout);
      expect(hasVersionInfo, isTrue,
          reason: 'Expected version info in: $stdout');
      log.expectation('output contains version info', hasVersionInfo);
    });
  });

  group('--help flag', () {
    test('displays usage information', () async {
      log.start('TB_HLP01', '--help displays usage');
      final result = await ws.runTool('versioner', ['--help']);
      log.capture('versioner --help', result);

      final stdout = (result.stdout as String);
      expect(result.exitCode, equals(0));
      expect(stdout, contains('--help'),
          reason: 'Help output should mention --help itself');
      expect(stdout, contains('--project'),
          reason: 'Help output should mention --project option');
      expect(stdout, contains('--scan'),
          reason: 'Help output should mention --scan option');
      log.expectation('contains --help', stdout.contains('--help'));
      log.expectation('contains --project', stdout.contains('--project'));
      log.expectation('contains --scan', stdout.contains('--scan'));
    });
  });

  group('--list with --scan', () {
    test('lists discovered projects with --scan and --recursive', () async {
      log.start('TB_LST01', '--list lists discovered projects');
      final result = await ws.runTool(
          'versioner', ['--scan', '.', '--recursive', '--list']);
      log.capture('versioner --scan . -r --list', result);

      final stdout = (result.stdout as String);
      expect(result.exitCode, equals(0));

      final projects = parseListOutput(stdout);
      expect(projects, isNotEmpty,
          reason: 'Expected at least one project in list output');

      // _build should be found since it has versioner config
      final hasBuild = projects.any((proj) => proj.contains('_build'));
      expect(hasBuild, isTrue,
          reason: 'Expected _build in discovered projects');
      log.expectation('projects discovered', projects.isNotEmpty);
      log.expectation('_build found', hasBuild);
    });
  });

  group('--exclude glob filtering', () {
    test('--exclude removes matching directories from scan', () async {
      log.start('TB_EXC01', '--exclude removes directories from scan');

      // Use dependencies tool — it lists ALL projects (any with pubspec.yaml),
      // not just tool-configured ones like versioner.

      // Baseline: scan without additional --exclude
      final baseline = await ws.runTool(
          'dependencies', ['--scan', '.', '--recursive', '--list']);
      log.capture('baseline (no extra --exclude)', baseline);
      final baseProjects = parseListOutput(baseline.stdout as String);

      // With --exclude: remove core/* from scan
      final filtered = await ws.runTool('dependencies',
          ['--scan', '.', '--recursive', '--list', '--exclude', 'core/*']);
      log.capture('with --exclude core/*', filtered);
      final filteredProjects = parseListOutput(filtered.stdout as String);

      expect(filtered.exitCode, equals(0));

      // Baseline should have core/ projects
      final baseHasCore =
          baseProjects.any((proj) => proj.contains('core/'));
      expect(baseHasCore, isTrue,
          reason: 'Baseline should include core/ projects');

      // Filtered should NOT have core/ projects
      final filteredHasCore =
          filteredProjects.any((proj) => proj.contains('core/'));
      expect(filteredHasCore, isFalse,
          reason: 'Filtered output should not include core/ projects');

      log.expectation('baseline has core projects', baseHasCore);
      log.expectation('filtered excludes core projects', !filteredHasCore);
    });
  });

  group('--recursion-exclude', () {
    test('prevents scanning into excluded directories', () async {
      log.start('TB_EXC02', '--recursion-exclude prevents scanning');
      final result = await ws.runTool('versioner', [
        '--scan', '.', '--recursive', '--list',
        '--recursion-exclude', 'node_modules',
      ]);
      log.capture('with --recursion-exclude node_modules', result);

      expect(result.exitCode, equals(0));

      final projects = parseListOutput(result.stdout as String);
      // Tool should still discover projects (node_modules doesn't hold Dart projects)
      expect(projects, isNotEmpty,
          reason: 'Should still find projects with --recursion-exclude');
      // No project paths should contain node_modules
      final hasNodeModules =
          projects.any((proj) => proj.contains('node_modules'));
      expect(hasNodeModules, isFalse);
      log.expectation('projects found', projects.isNotEmpty);
      log.expectation('no node_modules in paths', !hasNodeModules);
    });
  });

  group('workspace root discovery', () {
    test('discovers workspace root from a subdirectory', () async {
      log.start('TB_DSC01', 'workspace root discovery from subdirectory');

      // Run from workspace root using relative path
      final fromRoot =
          await ws.runTool('versioner', ['--project', '_build', '--list']);
      log.capture('from workspace root (relative)', fromRoot);

      // Run from _build subdirectory using absolute path
      final fromSub = await ws.runTool(
        'versioner',
        ['--project', p.join(ws.workspaceRoot, '_build'), '--list'],
        workingDirectory: p.join(ws.workspaceRoot, '_build'),
      );
      log.capture('from _build subdirectory (absolute)', fromSub);

      expect(fromRoot.exitCode, equals(0),
          reason: 'versioner from root should succeed');
      expect(fromSub.exitCode, equals(0),
          reason: 'versioner from subdirectory should succeed');
      log.expectation('from root: exit 0', fromRoot.exitCode == 0);
      log.expectation('from subdir: exit 0', fromSub.exitCode == 0);
    });
  });

  group('--exclude-projects pattern auto-detection', () {
    test('basename pattern (no /) matches folder name, path pattern (with /) matches relative path', () async {
      log.start('TB_XPJ06', 'pattern auto-detection: basename vs path');

      // Verify baseline DOES include core/tom_core_kernel
      final baseline = await ws.runTool(
          'dependencies', ['--scan', '.', '--recursive', '--list']);
      log.capture('baseline (no exclusion)', baseline);
      final baselineProjects = parseListOutput(baseline.stdout as String);
      final baselineHasKernel =
          baselineProjects.any((proj) => proj.endsWith('/tom_core_kernel') || proj == 'tom_core_kernel');
      expect(baselineHasKernel, isTrue,
          reason: 'Baseline should include tom_core_kernel');

      // Basename pattern: 'tom_core_kernel' should exclude the folder by name
      final byBasename = await ws.runTool('dependencies', [
        '--scan', '.', '--recursive', '--list',
        '--exclude-projects', 'tom_core_kernel',
      ]);
      log.capture('exclude by basename: tom_core_kernel', byBasename);

      final baseProjects = parseListOutput(byBasename.stdout as String);
      final baseHasKernel =
          baseProjects.any((proj) => proj.endsWith('/tom_core_kernel') || proj == 'tom_core_kernel');
      expect(baseHasKernel, isFalse,
          reason: 'Basename pattern should exclude tom_core_kernel');

      // Path pattern (has /): the matcher uses anchored, full-relative-path
      // glob matching against each project's path relative to the workspace
      // root. So the pattern must be the kernel's ACTUAL relative path, not a
      // partial sub-path. Derive it from the baseline output rather than
      // hardcoding a layout (the old literal 'core/tom_core_kernel' assumed a
      // non-nested layout; the kernel actually lives at
      // 'tom_ai/core/tom_core_kernel').
      final kernelRelPath = baselineProjects.firstWhere(
        (proj) => proj.endsWith('/tom_core_kernel') || proj == 'tom_core_kernel',
      );
      final byPath = await ws.runTool('dependencies', [
        '--scan', '.', '--recursive', '--list',
        '--exclude-projects', kernelRelPath,
      ]);
      log.capture('exclude by path: $kernelRelPath', byPath);

      final pathProjects = parseListOutput(byPath.stdout as String);
      final pathHasKernel =
          pathProjects.any((proj) => proj.endsWith('/tom_core_kernel') || proj == 'tom_core_kernel');
      expect(pathHasKernel, isFalse,
          reason: 'Path pattern ($kernelRelPath) should exclude the kernel');

      log.expectation('baseline includes tom_core_kernel', baselineHasKernel);
      log.expectation(
          'basename pattern excludes', !baseHasKernel);
      log.expectation(
          'path pattern excludes', !pathHasKernel);
    });
  });
}
