@TestOn('!browser')
@Timeout(Duration(seconds: 120))
library; // ignore: unnecessary_library_name

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/test_workspace.dart';

/// Integration tests for the versioner tool.
///
/// These tests use the `_build` project as the target because:
/// - It's in the main repo (no submodule complications for git revert)
/// - It has a versioner config (variable-prefix: tomTools)
/// - Its version.versioner.dart is NOT imported by tom_build_kit, so regenerating
///   it won't break the tool under test
void main() {
  late TestWorkspace ws;
  late TestLogger log;

  /// Absolute path to the _build project (target for versioner tests).
  late String targetProject;

  /// Relative path from workspace root to the version.versioner.dart file.
  late String versionFileRelative;

  setUpAll(() async {
    ws = TestWorkspace();
    targetProject = p.join(ws.workspaceRoot, '_build');
    versionFileRelative = '_build/lib/src/version.versioner.dart';
    print('');
    print('╔══════════════════════════════════════════════════════╗');
    print('║          Versioner Integration Tests                 ║');
    print('╚══════════════════════════════════════════════════════╝');
    print('Workspace root:  ${ws.workspaceRoot}');
    print('Buildkit root:   ${ws.buildkitRoot}');
    print('Target project:  $targetProject');

    // Full workspace protection protocol
    await ws.requireCleanWorkspace();
    await ws.saveHeadRefs();
  });

  setUp(() {
    log = TestLogger(ws);
  });

  tearDown(() async {
    log.finish();
    // Revert all changes in the main repo (buildkit_master.yaml,
    // _build/lib/src/version.versioner.dart, _build/tom_build_state.json)
    await ws.revertAll();
  });

  tearDownAll(() async {
    print('');
    print('  ── Versioner Tests: Tear-down ──');
    // Verify no commits leaked during the test run
    await ws.verifyHeadRefs();
    // Symmetric with requireCleanWorkspace's deprovision at suite start:
    // remove the test-provisioned `_build` so the tree is clean post-run.
    await ws.deprovisionBuildProject();
    print('  ── Versioner Tests: Complete ──');
  });

  group('versioner', () {
    test(
      '--project generates version.versioner.dart with correct prefix',
      () async {
        log.start(
          'VER_GEN01',
          '--project generates version.versioner.dart with correct prefix',
        );
        await ws.installFixture('versioner');

        final result = await ws.runTool('versioner', [
          '--project',
          targetProject,
        ]);
        log.capture('versioner --project _build', result);

        final exitOk = result.exitCode == 0;
        log.expectation('exit code 0', exitOk);
        expect(result.exitCode, 0, reason: 'versioner should exit with 0');

        // ToolRunner prints the per-item ItemResult message verbatim
        // (`  -> :versioner version file generated`). All ItemResult messages
        // use lowercase ('listed', 'config shown', …), so match that style.
        final hasMsg = (result.stdout as String).contains(
          'version file generated',
        );
        log.expectation('stdout contains "version file generated"', hasMsg);
        expect(
          result.stdout as String,
          contains('version file generated'),
          reason: 'Should report successful generation',
        );

        // The generated file should exist
        final versionFile = File(p.join(ws.workspaceRoot, versionFileRelative));
        final fileExists = versionFile.existsSync();
        log.expectation('version.versioner.dart exists', fileExists);
        expect(versionFile.existsSync(), isTrue);

        final content = versionFile.readAsStringSync();

        // _build/buildkit.yaml has variable-prefix: tomTools
        // → class name should be TomToolsVersionInfo
        final hasClass = content.contains('class TomToolsVersionInfo');
        log.expectation('class name TomToolsVersionInfo', hasClass);
        expect(
          content,
          contains('class TomToolsVersionInfo'),
          reason:
              'Class name should use project-level prefix "tomTools" → TomToolsVersionInfo',
        );

        // Should contain version from pubspec.yaml
        final hasVersion = content.contains(
          "static const String version = '1.0.0'",
        );
        log.expectation("version = '1.0.0'", hasVersion);
        expect(content, contains("static const String version = '1.0.0'"));

        // Should contain GENERATED header
        log.expectation(
          'GENERATED header',
          content.contains('GENERATED FILE - DO NOT EDIT'),
        );
        expect(content, contains('GENERATED FILE - DO NOT EDIT'));

        // Should contain git commit
        log.expectation(
          'gitCommit field',
          content.contains('static const String gitCommit'),
        );
        expect(content, contains('static const String gitCommit'));

        // Should contain build number
        log.expectation(
          'buildNumber field',
          content.contains('static const int buildNumber'),
        );
        expect(content, contains('static const int buildNumber'));

        // Should contain Dart SDK version
        log.expectation(
          'dartSdkVersion field',
          content.contains('static const String dartSdkVersion'),
        );
        expect(content, contains('static const String dartSdkVersion'));
      },
    );

    // Bug #12 FIXED: --no-git now correctly overrides project-level config.
    // The merge order is now: CLI > project > workspace > defaults.
    test('--no-git omits git commit field (bug #12 FIXED)', () async {
      log.start(
        'VER_GIT01',
        '--no-git overrides project config (bug #12 fixed)',
      );
      await ws.installFixture('versioner');

      final result = await ws.runTool('versioner', [
        '--project',
        targetProject,
        '--no-git',
      ]);
      log.capture('versioner --project _build --no-git', result);

      log.expectation('exit code 0', result.exitCode == 0);
      expect(result.exitCode, 0);

      final content = File(
        p.join(ws.workspaceRoot, versionFileRelative),
      ).readAsStringSync();

      // Bug #12 FIXED: CLI --no-git should override project config.
      // gitCommit field should be empty string (not absent, but empty).
      expect(
        content,
        contains("gitCommit = ''"),
        reason: 'Bug #12 fixed: --no-git should produce empty gitCommit',
      );
      log.expectation('gitCommit is empty', content.contains("gitCommit = ''"));

      // Version and build number should always be present
      log.expectation(
        'version field present',
        content.contains('static const String version'),
      );
      expect(content, contains('static const String version'));
      log.expectation(
        'buildNumber field present',
        content.contains('static const int buildNumber'),
      );
      expect(content, contains('static const int buildNumber'));
    });

    test('--list shows _build as a versioner project', () async {
      log.start('VER_LST01', '--list shows _build as a versioner project');
      await ws.installFixture('versioner');

      final result = await ws.runTool('versioner', [
        '--project',
        targetProject,
        '--list',
      ]);
      log.capture('versioner --project _build --list', result);

      log.expectation('exit code 0', result.exitCode == 0);
      expect(result.exitCode, 0);
      final hasBuild = (result.stdout as String).contains('_build');
      log.expectation('_build in output', hasBuild);
      expect(result.stdout as String, contains('_build'));
    });

    test(
      '--dump-config displays versioner config from buildkit.yaml',
      () async {
        log.start('VER_SHW01', '--dump-config displays versioner config');
        await ws.installFixture('versioner');

        final result = await ws.runTool('versioner', [
          '--project',
          targetProject,
          '--dump-config',
        ]);
        log.capture('versioner --project _build --dump-config', result);

        log.expectation('exit code 0', result.exitCode == 0);
        expect(result.exitCode, 0);

        final stdout = result.stdout as String;
        log.expectation(
          'contains variable-prefix',
          stdout.contains('variable-prefix'),
        );
        expect(stdout, contains('variable-prefix'));
        log.expectation('contains tomTools', stdout.contains('tomTools'));
        expect(stdout, contains('tomTools'));
      },
    );

    test('--version overrides pubspec version', () async {
      log.start('VER_OVR01', '--version overrides pubspec version');
      await ws.installFixture('versioner');

      final result = await ws.runTool('versioner', [
        '--project',
        targetProject,
        '--version',
        '9.9.9',
      ]);
      log.capture('versioner --project _build --version 9.9.9', result);

      log.expectation('exit code 0', result.exitCode == 0);
      expect(result.exitCode, 0);

      final content = File(
        p.join(ws.workspaceRoot, versionFileRelative),
      ).readAsStringSync();

      final hasOverride = content.contains(
        "static const String version = '9.9.9'",
      );
      log.expectation("version = '9.9.9'", hasOverride);
      expect(
        content,
        contains("static const String version = '9.9.9'"),
        reason: 'Should use overridden version 9.9.9',
      );
    });

    // Bug #12 FIXED: --variable-prefix now correctly overrides project config.
    test('--variable-prefix overrides project config (bug #12 FIXED)', () async {
      log.start(
        'VER_PFX01',
        '--variable-prefix overrides project config (bug #12 fixed)',
      );
      await ws.installFixture('versioner');

      final result = await ws.runTool('versioner', [
        '--project',
        targetProject,
        '--variable-prefix',
        'myCustom',
      ]);
      log.capture(
        'versioner --project _build --variable-prefix myCustom',
        result,
      );

      log.expectation('exit code 0', result.exitCode == 0);
      expect(result.exitCode, 0);

      final content = File(
        p.join(ws.workspaceRoot, versionFileRelative),
      ).readAsStringSync();

      // Bug #12 FIXED: CLI prefix "myCustom" should override project "tomTools"
      expect(
        content,
        contains('class MyCustomVersionInfo'),
        reason:
            'Bug #12 fixed: CLI --variable-prefix should override '
            'project config. Expected MyCustomVersionInfo',
      );
      log.expectation(
        'class is MyCustomVersionInfo',
        content.contains('class MyCustomVersionInfo'),
      );
    });

    test('build number increments on each run', () async {
      log.start('VER_BLD01', 'build number increments on each run');
      await ws.installFixture('versioner');

      // First run
      final result1 = await ws.runTool('versioner', [
        '--project',
        targetProject,
      ]);
      log.capture('versioner --project _build (run 1)', result1);
      final content1 = File(
        p.join(ws.workspaceRoot, versionFileRelative),
      ).readAsStringSync();
      final buildNum1 = _extractBuildNumber(content1);

      // Second run
      final result2 = await ws.runTool('versioner', [
        '--project',
        targetProject,
      ]);
      log.capture('versioner --project _build (run 2)', result2);
      final content2 = File(
        p.join(ws.workspaceRoot, versionFileRelative),
      ).readAsStringSync();
      final buildNum2 = _extractBuildNumber(content2);

      log.expectation(
        'build# run1=$buildNum1, run2=$buildNum2, diff=${buildNum2 - buildNum1}',
        buildNum2 == buildNum1 + 1,
      );
      expect(
        buildNum2,
        buildNum1 + 1,
        reason: 'Build number should increment on each run',
      );
    });
  });
}

/// Extract the build number from generated version.versioner.dart content.
int _extractBuildNumber(String content) {
  final match = RegExp(
    r'static const int buildNumber = (\d+);',
  ).firstMatch(content);
  if (match == null) {
    throw StateError('Could not find buildNumber in generated content');
  }
  return int.parse(match.group(1)!);
}
