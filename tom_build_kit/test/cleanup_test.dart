@TestOn('!browser')
@Timeout(Duration(seconds: 120))
library; // ignore: unnecessary_library_name

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/test_workspace.dart';

/// Integration tests for the cleanup tool.
///
/// Target project: `_build` (has `cleanup: ['**/version.versioner.dart']` in its
/// buildkit.yaml, and `_build/lib/src/version.versioner.dart` exists as a
/// tracked file that gets restored by `git checkout -- .`).
void main() {
  late TestWorkspace ws;
  late TestLogger log;

  /// Temporary untracked files created during tests (cleaned up in tearDown).
  final tempFiles = <String>[];

  /// Temporary directories created during tests (cleaned up in tearDown).
  final tempDirs = <String>{};

  setUpAll(() async {
    ws = TestWorkspace();
    print('');
    print('╔══════════════════════════════════════════════════════╗');
    print('║          Cleanup Integration Tests                   ║');
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

    // Remove any temporary untracked files created during the test
    if (tempFiles.isNotEmpty) {
      print('    🗑️  Cleaning up ${tempFiles.length} temporary file(s)...');
      for (final filePath in tempFiles) {
        final file = File(filePath);
        if (file.existsSync()) {
          final rel = p.relative(filePath, from: ws.workspaceRoot);
          file.deleteSync();
          print('       removed: $rel');
        }
      }
      tempFiles.clear();
    }

    // Remove empty temporary directories (deepest first)
    if (tempDirs.isNotEmpty) {
      final sorted = tempDirs.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final dirPath in sorted) {
        final dir = Directory(dirPath);
        if (dir.existsSync()) {
          try {
            // Delete if empty or if it's a test-created directory
            dir.deleteSync(recursive: true);
            final rel = p.relative(dirPath, from: ws.workspaceRoot);
            print('       removed dir: $rel');
          } catch (_) {
            // Ignore — directory might have other contents
          }
        }
      }
      tempDirs.clear();
    }

    // Revert all tracked file changes
    await ws.revertAll();
  });

  tearDownAll(() async {
    print('');
    print('  ── Cleanup Tests: Tear-down ──');
    await ws.verifyHeadRefs();
    // Symmetric with requireCleanWorkspace's deprovision at suite start:
    // remove the test-provisioned `_build` so the tree is clean post-run.
    await ws.deprovisionBuildProject();
    print('  ── Cleanup Tests: Complete ──');
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Parse `--list` output into project relative paths.
  List<String> parseListOutput(String stdout) {
    return stdout
        .split('\n')
        .where((line) => line.startsWith('  ') && line.trim().isNotEmpty)
        .map((line) => line.trim())
        .toList();
  }

  /// Create a temporary file and track it for cleanup in tearDown.
  String createTempFile(String relPath, {String content = '// temp'}) {
    final absPath = p.join(ws.workspaceRoot, relPath);
    final file = File(absPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    tempFiles.add(absPath);
    // Track parent directory if it's a test-created directory
    final parentPath = file.parent.path;
    if (p.basename(parentPath).startsWith('_test_')) {
      tempDirs.add(parentPath);
    }
    print('    📄 Created temp file: $relPath');
    return absPath;
  }

  /// Modify _build/buildkit.yaml with custom content.
  ///
  /// The original file is restored by `revertAll()` (git checkout -- .).
  void setBuildConfig(String yamlContent) {
    final configPath = p.join(ws.workspaceRoot, '_build', 'buildkit.yaml');
    File(configPath).writeAsStringSync(yamlContent);
    print('    📝 Modified _build/buildkit.yaml');
  }

  // ---------------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------------

  group('cleanup', () {
    test('--list shows cleanup-configured projects', () async {
      log.start('CLN_LST01', '--list shows cleanup-configured projects');
      final result = await ws.runTool('cleanup', [
        '--scan',
        '.',
        '--recursive',
        '--list',
      ]);
      log.capture('cleanup --scan . -r --list', result);

      final stdout = (result.stdout as String);
      expect(result.exitCode, equals(0));

      // _build has cleanup config, so it should be listed
      final projects = parseListOutput(stdout);
      final hasBuild = projects.any((proj) => proj.contains('_build'));
      expect(
        hasBuild,
        isTrue,
        reason: '_build has cleanup config and should be listed',
      );
      log.expectation('_build listed', hasBuild);
    });

    test('--dump-config displays cleanup config', () async {
      log.start('CLN_SHW01', '--dump-config displays cleanup config');
      final result = await ws.runTool('cleanup', [
        '--project',
        '_build',
        '--dump-config',
      ]);
      log.capture('cleanup --project _build --dump-config', result);

      final stdout = (result.stdout as String);
      expect(result.exitCode, equals(0));
      // Should show the cleanup glob pattern from _build/buildkit.yaml
      expect(
        stdout,
        contains('version.versioner.dart'),
        reason: 'Should display the cleanup glob pattern',
      );
      log.expectation(
        'shows version.versioner.dart pattern',
        stdout.contains('version.versioner.dart'),
      );
    });

    test('deletes files matching glob patterns', () async {
      log.start('CLN_DEL01', 'deletes files matching patterns');

      final versionFile = p.join(
        ws.workspaceRoot,
        '_build',
        'lib',
        'src',
        'version.versioner.dart',
      );
      expect(
        File(versionFile).existsSync(),
        isTrue,
        reason: 'version.versioner.dart should exist before cleanup',
      );

      final result = await ws.runTool('cleanup', ['--project', '_build']);
      log.capture('cleanup --project _build', result);

      expect(result.exitCode, equals(0));
      expect(
        File(versionFile).existsSync(),
        isFalse,
        reason: 'version.versioner.dart should be deleted by cleanup',
      );
      log.expectation(
        'version.versioner.dart deleted',
        !File(versionFile).existsSync(),
      );
    });

    test('--dry-run lists files without deleting', () async {
      log.start('CLN_DRY01', '--dry-run lists without deleting');

      final versionFile = p.join(
        ws.workspaceRoot,
        '_build',
        'lib',
        'src',
        'version.versioner.dart',
      );
      expect(
        File(versionFile).existsSync(),
        isTrue,
        reason: 'version.versioner.dart should exist before dry-run',
      );

      final result = await ws.runTool('cleanup', [
        '--project',
        '_build',
        '--dry-run',
      ]);
      log.capture('cleanup --project _build --dry-run', result);

      expect(result.exitCode, equals(0));
      // File should still exist after dry-run
      expect(
        File(versionFile).existsSync(),
        isTrue,
        reason: 'version.versioner.dart should survive --dry-run',
      );
      // Output should mention the file
      final stdout = (result.stdout as String);
      expect(
        stdout,
        contains('version.versioner.dart'),
        reason: 'Dry-run should list version.versioner.dart',
      );
      log.expectation('file survives', File(versionFile).existsSync());
      log.expectation(
        'file listed in output',
        stdout.contains('version.versioner.dart'),
      );
    });

    test('excludes patterns prevent deletion', () async {
      log.start('CLN_EXC01', 'excludes prevent deletion');

      // Modify _build/buildkit.yaml: broad pattern with exclude for
      // version.versioner.dart — version.versioner.dart should survive, temp file should not.
      setBuildConfig('''
# Modified by integration test — CLN_EXC01
versioner:
  variable-prefix: tomTools

cleanup:
  - globs:
      - '**/*.g.dart'
    excludes:
      - '**/version.versioner.dart'
''');

      // Create a temp .g.dart file that SHOULD be deleted
      final tempFile = createTempFile(
        '_build/lib/src/test_temp.g.dart',
        content: '// This file should be deleted by cleanup',
      );

      final versionFile = p.join(
        ws.workspaceRoot,
        '_build',
        'lib',
        'src',
        'version.versioner.dart',
      );
      expect(File(versionFile).existsSync(), isTrue);
      expect(File(tempFile).existsSync(), isTrue);

      final result = await ws.runTool('cleanup', ['--project', '_build']);
      log.capture('cleanup with excludes', result);

      expect(result.exitCode, equals(0));
      // version.versioner.dart should survive (excluded)
      expect(
        File(versionFile).existsSync(),
        isTrue,
        reason: 'version.versioner.dart should be protected by exclude pattern',
      );
      // test_temp.g.dart should be deleted (matches glob, not excluded)
      expect(
        File(tempFile).existsSync(),
        isFalse,
        reason: 'test_temp.g.dart should be deleted (not excluded)',
      );

      // Remove from tracking since it was deleted by cleanup
      tempFiles.remove(tempFile);

      log.expectation(
        'version.versioner.dart survives',
        File(versionFile).existsSync(),
      );
      log.expectation('test_temp.g.dart deleted', !File(tempFile).existsSync());
    });

    test('protected folders are never touched', () async {
      log.start('CLN_PRO01', 'protected folders are never touched');

      // Use broad pattern, add 'src' as a protected folder.
      // Protected-folders uses basename matching on individual path
      // segments — so 'src' matches any path containing a '/src/' segment.
      // version.versioner.dart is under lib/src/, so it should survive.
      setBuildConfig('''
# Modified by integration test — CLN_PRO01
versioner:
  variable-prefix: tomTools

cleanup:
  cleanup:
    - '**/*.g.dart'
  protected-folders:
    - 'src'
''');

      final versionFile = p.join(
        ws.workspaceRoot,
        '_build',
        'lib',
        'src',
        'version.versioner.dart',
      );
      expect(File(versionFile).existsSync(), isTrue);

      // Create a .g.dart file OUTSIDE the protected src/ folder
      final tempFile = createTempFile(
        '_build/lib/test_unprotected.g.dart',
        content: '// Outside protected folder — should be deleted',
      );

      final result = await ws.runTool('cleanup', ['--project', '_build']);
      log.capture('cleanup with protected-folders', result);

      expect(result.exitCode, equals(0));
      // version.versioner.dart under lib/src/ (protected) should survive
      expect(
        File(versionFile).existsSync(),
        isTrue,
        reason:
            'version.versioner.dart in protected src/ folder should survive',
      );
      // temp file outside protected folder should be deleted
      expect(
        File(tempFile).existsSync(),
        isFalse,
        reason: 'File outside protected folder should be deleted',
      );

      tempFiles.remove(tempFile);

      log.expectation(
        'protected file survives',
        File(versionFile).existsSync(),
      );
      log.expectation('unprotected file deleted', !File(tempFile).existsSync());
    });

    test(
      'protected-folders with multi-segment paths (bug #17 FIXED)',
      () async {
        log.start('CLN_PRO02', 'protected-folders multi-segment path');
        // Bug #17 FIXED: _isInProtectedFolder() now uses Glob matching for
        // multi-segment entries containing '/'. Single-segment entries still
        // use fast path via p.split() + set lookup.
        //
        // Set 'lib/src' as a protected folder — files under lib/src/ should
        // survive cleanup.
        setBuildConfig('''
# Modified by integration test — CLN_PRO02
versioner:
  variable-prefix: tomTools

cleanup:
  cleanup:
    - '**/*.g.dart'
  protected-folders:
    - 'lib/src'
''');

        final versionFile = p.join(
          ws.workspaceRoot,
          '_build',
          'lib',
          'src',
          'version.versioner.dart',
        );
        expect(File(versionFile).existsSync(), isTrue);

        // Create a .g.dart file OUTSIDE lib/src/ (should be deleted)
        final tempFile = createTempFile(
          '_build/lib/test_unprotected.g.dart',
          content: '// Outside protected folder — should be deleted',
        );

        final result = await ws.runTool('cleanup', ['--project', '_build']);
        log.capture('cleanup with multi-segment protected-folders', result);

        expect(result.exitCode, equals(0));

        // Bug #17 FIXED: version.versioner.dart under lib/src/ should survive
        // because 'lib/src' is listed in protected-folders and Glob
        // matching now handles multi-segment paths correctly.
        expect(
          File(versionFile).existsSync(),
          isTrue,
          reason:
              'version.versioner.dart in protected lib/src/ folder should '
              'survive cleanup. Bug #17 fixed: multi-segment paths now '
              'handled via Glob matching in _isInProtectedFolder()',
        );

        // Unprotected file should be deleted
        expect(
          File(tempFile).existsSync(),
          isFalse,
          reason: 'File outside protected folder should be deleted',
        );

        tempFiles.remove(tempFile);

        log.expectation(
          'protected file survives',
          File(versionFile).existsSync(),
        );
        log.expectation(
          'unprotected file deleted',
          !File(tempFile).existsSync(),
        );
      },
    );

    test('safety limit triggers abort when too many files', () async {
      log.start('CLN_SAF01', 'safety limit triggers abort');

      // Use broad pattern with low --max-files
      setBuildConfig('''
# Modified by integration test — CLN_SAF01
versioner:
  variable-prefix: tomTools

cleanup:
  - '**/*.g.dart'
''');

      // Create more files than the safety limit
      for (var i = 0; i < 6; i++) {
        createTempFile(
          '_build/lib/src/_test_safe/file_$i.g.dart',
          content: '// Safety test file $i',
        );
      }

      final result = await ws.runTool('cleanup', [
        '--project',
        '_build',
        '--max-files',
        '3',
      ]);
      log.capture('cleanup --max-files 3 with 7+ files', result);

      // Should abort due to safety limit (7+ files > 3 limit)
      expect(
        result.exitCode,
        isNot(equals(0)),
        reason: 'Should abort when file count exceeds --max-files',
      );

      // All temp files should still exist (abort = no deletion)
      for (var i = 0; i < 6; i++) {
        final f = File(
          p.join(ws.workspaceRoot, '_build/lib/src/_test_safe/file_$i.g.dart'),
        );
        expect(
          f.existsSync(),
          isTrue,
          reason: 'File $i should survive safety abort',
        );
      }

      final stdout = (result.stdout as String);
      expect(
        stdout.toLowerCase(),
        contains('warning'),
        reason: 'Should print a warning about file count',
      );
      log.expectation('exit code non-zero', result.exitCode != 0);
      log.expectation('files survived', true);
    });

    test('--force skips safety limit', () async {
      log.start('CLN_SAF02', '--force skips safety limit');

      setBuildConfig('''
# Modified by integration test — CLN_SAF02
versioner:
  variable-prefix: tomTools

cleanup:
  - '**/*.g.dart'
''');

      // Create files that exceed the safety limit
      for (var i = 0; i < 6; i++) {
        createTempFile(
          '_build/lib/src/_test_force/file_$i.g.dart',
          content: '// Force test file $i',
        );
      }

      final result = await ws.runTool('cleanup', [
        '--project',
        '_build',
        '--max-files',
        '3',
        '--force',
      ]);
      log.capture('cleanup --max-files 3 --force', result);

      expect(result.exitCode, equals(0));

      // Files should be deleted (force overrides safety)
      var deletedCount = 0;
      for (var i = 0; i < 6; i++) {
        final f = File(
          p.join(ws.workspaceRoot, '_build/lib/src/_test_force/file_$i.g.dart'),
        );
        if (!f.existsSync()) deletedCount++;
      }
      expect(
        deletedCount,
        greaterThan(0),
        reason: 'Some files should be deleted with --force',
      );

      // Remove deleted files from tracking
      tempFiles.removeWhere((f) => !File(f).existsSync());

      log.expectation('files deleted', deletedCount > 0);
    });
  });
}
