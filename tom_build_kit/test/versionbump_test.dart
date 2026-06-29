/// Integration tests for the VersionBump tool.
///
/// **Bug #13 is FIXED** — the `-v` abbreviation conflict has been resolved
/// by removing the `-v` abbreviation from `--versioner`.
///
/// Test IDs: VBM_BUG13, VBM_PAT01, VBM_MIN01, VBM_MAJ01, VBM_RST01, VBM_DRY01
@TestOn('!browser')
@Timeout(Duration(seconds: 120))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/test_workspace.dart';

void main() {
  late TestWorkspace ws;
  late TestLogger log;

  setUpAll(() async {
    ws = TestWorkspace();
    print('');
    print('╔══════════════════════════════════════════════════════╗');
    print('║          VersionBump Integration Tests               ║');
    print('╚══════════════════════════════════════════════════════╝');
    print('Workspace root:  ${ws.workspaceRoot}');
    print('Buildkit root:   ${ws.buildkitRoot}');
    print('');
    await ws.requireCleanWorkspace();
    await ws.saveHeadRefs();
  });

  setUp(() async {
    log = TestLogger(ws);
    // Provision the `_build` project each test so its pubspec.yaml exists.
    // The versionbump tests read/bump `<root>/_build/pubspec.yaml`; without
    // this the file is absent and VBM_PAT01 (et al.) throw
    // PathNotFoundException. installFixture also lays down a
    // buildkit_master.yaml (workspace defaults) and is the same provisioning
    // pattern used by exclusion_test / config_merge_test. tearDownAll already
    // calls deprovisionBuildProject(), confirming provisioning was intended
    // here but omitted.
    await ws.installFixture('versioner');
  });

  tearDown(() async {
    log.finish();
    await ws.revertAll();
  });

  tearDownAll(() async {
    print('');
    print('  ── VersionBump Tests: Tear-down ──');
    await ws.verifyHeadRefs();
    // Symmetric with requireCleanWorkspace's deprovision at suite start:
    // remove the test-provisioned `_build` so the tree is clean post-run.
    await ws.deprovisionBuildProject();
    print('  ── VersionBump Tests: Complete ──');
  });

  // ── Bug #13 FIXED: --help now works ──────────────────────────────────

  test('Bug #13 FIXED: --help works after removing -v abbreviation',
      () async {
    log.start('VBM_BUG13', 'versionbump --help works');
    final result = await ws.runTool('bumpversion', ['--help']);
    log.capture('versionbump --help', result);

    expect(result.exitCode, equals(0),
        reason: 'Bug #13 fixed: versionbump --help should succeed');
    final stdout = (result.stdout as String);
    expect(stdout, contains('Usage'),
        reason: '--help should show usage text');
    expect(stdout, contains('--versioner'),
        reason: '--help should list --versioner option');
    log.expectation('exit code 0', result.exitCode == 0);
    log.expectation('shows usage', stdout.contains('Usage'));
  });

  // ── Patch bump (VBM_PAT01) ───────────────────────────────────────────

  test('default patch bump', () async {
    log.start('VBM_PAT01', 'default patch bump');

    // Read current version
    final pubspecPath =
        p.join(ws.workspaceRoot, '_build', 'pubspec.yaml');
    final beforeContent = File(pubspecPath).readAsStringSync();
    final versionMatch =
        RegExp(r'version:\s*(\S+)').firstMatch(beforeContent);
    final beforeVersion = versionMatch?.group(1) ?? '0.0.0';
    print('    Before version: $beforeVersion');

    final result =
        await ws.runTool('bumpversion', ['--project', '_build']);
    log.capture('versionbump --project _build', result);

    expect(result.exitCode, equals(0),
        reason: 'versionbump should succeed');

    final afterContent = File(pubspecPath).readAsStringSync();
    final afterMatch =
        RegExp(r'version:\s*(\S+)').firstMatch(afterContent);
    final afterVersion = afterMatch?.group(1) ?? '0.0.0';
    print('    After version: $afterVersion');

    expect(afterVersion, isNot(equals(beforeVersion)),
        reason: 'Version should be bumped');

    final stdout = (result.stdout as String);
    expect(stdout.toLowerCase(), contains('bump'),
        reason: 'Output should mention bumping');
    log.expectation('version changed', afterVersion != beforeVersion);
  });

  // ── Minor bump (VBM_MIN01) ───────────────────────────────────────────

  test('--minor bump for specific project', () async {
    log.start('VBM_MIN01', '--minor bump');

    final pubspecPath =
        p.join(ws.workspaceRoot, '_build', 'pubspec.yaml');
    final beforeContent = File(pubspecPath).readAsStringSync();
    final versionMatch =
        RegExp(r'version:\s*(\d+)\.(\d+)\.(\d+)').firstMatch(beforeContent);
    final beforeMinor = int.tryParse(versionMatch?.group(2) ?? '0') ?? 0;

    final result = await ws.runTool(
        'bumpversion', ['--minor', '_build', '--project', '_build']);
    log.capture('versionbump --minor _build --project _build', result);

    expect(result.exitCode, equals(0),
        reason: '--minor bump should succeed');

    final afterContent = File(pubspecPath).readAsStringSync();
    final afterMatch =
        RegExp(r'version:\s*(\d+)\.(\d+)\.(\d+)').firstMatch(afterContent);
    final afterMinor = int.tryParse(afterMatch?.group(2) ?? '0') ?? 0;

    expect(afterMinor, equals(beforeMinor + 1),
        reason: 'Minor version should increase by 1');
    log.expectation('minor bumped', afterMinor == beforeMinor + 1);
  });

  // ── Major bump (VBM_MAJ01) ───────────────────────────────────────────

  test('--major bump for specific project', () async {
    log.start('VBM_MAJ01', '--major bump');

    final pubspecPath =
        p.join(ws.workspaceRoot, '_build', 'pubspec.yaml');
    final beforeContent = File(pubspecPath).readAsStringSync();
    final versionMatch =
        RegExp(r'version:\s*(\d+)\.(\d+)\.(\d+)').firstMatch(beforeContent);
    final beforeMajor = int.tryParse(versionMatch?.group(1) ?? '0') ?? 0;

    final result = await ws.runTool(
        'bumpversion', ['--major', '_build', '--project', '_build']);
    log.capture('versionbump --major _build --project _build', result);

    expect(result.exitCode, equals(0),
        reason: '--major bump should succeed');

    final afterContent = File(pubspecPath).readAsStringSync();
    final afterMatch =
        RegExp(r'version:\s*(\d+)\.(\d+)\.(\d+)').firstMatch(afterContent);
    final afterMajor = int.tryParse(afterMatch?.group(1) ?? '0') ?? 0;

    expect(afterMajor, equals(beforeMajor + 1),
        reason: 'Major version should increase by 1');
    log.expectation('major bumped', afterMajor == beforeMajor + 1);
  });

  // ── Build counter reset (VBM_RST01) ──────────────────────────────────

  test('build counter reset after bump', () async {
    log.start('VBM_RST01', 'build counter reset');

    final result =
        await ws.runTool('bumpversion', ['--project', '_build']);
    log.capture('versionbump --project _build', result);

    expect(result.exitCode, equals(0),
        reason: 'versionbump should succeed');

    // Check tom_build_state.json has buildNumber: 0
    final stateFile = File(
        p.join(ws.workspaceRoot, '_build', 'tom_build_state.json'));
    if (stateFile.existsSync()) {
      final state =
          jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>;
      final buildNumber = state['buildNumber'] as int? ?? -1;
      expect(buildNumber, equals(0),
          reason: 'Build number should be reset to 0 after bump');
      log.expectation('buildNumber is 0', buildNumber == 0);
    } else {
      // State file may not exist if tool doesn't create it for this project
      log.expectation('state file exists', false);
    }
  });

  // ── Dry-run (VBM_DRY01) ─────────────────────────────────────────────

  test('--dry-run shows planned bumps without changing files', () async {
    log.start('VBM_DRY01', '--dry-run');

    final pubspecPath =
        p.join(ws.workspaceRoot, '_build', 'pubspec.yaml');
    final beforeContent = File(pubspecPath).readAsStringSync();

    final result = await ws.runTool(
        'bumpversion', ['--dry-run', '--project', '_build']);
    log.capture('versionbump --dry-run --project _build', result);

    expect(result.exitCode, equals(0),
        reason: '--dry-run should succeed');

    // pubspec.yaml should be unchanged
    final afterContent = File(pubspecPath).readAsStringSync();
    expect(afterContent, equals(beforeContent),
        reason: '--dry-run should not modify pubspec.yaml');

    final stdout = (result.stdout as String);
    // Should show planned changes
    final hasInfo = stdout.contains('→') || stdout.contains('->') ||
        stdout.contains('bump') || stdout.contains('DRY');
    expect(hasInfo, isTrue,
        reason: '--dry-run should show planned bump information');
    log.expectation('file unchanged', afterContent == beforeContent);
    log.expectation('shows planned info', hasInfo);
  });
}
