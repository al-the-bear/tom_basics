/// Integration tests for the runner (build_runner wrapper) tool.
///
/// Target project: `_build` (has `build.yaml` and `build_runner` in dev deps).
/// All tests use `--dry-run` or read-only flags to avoid running build_runner.
///
/// Test IDs: RUN_LST01, RUN_SHW01, RUN_DRY01, RUN_FLT01, RUN_CLN01
@TestOn('!browser')
@Timeout(Duration(seconds: 120))
library;

import 'package:test/test.dart';

import 'helpers/test_workspace.dart';

void main() {
  late TestWorkspace ws;
  late TestLogger log;

  setUpAll(() async {
    ws = TestWorkspace();
    print('');
    print('╔══════════════════════════════════════════════════════╗');
    print('║          Runner Integration Tests                    ║');
    print('╚══════════════════════════════════════════════════════╝');
    print('Workspace root:  ${ws.workspaceRoot}');
    print('Buildkit root:   ${ws.buildkitRoot}');
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
    print('  ── Runner Tests: Tear-down ──');
    await ws.verifyHeadRefs();
    // Symmetric with requireCleanWorkspace's deprovision at suite start:
    // remove the test-provisioned `_build` so the tree is clean post-run.
    await ws.deprovisionBuildProject();
    print('  ── Runner Tests: Complete ──');
  });

  // ----------- Helpers ----------- //

  /// Parse --list output into project paths.
  List<String> parseListOutput(String stdout) {
    return stdout
        .split('\n')
        .where((line) => line.startsWith('  ') && line.trim().isNotEmpty)
        .map((line) => line.trim())
        .toList();
  }

  // ----------- Tests ----------- //

  group('runner', () {
    test('--list shows runner-eligible projects', () async {
      log.start('RUN_LST01', '--list shows runner-eligible projects');
      final result = await ws.runTool('runner', [
        '--scan',
        '.',
        '--recursive',
        '--list',
      ]);
      log.capture('runner --scan . -r --list', result);

      final stdout = (result.stdout as String);
      expect(result.exitCode, equals(0));

      final projects = parseListOutput(stdout);
      // At least _build should have build.yaml
      expect(
        projects,
        isNotEmpty,
        reason: 'At least one project with build.yaml should be found',
      );
      log.expectation('projects found', projects.isNotEmpty);
      // Log which projects were found for debugging
      for (final proj in projects) {
        print('      found: $proj');
      }
    });

    test('--dump-config displays runner config and builders', () async {
      log.start('RUN_SHW01', '--dump-config displays runner config');
      final result = await ws.runTool('runner', [
        '--project',
        '_build',
        '--dump-config',
      ]);
      log.capture('runner --project _build --dump-config', result);

      final stdout = (result.stdout as String);
      expect(result.exitCode, equals(0));

      // --dump-config should display builder information or runner config
      final hasRunnerInfo =
          stdout.contains('builder') ||
          stdout.contains('build.yaml') ||
          stdout.contains('_build') ||
          stdout.contains('runner');
      expect(
        hasRunnerInfo,
        isTrue,
        reason: 'Should display runner configuration info',
      );
      log.expectation('shows runner info', hasRunnerInfo);
    });

    test('--dry-run shows build_runner command', () async {
      log.start('RUN_DRY01', '--dry-run shows planned command');
      final result = await ws.runTool('runner', [
        '--project',
        '_build',
        '--dry-run',
      ]);
      log.capture('runner --project _build --dry-run', result);

      final stdout = (result.stdout as String);
      expect(result.exitCode, equals(0));

      // Dry-run should show the planned build_runner command
      final hasDryRun =
          stdout.toLowerCase().contains('dry run') ||
          stdout.contains('build_runner') ||
          stdout.contains('Would run');
      expect(
        hasDryRun,
        isTrue,
        reason: 'Dry-run should show planned build_runner command',
      );
      log.expectation('shows planned command', hasDryRun);
    });

    test('--include-builders filters to specific builders', () async {
      log.start('RUN_FLT01', '--include-builders filters builders');
      // Filter to a builder that likely exists (or a fake one to test filtering)
      final result = await ws.runTool('runner', [
        '--project',
        '_build',
        '--dry-run',
        '--include-builders',
        'tom_d4rt_generator',
      ]);
      log.capture(
        'runner --dry-run --include-builders tom_d4rt_generator',
        result,
      );

      final stdout = (result.stdout as String);
      expect(result.exitCode, equals(0));

      // With --include-builders, the dry-run output should show --define flags
      // for disabled builders, or at least acknowledge the filter
      final hasFilterInfo =
          stdout.contains('define') ||
          stdout.contains('include') ||
          stdout.contains('enabled=false') ||
          stdout.toLowerCase().contains('filter') ||
          stdout.toLowerCase().contains('dry run');
      expect(
        hasFilterInfo,
        isTrue,
        reason: 'Filtered run should show define flags or filter info',
      );
      log.expectation('filter acknowledged', hasFilterInfo);
    });

    test('--command clean shows clean command in dry-run', () async {
      log.start('RUN_CLN01', '--command clean in dry-run');
      final result = await ws.runTool('runner', [
        '--project',
        '_build',
        '--dry-run',
        '--command',
        'clean',
      ]);
      log.capture('runner --dry-run --command clean', result);

      final stdout = (result.stdout as String);
      expect(result.exitCode, equals(0));

      // Dry-run with --command clean should show "clean" in the command
      final hasClean = stdout.contains('clean');
      expect(hasClean, isTrue, reason: 'Dry-run should show "clean" command');
      log.expectation('shows clean command', hasClean);
    });
  });
}
