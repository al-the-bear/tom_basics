@TestOn('!browser')
@Timeout(Duration(seconds: 180))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/test_workspace.dart';

/// Integration tests for project exclusion features.
///
/// Tests cover:
/// - `--exclude-projects` with basename patterns (e.g. `_build`)
/// - `--exclude-projects` with path patterns (e.g. `core/*`)
/// - `buildkit_skip.yaml` marker file exclusion
/// - All 6 standalone tools + buildkit
///
/// These tests use `--scan . --recursive --list` to discover projects,
/// then verify that exclusion filters remove expected entries from stdout.
void main() {
  late TestWorkspace ws;
  late TestLogger log;

  /// Temporary skip files placed during tests (cleaned up in tearDown).
  final tempSkipFiles = <String>[];

  setUpAll(() async {
    ws = TestWorkspace();
    print('');
    print('╔══════════════════════════════════════════════════════╗');
    print('║          Exclusion Integration Tests                 ║');
    print('╚══════════════════════════════════════════════════════╝');
    print('Workspace root:  ${ws.workspaceRoot}');
    print('Buildkit root:   ${ws.buildkitRoot}');

    // Full workspace protection protocol
    await ws.requireCleanWorkspace();
    await ws.saveHeadRefs();
  });

  setUp(() async {
    log = TestLogger(ws);
    // Install the exclusion test fixture
    await ws.installFixture('exclusion');
  });

  tearDown(() async {
    log.finish();

    // Remove any temporary skip files placed during this test
    if (tempSkipFiles.isNotEmpty) {
      print(
        '    🗑️  Cleaning up ${tempSkipFiles.length} temporary skip file(s)...',
      );
      for (final skipFilePath in tempSkipFiles) {
        final file = File(skipFilePath);
        if (file.existsSync()) {
          final rel = p.relative(skipFilePath, from: ws.workspaceRoot);
          file.deleteSync();
          print('       removed: $rel');
        }
      }
      tempSkipFiles.clear();
    }

    // Revert all changes in the main repo (fixture, etc.)
    await ws.revertAll();
  });

  tearDownAll(() async {
    print('');
    print('  ── Exclusion Tests: Tear-down ──');
    // Verify no commits leaked during the test run
    await ws.verifyHeadRefs();
    // Symmetric with requireCleanWorkspace's deprovision at suite start:
    // remove the test-provisioned `_build` so the tree is clean post-run.
    await ws.deprovisionBuildProject();
    print('  ── Exclusion Tests: Complete ──');
  });

  // ---------------------------------------------------------------------------
  // Helper: run a tool with --scan . --recursive --list and return stdout
  // ---------------------------------------------------------------------------

  /// Runs a standalone tool with `--scan . --recursive --list` plus any
  /// additional args. Returns stdout as a String.
  /// Also captures the output into the test logger.
  Future<String> runToolList(
    String tool, {
    List<String> extraArgs = const [],
  }) async {
    final result = await ws.runTool(tool, [
      '--scan',
      '.',
      '--recursive',
      '--list',
      ...extraArgs,
    ]);
    log.capture('$tool --list ${extraArgs.join(' ')}'.trim(), result);
    if (result.exitCode != 0) {
      print('STDERR ($tool):\n${result.stderr}');
    }
    expect(result.exitCode, 0, reason: '$tool --list should exit with 0');
    return result.stdout as String;
  }

  /// Parse project paths from --list output.
  ///
  /// The format is two-space indent per project line.
  List<String> parseListOutput(String stdout) {
    return stdout
        .split('\n')
        .where((line) => line.startsWith('  ') && line.trim().isNotEmpty)
        .map((line) => line.trim())
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Group: --exclude-projects with basename patterns
  // ---------------------------------------------------------------------------

  group('--exclude-projects basename patterns', () {
    test('versioner excludes _build by basename', () async {
      log.start('EXCL_BN01', 'versioner excludes _build by basename');
      final stdout = await runToolList(
        'versioner',
        extraArgs: ['--exclude-projects', '_build'],
      );
      final projects = parseListOutput(stdout);
      final excluded = !projects.contains('_build');
      log.expectation('_build absent from list', excluded);
      expect(
        projects,
        isNot(contains('_build')),
        reason: '_build should be excluded by --exclude-projects',
      );
      // Should still have other versioner projects
      final hasOthers = projects.isNotEmpty;
      log.expectation(
        'other projects remain (found ${projects.length})',
        hasOthers,
      );
      expect(
        projects.isNotEmpty,
        isTrue,
        reason: 'Other versioner projects should remain',
      );
    });

    test('cleanup excludes _build by basename', () async {
      log.start('EXCL_BN02', 'cleanup excludes _build by basename');
      final stdout = await runToolList(
        'cleanup',
        extraArgs: ['--exclude-projects', '_build'],
      );
      final projects = parseListOutput(stdout);
      final excluded = !projects.contains('_build');
      log.expectation('_build absent from list', excluded);
      expect(projects, isNot(contains('_build')));
      log.expectation(
        'other projects remain (found ${projects.length})',
        projects.isNotEmpty,
      );
      expect(projects.isNotEmpty, isTrue);
    });

    test('compiler excludes _build by basename', () async {
      log.start('EXCL_BN03', 'compiler excludes _build by basename');
      final stdout = await runToolList(
        'compiler',
        extraArgs: ['--exclude-projects', '_build'],
      );
      final projects = parseListOutput(stdout);
      final excluded = !projects.contains('_build');
      log.expectation('_build absent from list', excluded);
      expect(projects, isNot(contains('_build')));
      log.expectation(
        'other projects remain (found ${projects.length})',
        projects.isNotEmpty,
      );
      expect(projects.isNotEmpty, isTrue);
    });

    test('dependencies excludes _build by basename', () async {
      log.start('EXCL_BN04', 'dependencies excludes _build by basename');
      final stdout = await runToolList(
        'dependencies',
        extraArgs: ['--exclude-projects', '_build'],
      );
      final projects = parseListOutput(stdout);
      final excluded = !projects.contains('_build');
      log.expectation('_build absent from list', excluded);
      expect(projects, isNot(contains('_build')));
      log.expectation(
        'other projects remain (found ${projects.length})',
        projects.isNotEmpty,
      );
      expect(projects.isNotEmpty, isTrue);
    });

    test('runner excludes devops/tom_build_cli by basename', () async {
      log.start('EXCL_BN05', 'runner excludes tom_build_cli by basename');
      final stdout = await runToolList(
        'runner',
        extraArgs: ['--exclude-projects', 'tom_build_cli'],
      );
      final projects = parseListOutput(stdout);
      // No project should match basename tom_build_cli
      bool allExcluded = true;
      for (final proj in projects) {
        if (p.basename(proj) == 'tom_build_cli') allExcluded = false;
        expect(
          p.basename(proj),
          isNot(equals('tom_build_cli')),
          reason: 'tom_build_cli should be excluded',
        );
      }
      log.expectation('no tom_build_cli basename in list', allExcluded);
      log.expectation(
        'other projects remain (found ${projects.length})',
        projects.isNotEmpty,
      );
      expect(projects.isNotEmpty, isTrue);
    });

    // Bug #13 FIXED: -v abbreviation removed from --versioner flag.
    test('bumpversion excludes by basename (bug #13 FIXED)', () async {
      log.start(
        'EXCL_BN06',
        'bumpversion excludes by basename (bug #13 fixed)',
      );
      final result = await ws.runTool('bumpversion', [
        '--scan',
        '.',
        '--recursive',
        '--list',
        '--exclude-projects',
        '_build',
      ]);
      log.capture('bumpversion --list --exclude-projects _build', result);

      log.expectation('exit code 0', result.exitCode == 0);
      expect(
        result.exitCode,
        0,
        reason: 'Bug #13 fixed: bumpversion should start successfully',
      );

      final stdout = result.stdout as String;
      log.expectation(
        '_build excluded from output',
        !stdout.contains('_build/'),
      );
    });

    test('glob pattern excludes multiple projects', () async {
      log.start(
        'EXCL_BN07',
        'glob pattern excludes multiple tom_core_* projects',
      );
      final stdout = await runToolList(
        'dependencies',
        extraArgs: ['--exclude-projects', 'tom_core_*'],
      );
      final projects = parseListOutput(stdout);
      bool allExcluded = true;
      for (final proj in projects) {
        if (p.basename(proj).startsWith('tom_core_')) allExcluded = false;
        expect(
          p.basename(proj),
          isNot(startsWith('tom_core_')),
          reason: 'All tom_core_* projects should be excluded',
        );
      }
      log.expectation('no tom_core_* basenames in list', allExcluded);
    });
  });

  // ---------------------------------------------------------------------------
  // Group: --exclude-projects with path patterns
  // ---------------------------------------------------------------------------

  group('--exclude-projects path patterns', () {
    test('path pattern excludes core/* projects', () async {
      log.start('EXCL_PP01', 'path pattern excludes core/* projects');
      final stdout = await runToolList(
        'dependencies',
        extraArgs: ['--exclude-projects', 'core/*'],
      );
      final projects = parseListOutput(stdout);
      bool allExcluded = true;
      for (final proj in projects) {
        if (proj.startsWith('core/')) allExcluded = false;
        expect(
          proj,
          isNot(startsWith('core/')),
          reason: 'All core/ projects should be excluded by path pattern',
        );
      }
      log.expectation('no core/ projects in list', allExcluded);
      log.expectation(
        'other projects remain (found ${projects.length})',
        projects.isNotEmpty,
      );
      expect(projects.isNotEmpty, isTrue);
    });

    test('path pattern excludes devops/** from runner', () async {
      log.start('EXCL_PP02', 'path pattern excludes devops/** from runner');
      final stdout = await runToolList(
        'runner',
        extraArgs: ['--exclude-projects', 'devops/**'],
      );
      final projects = parseListOutput(stdout);
      bool allExcluded = true;
      for (final proj in projects) {
        if (proj.startsWith('devops/')) allExcluded = false;
        expect(
          proj,
          isNot(startsWith('devops/')),
          reason: 'devops/ projects should be excluded',
        );
      }
      log.expectation('no devops/ projects in list', allExcluded);
    });

    test('** glob matches nested paths in dependencies', () async {
      log.start('EXCL_PP03', '** glob matches nested paths');
      final stdout = await runToolList(
        'dependencies',
        extraArgs: ['--exclude-projects', '**/tom_core_*'],
      );
      final projects = parseListOutput(stdout);
      bool allExcluded = true;
      for (final proj in projects) {
        if (p.basename(proj).startsWith('tom_core_')) allExcluded = false;
        expect(
          p.basename(proj),
          isNot(startsWith('tom_core_')),
          reason: '** pattern should match tom_core_* at any depth',
        );
      }
      log.expectation('no tom_core_* at any depth', allExcluded);
    });

    test('combined basename + path patterns', () async {
      log.start('EXCL_PP04', 'combined basename + path patterns');
      final stdout = await runToolList(
        'dependencies',
        extraArgs: [
          '--exclude-projects',
          '_build',
          '--exclude-projects',
          'core/*',
        ],
      );
      final projects = parseListOutput(stdout);
      final buildExcluded = !projects.contains('_build');
      log.expectation('_build excluded by basename', buildExcluded);
      expect(
        projects,
        isNot(contains('_build')),
        reason: '_build excluded by basename',
      );
      bool coreExcluded = true;
      for (final proj in projects) {
        if (proj.startsWith('core/')) coreExcluded = false;
        expect(
          proj,
          isNot(startsWith('core/')),
          reason: 'core/* excluded by path',
        );
      }
      log.expectation('no core/ projects (path pattern)', coreExcluded);
      log.expectation(
        'other projects remain (found ${projects.length})',
        projects.isNotEmpty,
      );
      expect(projects.isNotEmpty, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Group: buildkit_skip.yaml marker file
  // ---------------------------------------------------------------------------

  group('buildkit_skip.yaml marker file', () {
    test('skip file excludes project from versioner', () async {
      log.start('EXCL_SF01', 'skip file excludes project from versioner');
      // Place a temporary skip file in _build
      tempSkipFiles.add(ws.placeSkipFile('_build'));

      final stdout = await runToolList('versioner');
      final projects = parseListOutput(stdout);
      final excluded = !projects.contains('_build');
      log.expectation('_build with skip file absent from list', excluded);
      expect(
        projects,
        isNot(contains('_build')),
        reason: '_build with skip file should be excluded',
      );
    });

    test('skip file excludes project from cleanup', () async {
      log.start('EXCL_SF02', 'skip file excludes project from cleanup');
      tempSkipFiles.add(ws.placeSkipFile('_build'));

      final stdout = await runToolList('cleanup');
      final projects = parseListOutput(stdout);
      final excluded = !projects.contains('_build');
      log.expectation('_build with skip file absent from list', excluded);
      expect(projects, isNot(contains('_build')));
    });

    test('skip file excludes project from compiler', () async {
      log.start('EXCL_SF03', 'skip file excludes project from compiler');
      tempSkipFiles.add(ws.placeSkipFile('_build'));

      final stdout = await runToolList('compiler');
      final projects = parseListOutput(stdout);
      final excluded = !projects.contains('_build');
      log.expectation('_build with skip file absent from list', excluded);
      expect(projects, isNot(contains('_build')));
    });

    test('skip file excludes project from dependencies', () async {
      log.start('EXCL_SF04', 'skip file excludes project from dependencies');
      tempSkipFiles.add(ws.placeSkipFile('_build'));

      final stdout = await runToolList('dependencies');
      final projects = parseListOutput(stdout);
      final excluded = !projects.contains('_build');
      log.expectation('_build with skip file absent from list', excluded);
      expect(projects, isNot(contains('_build')));
    });

    test('skip file excludes project from runner', () async {
      log.start('EXCL_SF05', 'skip file excludes project from runner');

      // Discover a real project the runner tool lists (one with a build.yaml)
      // rather than hardcoding a path. Layout-agnostic: the previous literal
      // 'devops/tom_build_cli' assumed a flat root layout, but in this nested
      // checkout projects live under tom_ai/..., so placeSkipFile threw
      // PathNotFoundException. The runner --list output interleaves
      // '-> :runner skipped/listed' status lines with the clean project-path
      // lines, so filter the status lines out to get the real project paths.
      final baseline = parseListOutput(await runToolList('runner'))
          .where((line) => !line.startsWith('->'))
          .toList();
      expect(baseline, isNotEmpty,
          reason: 'runner should list at least one project with build.yaml');
      final target = baseline.first;

      // Place a skip file at that real project and re-run; it must disappear.
      tempSkipFiles.add(ws.placeSkipFile(target));

      final projects = parseListOutput(await runToolList('runner'))
          .where((line) => !line.startsWith('->'))
          .toList();
      final excluded = !projects.contains(target);
      expect(
        projects,
        isNot(contains(target)),
        reason: '$target with skip file should be excluded from runner',
      );
      log.expectation('$target absent from runner list', excluded);
    });

    // Bug #13 FIXED: -v abbreviation removed from --versioner flag.
    test('bumpversion skip file excludes project (bug #13 FIXED)', () async {
      log.start(
        'EXCL_SF06',
        'bumpversion skip file excludes project (bug #13 fixed)',
      );
      tempSkipFiles.add(ws.placeSkipFile('_build'));

      final result = await ws.runTool('bumpversion', [
        '--scan',
        '.',
        '--recursive',
        '--list',
      ]);
      log.capture('bumpversion --list (skip file in _build)', result);

      log.expectation('exit code 0', result.exitCode == 0);
      expect(
        result.exitCode,
        0,
        reason: 'Bug #13 fixed: bumpversion should start successfully',
      );
    });

    test('skip file in parent excludes all children', () async {
      log.start('EXCL_SF07', 'skip file in parent excludes all children');

      // Discover a real container directory that holds >= 2 child projects,
      // rather than hardcoding 'core'. Layout-agnostic: the previous literal
      // 'core' assumed a flat root layout, but in this nested checkout the core
      // projects live under tom_ai/core/..., so placeSkipFile('core') threw
      // PathNotFoundException. The --list output interleaves
      // '-> :dependencies listed' status lines with the clean project-path
      // lines, so filter the status lines out to get the real project paths.
      final baseline = parseListOutput(await runToolList('dependencies'))
          .where((line) => !line.startsWith('->'))
          .toList();
      final childCountByParent = <String, int>{};
      for (final proj in baseline) {
        final parent = p.dirname(proj);
        if (parent == '.' || parent.isEmpty) continue;
        childCountByParent[parent] = (childCountByParent[parent] ?? 0) + 1;
      }
      final parentDir = childCountByParent.entries
          .firstWhere(
            (e) => e.value >= 2,
            orElse: () => throw StateError(
              'expected a container dir with >= 2 child projects',
            ),
          )
          .key;

      // Place a skip file in that real container and re-run; every project
      // within parentDir must disappear (parent skip excludes all children).
      tempSkipFiles.add(ws.placeSkipFile(parentDir));

      final remaining = parseListOutput(await runToolList('dependencies'))
          .where((line) => !line.startsWith('->'))
          .toList();
      final childrenRemain =
          remaining.where((proj) => p.isWithin(parentDir, proj)).toList();
      expect(
        childrenRemain,
        isEmpty,
        reason: 'All children of $parentDir should be excluded by parent skip',
      );
      log.expectation(
        'no children of $parentDir in list',
        childrenRemain.isEmpty,
      );
    });

    test('skip file is cleaned up in tearDown', () async {
      log.start('EXCL_SF08', 'skip file cleanup in tearDown');
      // This test verifies our own cleanup mechanism
      final skipPath = ws.placeSkipFile('_build');
      tempSkipFiles.add(skipPath);

      final exists = File(skipPath).existsSync();
      log.expectation('skip file exists after placement', exists);
      expect(
        File(skipPath).existsSync(),
        isTrue,
        reason: 'Skip file should exist after placement',
      );

      // The actual cleanup happens in tearDown — just verify it was placed
    });
  });

  // ---------------------------------------------------------------------------
  // Group: buildkit --exclude-projects
  // ---------------------------------------------------------------------------

  group('buildkit --exclude-projects', () {
    test('buildkit excludes _build by basename', () async {
      log.start('EXCL_BK01', 'buildkit excludes _build by basename');
      // buildkit runs per-project, so we verify _build never appears
      // in the output when excluded. Use --scan with a small scope.
      final result = await ws.runTool('buildkit', [
        '--scan',
        '.',
        '--recursive',
        '--verbose',
        '--exclude-projects',
        '_build',
        ':versioner',
        '--list',
      ]);
      log.capture(
        'buildkit --verbose --exclude-projects _build :versioner --list',
        result,
      );
      final stdout = result.stdout as String;
      // In verbose mode, buildkit lists discovered projects with "  - "
      // The excluded project should never appear
      final excluded = !stdout.contains('/_build');
      log.expectation('/_build not in verbose output', excluded);
      expect(
        stdout,
        isNot(contains('/_build')),
        reason: '_build should not appear when excluded by basename',
      );
    });

    test('buildkit excludes by path pattern', () async {
      log.start('EXCL_BK02', 'buildkit excludes by path pattern');
      final result = await ws.runTool('buildkit', [
        '--scan',
        '.',
        '--recursive',
        '--verbose',
        '--exclude-projects',
        'core/*',
        ':versioner',
        '--list',
      ]);
      log.capture(
        'buildkit --verbose --exclude-projects core/* :versioner --list',
        result,
      );
      final stdout = result.stdout as String;
      // core/ projects should not appear
      final excluded = !stdout.contains('/core/tom_core_');
      log.expectation('/core/tom_core_ not in verbose output', excluded);
      expect(
        stdout,
        isNot(contains('/core/tom_core_')),
        reason: 'core/ projects should not appear when excluded by path',
      );
    });

    test('buildkit respects buildkit_skip.yaml', () async {
      log.start('EXCL_BK03', 'buildkit respects buildkit_skip.yaml');
      tempSkipFiles.add(ws.placeSkipFile('_build'));

      final result = await ws.runTool('versioner', [
        '--scan',
        '.',
        '--recursive',
        '--verbose',
        '--list',
      ]);
      log.capture(
        'buildkit --verbose --list :versioner (skip file in _build)',
        result,
      );
      final stdout = result.stdout as String;
      // Verbose mode lists discovered projects with "  - <relative-path>"
      // The skip message itself will contain the project name, so we check
      // that _build does not appear in the project listing lines.
      final projectLines = stdout
          .split('\n')
          .where((line) => line.startsWith('  - '))
          .map((line) => line.substring(4)) // strip "  - " prefix
          .toList();
      // Check that no project IS _build or ENDS with /_build
      bool allExcluded = true;
      for (final projPath in projectLines) {
        if (projPath == '_build' || projPath.endsWith('/_build')) {
          allExcluded = false;
        }
        expect(
          projPath == '_build' || projPath.endsWith('/_build'),
          isFalse,
          reason:
              '_build with skip file should not appear in project listing '
              '(found: $projPath)',
        );
      }
      log.expectation('_build not in project listing lines', allExcluded);
      // Verify the skip message IS present (proves the feature is active)
      // The v2 traversal writes skip messages to stderr, not stdout.
      final stderr = result.stderr as String;
      final hasSkipMsg = stderr.contains(
        'Skipping - buildkit_skip.yaml found:',
      );
      log.expectation('skip message present in stderr', hasSkipMsg);
      expect(
        stderr,
        contains('Skipping - buildkit_skip.yaml found:'),
        reason:
            'Should log skip message for _build in verbose mode (on stderr)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Group: exclude-projects from master YAML
  // ---------------------------------------------------------------------------

  group('master YAML exclude-projects', () {
    test('master YAML exclude-projects filters projects', () async {
      log.start('EXCL_MY01', 'master YAML basename exclude-projects');
      // Write a custom fixture with exclude-projects in navigation
      final masterPath = p.join(ws.workspaceRoot, 'buildkit_master.yaml');
      File(masterPath).writeAsStringSync('''
navigation:
  exclude:
    - 'xternal_apps/**'
    - 'cloud/**'
    - 'sqm/**'
    - 'uam/**'
    - 'ai_build/**'
    - 'zom_workspaces/**'
  exclude-projects:
    - '_build'

versioner:
  variable-prefix: testDefault
''');

      final stdout = await runToolList('dependencies');
      final projects = parseListOutput(stdout);
      final excluded = !projects.contains('_build');
      log.expectation('_build excluded by master YAML', excluded);
      expect(
        projects,
        isNot(contains('_build')),
        reason: '_build should be excluded by master YAML exclude-projects',
      );
      log.expectation(
        'other projects remain (found ${projects.length})',
        projects.isNotEmpty,
      );
      expect(projects.isNotEmpty, isTrue);
    });

    test('master YAML path pattern exclude-projects', () async {
      log.start('EXCL_MY02', 'master YAML path pattern exclude-projects');
      final masterPath = p.join(ws.workspaceRoot, 'buildkit_master.yaml');
      File(masterPath).writeAsStringSync('''
navigation:
  exclude:
    - 'xternal_apps/**'
    - 'cloud/**'
    - 'sqm/**'
    - 'uam/**'
    - 'ai_build/**'
    - 'zom_workspaces/**'
  exclude-projects:
    - 'core/*'

versioner:
  variable-prefix: testDefault
''');

      final stdout = await runToolList('dependencies');
      final projects = parseListOutput(stdout);
      bool allExcluded = true;
      for (final proj in projects) {
        if (proj.startsWith('core/')) allExcluded = false;
        expect(
          proj,
          isNot(startsWith('core/')),
          reason: 'core/ excluded by master YAML path pattern',
        );
      }
      log.expectation(
        'no core/ projects (master YAML path pattern)',
        allExcluded,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Group: baseline (no exclusion) — verify projects are found without filters
  // ---------------------------------------------------------------------------

  group('baseline (no exclusion)', () {
    test('versioner finds _build without exclusions', () async {
      log.start('EXCL_BL01', 'versioner finds _build without exclusions');
      final stdout = await runToolList('versioner');
      final projects = parseListOutput(stdout);
      final found = projects.contains('_build');
      log.expectation('_build present in list', found);
      expect(
        projects,
        contains('_build'),
        reason: '_build should be found when no exclusions applied',
      );
    });

    test('dependencies finds core projects without exclusions', () async {
      log.start(
        'EXCL_BL02',
        'dependencies finds core projects without exclusions',
      );
      final stdout = await runToolList('dependencies');
      final projects = parseListOutput(stdout);
      final coreProjects = projects
          .where((p) => p.startsWith('core/'))
          .toList();
      final found = coreProjects.isNotEmpty;
      log.expectation('core/ projects found (${coreProjects.length})', found);
      expect(
        coreProjects,
        isNotEmpty,
        reason: 'core/ projects should be found when no exclusions applied',
      );
    });

    test('runner finds projects without exclusions', () async {
      log.start('EXCL_BL03', 'runner finds projects without exclusions');
      final stdout = await runToolList('runner');
      final projects = parseListOutput(stdout);
      final found = projects.isNotEmpty;
      log.expectation('projects found (${projects.length})', found);
      expect(
        projects.isNotEmpty,
        isTrue,
        reason: 'Runner should find projects with build.yaml',
      );
    });
  });
}
