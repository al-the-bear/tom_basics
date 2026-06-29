/// Integration tests for config merge precedence.
///
/// Tests that the config hierarchy (workspace defaults → project config →
/// CLI args) works correctly across tools.
///
/// Test IDs: CFG_DEF01, CFG_OVR01, CFG_MRG01
/// Note: Bug #12 is fixed — CLI args now correctly override project config.
@TestOn('!browser')
@Timeout(Duration(seconds: 120))
library;

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
    print('║          Config Merge Integration Tests              ║');
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
    print('  ── Config Merge Tests: Tear-down ──');
    await ws.verifyHeadRefs();
    // Symmetric with requireCleanWorkspace's deprovision at suite start:
    // remove the test-provisioned `_build` so the tree is clean post-run.
    await ws.deprovisionBuildProject();
    print('  ── Config Merge Tests: Complete ──');
  });

  // ----------- Helpers ----------- //

  /// Read the generated version.versioner.dart file content.
  String readVersionFile() {
    final versionFile =
        p.join(ws.workspaceRoot, '_build', 'lib', 'src', 'version.versioner.dart');
    return File(versionFile).readAsStringSync();
  }

  // ----------- Tests ----------- //

  group('config merge precedence', () {
    test('workspace defaults apply when project has no override', () async {
      log.start('CFG_DEF01', 'workspace defaults apply');

      // The exclusion fixture sets workspace-level versioner prefix to
      // 'testDefault'. The versioner is opt-in per project: it only runs where
      // the project's own buildkit.yaml declares a `versioner:` section — the
      // workspace master provides defaults but does not version every project
      // (see VersionerExecutor: "skipped (no versioner config)"). So we write a
      // buildkit.yaml WITH an EMPTY versioner section (opt-in, no
      // variable-prefix override): the project participates, supplies no
      // override, and the workspace default 'testDefault' should apply.
      final buildConfig =
          p.join(ws.workspaceRoot, '_build', 'buildkit.yaml');
      File(buildConfig).writeAsStringSync(
        '# Test fixture: empty versioner section (opt-in, no override)\n'
        'versioner:\n'
        'cleanup:\n'
        "  - '**/version.versioner.dart'\n",
      );
      print('    📝 Wrote _build/buildkit.yaml with empty versioner section');

      final result =
          await ws.runTool('versioner', ['--project', '_build']);
      log.capture('versioner without project versioner config', result);

      expect(result.exitCode, equals(0));

      // With no project override, workspace default prefix 'testDefault'
      // should be used, producing class TestDefaultVersionInfo
      final versionContent = readVersionFile();
      final usesWorkspaceDefault =
          versionContent.contains('TestDefaultVersionInfo') ||
              versionContent.contains('testDefault');
      expect(usesWorkspaceDefault, isTrue,
          reason: 'Without project config, workspace default prefix '
              '"testDefault" should apply. Got: '
              '${versionContent.substring(0, versionContent.length.clamp(0, 200))}');
      log.expectation('workspace default applied', usesWorkspaceDefault);
    });

    test('project config overrides workspace config', () async {
      log.start('CFG_OVR01', 'project config overrides workspace');

      // Exclusion fixture has workspace prefix 'testDefault'.
      // Write a complete _build/buildkit.yaml with project prefix 'tomTools'.
      // Project should win over workspace.
      final buildConfig =
          p.join(ws.workspaceRoot, '_build', 'buildkit.yaml');
      File(buildConfig).writeAsStringSync(
        '# Test fixture: project override for versioner prefix\n'
        'versioner:\n'
        '  variable-prefix: tomTools\n'
        '\n'
        'cleanup:\n'
        "  - '**/version.versioner.dart'\n",
      );
      print('    📝 Wrote _build/buildkit.yaml with variable-prefix: tomTools');

      final result =
          await ws.runTool('versioner', ['--project', '_build']);
      log.capture('versioner with project override', result);

      expect(result.exitCode, equals(0));

      final versionContent = readVersionFile();
      // Project prefix 'tomTools' should produce TomToolsVersionInfo
      expect(versionContent, contains('TomToolsVersionInfo'),
          reason: 'Project config "tomTools" should override workspace '
              '"testDefault"');
      log.expectation('project prefix used',
          versionContent.contains('TomToolsVersionInfo'));
    });

    test('additive merge for list fields (protected-folders)', () async {
      log.start('CFG_MRG01', 'additive merge for list fields');

      // Test that project-level protected-folders MERGE with built-in set.
      // Built-in protected folders: {.git, .github, .vscode, .idea}
      // Project adds: 'custom_protected'
      // Effective set should be: {.git, .github, .vscode, .idea, custom_protected}
      final buildConfig =
          p.join(ws.workspaceRoot, '_build', 'buildkit.yaml');
      File(buildConfig).writeAsStringSync(
        '# Test fixture: cleanup with protected-folders\n'
        'cleanup:\n'
        "  cleanup:\n"
        "    - '**/*.g.dart'\n"
        '  protected-folders:\n'
        "    - 'custom_protected'\n",
      );
      print('    📝 Wrote _build/buildkit.yaml with protected-folders');

      // Create file in project-level custom protected folder
      final customDir = Directory(
          p.join(ws.workspaceRoot, '_build', 'custom_protected'));
      customDir.createSync(recursive: true);
      File(p.join(customDir.path, 'test.g.dart'))
          .writeAsStringSync('// custom protected');

      // Create file in built-in protected folder (.github)
      final githubDir = Directory(
          p.join(ws.workspaceRoot, '_build', '.github'));
      final githubDirExisted = githubDir.existsSync();
      githubDir.createSync(recursive: true);
      final githubFile = File(p.join(githubDir.path, 'test.g.dart'));
      githubFile.writeAsStringSync('// builtin protected');

      // Create unprotected file that SHOULD be deleted
      final unprotectedFile = File(
          p.join(ws.workspaceRoot, '_build', 'lib', 'test_unprotected.g.dart'));
      unprotectedFile.writeAsStringSync('// should be deleted');

      final result =
          await ws.runTool('cleanup', ['--project', '_build']);
      log.capture('cleanup with merged protected-folders', result);

      expect(result.exitCode, equals(0));

      // Custom protected folder should survive (project additive merge)
      final customSurvived = File(
              p.join(customDir.path, 'test.g.dart'))
          .existsSync();
      // Built-in .github should survive (always protected)
      final githubSurvived = githubFile.existsSync();
      // Unprotected file should be deleted
      final unprotectedDeleted = !unprotectedFile.existsSync();

      expect(customSurvived, isTrue,
          reason: 'Project custom protected folder should survive cleanup');
      expect(githubSurvived, isTrue,
          reason: 'Built-in .github folder should survive cleanup');
      expect(unprotectedDeleted, isTrue,
          reason: 'Unprotected file should be deleted');

      log.expectation('custom protected survived', customSurvived);
      log.expectation('.github protected survived', githubSurvived);
      log.expectation('unprotected deleted', unprotectedDeleted);

      // Clean up untracked directories and files
      if (customDir.existsSync()) customDir.deleteSync(recursive: true);
      if (githubFile.existsSync()) githubFile.deleteSync();
      if (!githubDirExisted && githubDir.existsSync() &&
          githubDir.listSync().isEmpty) {
        githubDir.deleteSync();
      }
    });

    test('CLI args override both project and workspace config', () async {
      log.start('CFG_CLI01', 'CLI args override project config');

      // Exclusion fixture: workspace prefix 'testDefault'.
      // _build project: prefix 'tomTools'.
      // CLI: --variable-prefix myCustom → should WIN over both.
      final result = await ws.runTool('versioner', [
        '--project', '_build',
        '--variable-prefix', 'myCustom',
      ]);
      log.capture('versioner with --variable-prefix myCustom', result);

      expect(result.exitCode, equals(0));

      final versionContent = readVersionFile();
      // CLI prefix 'myCustom' should produce MyCustomVersionInfo
      expect(versionContent, contains('MyCustomVersionInfo'),
          reason: 'CLI --variable-prefix "myCustom" should override '
              'project "tomTools" and workspace "testDefault". '
              'Got: ${versionContent.substring(0, versionContent.length.clamp(0, 200))}');
      log.expectation('CLI prefix used',
          versionContent.contains('MyCustomVersionInfo'));
    });
  });
}
