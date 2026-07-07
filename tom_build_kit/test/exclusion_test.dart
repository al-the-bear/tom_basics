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

  /// Project paths in [projects] that live under a `core` container segment.
  ///
  /// Used by the path-pattern exclusion tests to derive a real baseline: the
  /// set of core projects that a `<container>/**` exclusion must remove.
  List<String> coreProjectsIn(Iterable<String> projects) =>
      projects.where((proj) => p.split(proj).contains('core')).toList();

  /// Derive an anchored `<container>/**` exclusion pattern from a non-empty
  /// [coreBaseline].
  ///
  /// `--exclude-projects` path patterns are glob-matched against each project's
  /// path *relative to the execution root* (anchored — see
  /// filter_pipeline._matchesRelativePath / AA7). A literal `core/*` is
  /// therefore anchored at the root and matches nothing in this nested checkout
  /// (core projects live at `tom_ai/core/...`), which is why the old
  /// assertions passed vacuously (AD7). This derives the *actual* container
  /// (e.g. `tom_ai/core`) from a baseline sample and returns `<container>/**`,
  /// whose `**` glob matches core projects at any depth (direct children and
  /// deeper `tom_core_samples/...` ones) in flat or nested layouts.
  String coreContainerPattern(List<String> coreBaseline) {
    final sample = coreBaseline.firstWhere(
      (proj) {
        final segs = p.split(proj);
        final idx = segs.indexOf('core');
        return idx >= 0 && idx < segs.length - 1;
      },
      orElse: () => coreBaseline.first,
    );
    final segs = p.split(sample);
    final coreIndex = segs.indexOf('core');
    return '${p.joinAll(segs.sublist(0, coreIndex + 1))}/**';
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

      // A literal 'core/*' is anchored at the execution root and matches
      // nothing in the nested 'tom_ai/core/...' checkout, so the old assertion
      // `isNot(startsWith('core/'))` was satisfied without the exclusion ever
      // firing — a vacuous pass (AD7, follow-up of the EXCL_MY02 fix AC3).
      //
      // Harden it: capture a real baseline, require core projects to be
      // present, derive the actual '<container>/**' pattern, apply it via the
      // CLI, and assert those core projects are genuinely removed.
      final baseline = parseListOutput(await runToolList('dependencies'))
          .where((line) => !line.startsWith('->'))
          .toList();
      final coreBaseline = coreProjectsIn(baseline);
      log.expectation(
        'baseline has core projects to exclude (${coreBaseline.length})',
        coreBaseline.isNotEmpty,
      );
      expect(
        coreBaseline,
        isNotEmpty,
        reason:
            'EXCL_PP01 needs core projects in the baseline to exercise the '
            'exclusion; found none — check the fixture layout.',
      );
      final pattern = coreContainerPattern(coreBaseline);

      final excluded = parseListOutput(
        await runToolList(
          'dependencies',
          extraArgs: ['--exclude-projects', pattern],
        ),
      ).where((line) => !line.startsWith('->')).toList();

      // Every core project present in the baseline must now be gone.
      for (final coreProj in coreBaseline) {
        expect(
          excluded,
          isNot(contains(coreProj)),
          reason: "$coreProj should be excluded by path pattern '$pattern'",
        );
      }
      final coreStillPresent = coreProjectsIn(excluded);
      log.expectation('no core projects in list', coreStillPresent.isEmpty);
      expect(coreStillPresent, isEmpty);

      // Non-core projects must survive: the exclusion removed something, not
      // everything (guards against an over-broad pattern or an empty scan).
      log.expectation(
        'other projects remain (${excluded.length} of ${baseline.length})',
        excluded.isNotEmpty && excluded.length < baseline.length,
      );
      expect(
        excluded,
        isNotEmpty,
        reason: 'non-core projects should remain after excluding core',
      );
      expect(
        excluded.length,
        lessThan(baseline.length),
        reason: 'the core exclusion must actually remove projects',
      );
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

      // Combine a basename exclusion (_build) with a *real* anchored core path
      // pattern. The old literal 'core/*' was vacuous (see EXCL_PP01 /
      // EXCL_MY02); derive the actual '<container>/**' from the baseline so
      // both halves of the combined exclusion are genuinely exercised.
      final baseline = parseListOutput(await runToolList('dependencies'))
          .where((line) => !line.startsWith('->'))
          .toList();
      final coreBaseline = coreProjectsIn(baseline);
      log.expectation(
        'baseline has _build and core projects to exclude',
        baseline.contains('_build') && coreBaseline.isNotEmpty,
      );
      expect(
        baseline,
        contains('_build'),
        reason: 'baseline should contain the provisioned _build project',
      );
      expect(
        coreBaseline,
        isNotEmpty,
        reason: 'baseline needs core projects to exercise the path pattern',
      );
      final pattern = coreContainerPattern(coreBaseline);

      final excluded = parseListOutput(
        await runToolList(
          'dependencies',
          extraArgs: [
            '--exclude-projects',
            '_build',
            '--exclude-projects',
            pattern,
          ],
        ),
      ).where((line) => !line.startsWith('->')).toList();

      log.expectation('_build excluded by basename', !excluded.contains('_build'));
      expect(
        excluded,
        isNot(contains('_build')),
        reason: '_build excluded by basename',
      );
      for (final coreProj in coreBaseline) {
        expect(
          excluded,
          isNot(contains(coreProj)),
          reason: "$coreProj should be excluded by path pattern '$pattern'",
        );
      }
      final coreStillPresent = coreProjectsIn(excluded);
      log.expectation('no core/ projects (path pattern)', coreStillPresent.isEmpty);
      expect(coreStillPresent, isEmpty);
      log.expectation(
        'other projects remain (${excluded.length} of ${baseline.length})',
        excluded.isNotEmpty && excluded.length < baseline.length,
      );
      expect(excluded, isNotEmpty);
      expect(
        excluded.length,
        lessThan(baseline.length),
        reason: 'the combined exclusion must actually remove projects',
      );
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

      // Verify buildkit's global --exclude-projects removes the provisioned
      // `_build` project (a *basename* pattern). Baseline diff: the project is
      // provisioned at the workspace root, so its path is the bare `_build`
      // (no parent segment). The old assertion `isNot(contains('/_build'))`
      // could therefore never match a root-level project even if exclusion
      // failed — and it ran via `runTool('buildkit', …)`, which emitted the
      // rejected `:buildkit` command, so it only ever inspected the error
      // message "Unknown command: :buildkit" (AD7). Route through `versioner`
      // (a valid buildkit command) and diff a real baseline against exclusion.
      final buildRe = RegExp(r'(?:^|[\s/>])_build(?:$|[\s/])', multiLine: true);

      final baselineResult = await ws.runTool('versioner', [
        '--scan',
        '.',
        '--recursive',
        '--verbose',
        '--list',
      ]);
      log.capture('versioner --verbose --list (baseline)', baselineResult);
      final baselineOut = baselineResult.stdout as String;
      log.expectation(
        'baseline lists the provisioned _build project',
        buildRe.hasMatch(baselineOut),
      );
      expect(
        buildRe.hasMatch(baselineOut),
        isTrue,
        reason:
            'EXCL_BK01 needs the provisioned _build project in the baseline '
            'to exercise the basename exclusion.',
      );

      final result = await ws.runTool('versioner', [
        '--scan',
        '.',
        '--recursive',
        '--verbose',
        '--exclude-projects',
        '_build',
        '--list',
      ]);
      log.capture(
        'versioner --verbose --exclude-projects _build --list',
        result,
      );
      final stdout = result.stdout as String;
      final excluded = !buildRe.hasMatch(stdout);
      log.expectation('_build absent from verbose output', excluded);
      expect(
        buildRe.hasMatch(stdout),
        isFalse,
        reason: '_build should not appear when excluded by basename',
      );
    });

    test('buildkit excludes by path pattern', () async {
      log.start('EXCL_BK02', 'buildkit excludes by path pattern');

      // The old test excluded literal 'core/*' and asserted the verbose output
      // no longer contained '/core/tom_core_'. That pattern is anchored at the
      // execution root (see EXCL_MY02 / filter_pipeline._matchesRelativePath),
      // so it matched nothing in the nested 'tom_ai/core/...' checkout and the
      // assertion could pass without the exclusion ever firing (AD7).
      //
      // Harden it with a baseline diff: run the same verbose scan *without*
      // exclusion, collect the core project paths that genuinely appear, derive
      // the actual '<container>/**' pattern, then re-run *with* that exclusion
      // and require every baseline core project to be gone. This fails if
      // buildkit's CLI --exclude-projects path matching stops working.
      //
      // NB: route through the `versioner` tool (runTool prepends `:versioner`
      // to the buildkit.dart invocation, so buildkit's global
      // `--exclude-projects` is what's exercised). The old test invoked
      // `runTool('buildkit', …)`, which emitted the pipeline `:buildkit`
      // command — buildkit rejects it with "Unknown command: :buildkit", so
      // the negative assertion passed against an *error message*, never against
      // a real project listing (AD7).
      final baselineResult = await ws.runTool('versioner', [
        '--scan',
        '.',
        '--recursive',
        '--verbose',
        '--list',
      ]);
      log.capture(
        'versioner --verbose --list (baseline)',
        baselineResult,
      );
      final baselineOut = baselineResult.stdout as String;

      // Core project paths present in the baseline verbose output (e.g.
      // 'tom_ai/core/tom_core_d4rt'). Matching 'tom_core_*' basenames is
      // enough to prove the exclusion — the derived '<container>/**' removes
      // every core project regardless of basename shape.
      final coreRe = RegExp(r'[\w./-]*?/core/tom_core_[\w-]+');
      final baselineCore =
          coreRe.allMatches(baselineOut).map((m) => m.group(0)!).toSet();
      log.expectation(
        'baseline verbose output has core projects (${baselineCore.length})',
        baselineCore.isNotEmpty,
      );
      expect(
        baselineCore,
        isNotEmpty,
        reason:
            'EXCL_BK02 needs core projects in the baseline scan to exercise '
            'the exclusion; found none — check the fixture layout.',
      );
      final pattern = coreContainerPattern(baselineCore.toList());

      final result = await ws.runTool('versioner', [
        '--scan',
        '.',
        '--recursive',
        '--verbose',
        '--exclude-projects',
        pattern,
        '--list',
      ]);
      log.capture(
        'versioner --verbose --exclude-projects $pattern --list',
        result,
      );
      final stdout = result.stdout as String;

      for (final coreProj in baselineCore) {
        expect(
          stdout,
          isNot(contains(coreProj)),
          reason:
              "$coreProj should not appear when excluded by path pattern "
              "'$pattern'",
        );
      }
      final coreGone = baselineCore.every((proj) => !stdout.contains(proj));
      log.expectation('core projects removed from verbose output', coreGone);

      // The exclusion must remove content, not silently produce identical or
      // empty output.
      log.expectation(
        'output shrank after exclusion (${stdout.length} < ${baselineOut.length})',
        stdout.isNotEmpty && stdout.length < baselineOut.length,
      );
      expect(stdout, isNotEmpty);
      expect(
        stdout.length,
        lessThan(baselineOut.length),
        reason: 'the core exclusion must actually remove projects',
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

      // Master YAML `exclude-projects` path patterns are glob-matched against
      // each project's path *relative to the execution root* (anchored — see
      // filter_pipeline._matchesRelativePath / AA7). A literal 'core/*' is
      // therefore anchored at the root and matches nothing in this nested
      // checkout (core projects live at 'tom_ai/core/...'), so the old
      // assertion `isNot(startsWith('core/'))` was satisfied without the
      // exclusion ever firing — a vacuous pass (AC3, follow-up of AA10).
      //
      // Harden it: capture a real baseline, derive the actual core-container
      // path from it, exclude that container's children, and assert those
      // projects are genuinely removed versus the baseline.

      // --- Baseline: true no-exclusion project set (delete any leftover
      //     master YAML from a prior test first). ---
      final masterFile = File(masterPath);
      if (masterFile.existsSync()) masterFile.deleteSync();
      final baseline = parseListOutput(await runToolList('dependencies'))
          .where((line) => !line.startsWith('->'))
          .toList();
      final coreBaseline = coreProjectsIn(baseline);
      log.expectation(
        'baseline has core projects to exclude (${coreBaseline.length})',
        coreBaseline.isNotEmpty,
      );
      expect(
        coreBaseline,
        isNotEmpty,
        reason:
            'EXCL_MY02 needs at least one core project in the baseline to '
            'exercise the exclusion; found none — check the fixture layout.',
      );

      // Derive the core container (e.g. 'tom_ai/core') and exclude everything
      // beneath it with '<container>/**' — see coreContainerPattern. The '**'
      // glob matches core projects at any depth (direct children like
      // 'tom_ai/core/tom_core_kernel' and deeper ones like
      // 'tom_ai/core/tom_core_samples/core_client_sample').
      final pattern = coreContainerPattern(coreBaseline);

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
    - '$pattern'

versioner:
  variable-prefix: testDefault
''');

      final excluded = parseListOutput(await runToolList('dependencies'))
          .where((line) => !line.startsWith('->'))
          .toList();

      // Every core project present in the baseline must now be gone.
      for (final coreProj in coreBaseline) {
        expect(
          excluded,
          isNot(contains(coreProj)),
          reason:
              "$coreProj should be excluded by master YAML path pattern "
              "'$pattern'",
        );
      }
      final coreStillPresent = coreProjectsIn(excluded);
      log.expectation(
        'all core projects removed by master YAML path pattern',
        coreStillPresent.isEmpty,
      );
      expect(coreStillPresent, isEmpty);

      // Non-core projects must survive: the exclusion removed something, not
      // everything (guards against an over-broad pattern or an empty scan).
      log.expectation(
        'non-core projects remain (${excluded.length} of ${baseline.length})',
        excluded.isNotEmpty && excluded.length < baseline.length,
      );
      expect(
        excluded,
        isNotEmpty,
        reason: 'non-core projects should remain after excluding core',
      );
      expect(
        excluded.length,
        lessThan(baseline.length),
        reason: 'the core exclusion must actually remove projects',
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
      // Layout-agnostic: the framework core projects live in a `core/`
      // directory segment — flat ('core/...') or nested ('tom_ai/core/...').
      // The previous startsWith('core/') literal assumed a flat root layout and
      // found none in this nested checkout. Match any project with a `core`
      // path segment instead. (The --list output interleaves
      // '-> :dependencies listed' status lines with the clean path lines, so
      // filter the status lines out.)
      final projects = parseListOutput(stdout)
          .where((line) => !line.startsWith('->'))
          .toList();
      final coreProjects = projects
          .where((proj) => p.split(proj).contains('core'))
          .toList();
      final found = coreProjects.isNotEmpty;
      log.expectation('core projects found (${coreProjects.length})', found);
      expect(
        coreProjects,
        isNotEmpty,
        reason: 'core projects should be found when no exclusions applied',
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
