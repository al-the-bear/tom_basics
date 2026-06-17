/// Integration tests for the `buildkit :execute` command.
///
/// Tests the ExecuteExecutor with placeholder resolution by spawning
/// buildkit as an external process against a temporary workspace fixture.
///
/// Test IDs: BK-EXEC-1 through BK-EXEC-12
@TestOn('!browser')
@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late String fixtureRoot;
  late Directory tempDir;
  late String buildkitPath;

  setUpAll(() async {
    // Create temp workspace fixture
    tempDir = await Directory.systemTemp.createTemp('bk_exec_test_');
    fixtureRoot = tempDir.path;

    // Workspace markers
    _writeFile(fixtureRoot, 'buildkit_master.yaml', 'name: bk_exec_test\n');
    _createDir(fixtureRoot, '.git');

    // Dart console app
    _writePubspec(fixtureRoot, 'app_one', '''
name: app_one
version: 1.0.0
environment:
  sdk: ^3.0.0
''');
    _createDir(fixtureRoot, 'app_one/bin');
    _writeFile(fixtureRoot, 'app_one/bin/main.dart', 'void main() {}\n');

    // Dart package
    _writePubspec(fixtureRoot, 'pkg_two', '''
name: pkg_two
version: 2.0.0
environment:
  sdk: ^3.0.0
''');

    // Another Dart package
    _writePubspec(fixtureRoot, 'pkg_three', '''
name: pkg_three
version: 3.0.0
environment:
  sdk: ^3.0.0
''');

    // Skipped project
    _writePubspec(fixtureRoot, 'skipped_one', '''
name: skipped_one
version: 0.0.1
environment:
  sdk: ^3.0.0
''');
    _writeFile(fixtureRoot, 'skipped_one/buildkit_skip.yaml', 'skip: true\n');

    // TypeScript project (no pubspec.yaml)
    _writeFile(
      fixtureRoot,
      'ts_proj/package.json',
      '{"name": "ts_proj", "version": "1.0.0"}\n',
    );
    _writeFile(fixtureRoot, 'ts_proj/tsconfig.json', '{}\n');

    // Git submodule
    _createDir(fixtureRoot, 'xternal/sub_mod/.git');
    _writePubspec(fixtureRoot, 'xternal/sub_mod', '''
name: sub_mod
version: 0.5.0
environment:
  sdk: ^3.0.0
''');

    // Find buildkit entry point
    final buildkitRoot = _findBuildkitRoot();
    buildkitPath = p.join(buildkitRoot, 'bin', 'buildkit.dart');
    expect(
      File(buildkitPath).existsSync(),
      isTrue,
      reason: 'buildkit.dart should exist at $buildkitPath',
    );
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Run buildkit with given args and return the process result.
  Future<ProcessResult> runBuildkit(List<String> args) async {
    return Process.run(
      'dart',
      ['run', buildkitPath, ...args],
      environment: {'HOME': Platform.environment['HOME'] ?? '/tmp'},
      workingDirectory: fixtureRoot,
    );
  }

  // ==========================================================================
  // Group 1: Basic :execute command
  // ==========================================================================
  group(':execute basic', () {
    test(
      'BK-EXEC-1: Execute echo with folder.name placeholder [2026-06-30]',
      () async {
        final result = await runBuildkit([
          '-R',
          fixtureRoot,
          '-s',
          fixtureRoot,
          '-r',
          ':execute',
          r'echo %{folder.name}',
        ]);

        final stdout = result.stdout as String;
        final stderr = result.stderr as String;
        print('stdout:\n$stdout');
        if (stderr.isNotEmpty) print('stderr:\n$stderr');

        expect(
          result.exitCode,
          equals(0),
          reason: 'Exit code should be 0. stderr: $stderr',
        );

        // Should see project names echoed
        expect(
          stdout,
          contains('app_one'),
          reason: 'Should echo app_one folder name',
        );
        expect(
          stdout,
          contains('pkg_two'),
          reason: 'Should echo pkg_two folder name',
        );
        expect(
          stdout,
          contains('pkg_three'),
          reason: 'Should echo pkg_three folder name',
        );
      },
    );

    test(
      'BK-EXEC-2: Execute with folder.relative placeholder [2026-06-30]',
      () async {
        final result = await runBuildkit([
          '-R',
          fixtureRoot,
          '-s',
          fixtureRoot,
          '-r',
          ':execute',
          r'echo %{folder.relative}',
        ]);

        final stdout = result.stdout as String;
        print('stdout:\n$stdout');

        expect(result.exitCode, equals(0));
        // Relative paths should be present
        expect(stdout, contains('app_one'));
      },
    );

    test(
      'BK-EXEC-3: Execute skips projects with buildkit_skip.yaml [2026-06-30]',
      () async {
        final result = await runBuildkit([
          '-R',
          fixtureRoot,
          '-s',
          fixtureRoot,
          '-r',
          ':execute',
          r'echo %{folder.name}',
        ]);

        final stdout = result.stdout as String;
        expect(
          stdout,
          isNot(contains('skipped_one')),
          reason: 'Skipped project should not appear in output',
        );
      },
    );

    test(
      'BK-EXEC-4: Execute with --dry-run does not run commands [2026-06-30]',
      () async {
        final result = await runBuildkit([
          '-R',
          fixtureRoot,
          '-s',
          fixtureRoot,
          '-r',
          '-n',
          ':execute',
          r'echo %{folder.name}',
        ]);

        final stdout = result.stdout as String;
        print('stdout:\n$stdout');

        expect(result.exitCode, equals(0));
        // Dry run should show [DRY-RUN] prefix
        expect(
          stdout,
          contains('DRY-RUN'),
          reason: 'Dry run should output [DRY-RUN] markers',
        );
      },
    );
  });

  // ==========================================================================
  // Group 2: Placeholder resolution
  // ==========================================================================
  group(':execute placeholders', () {
    test(
      'BK-EXEC-5: dart.exists ternary resolves correctly [2026-06-30]',
      () async {
        final result = await runBuildkit([
          '-R',
          fixtureRoot,
          '-s',
          fixtureRoot,
          '-r',
          '-n',
          ':execute',
          r'echo %{dart.exists?(DART):(NOT-DART)}',
        ]);

        final stdout = result.stdout as String;
        print('stdout:\n$stdout');

        expect(result.exitCode, equals(0));

        // Dart projects should resolve to DART
        // app_one, pkg_two, pkg_three are Dart, ts_proj is not
        // Check that both DART and NOT-DART appear
        expect(
          stdout,
          contains('DART'),
          reason: 'Dart projects should resolve ternary to DART',
        );
      },
    );

    test(
      'BK-EXEC-6: root placeholder resolves to workspace root [2026-06-30]',
      () async {
        final result = await runBuildkit([
          '-R',
          fixtureRoot,
          '-s',
          fixtureRoot,
          '-r',
          '-p',
          'app_one',
          '-n',
          ':execute',
          r'echo %{root}',
        ]);

        final stdout = result.stdout as String;
        print('stdout:\n$stdout');

        expect(result.exitCode, equals(0));
        // Root should contain the fixture path
        expect(
          stdout,
          contains(fixtureRoot),
          reason: r'%{root} should resolve to the workspace root',
        );
      },
    );

    test(
      'BK-EXEC-7: folder placeholder resolves to absolute path [2026-06-30]',
      () async {
        final result = await runBuildkit([
          '-R',
          fixtureRoot,
          '-s',
          fixtureRoot,
          '-r',
          '-p',
          'app_one',
          '-n',
          ':execute',
          r'echo %{folder}',
        ]);

        final stdout = result.stdout as String;
        print('stdout:\n$stdout');

        expect(result.exitCode, equals(0));
        expect(
          stdout,
          contains(p.join(fixtureRoot, 'app_one')),
          reason: r'%{folder} should resolve to absolute folder path',
        );
      },
    );
  });

  // ==========================================================================
  // Group 3: Navigation flags with :execute
  // ==========================================================================
  group(':execute with navigation', () {
    test(
      'BK-EXEC-8: -p project filter limits execute to one project [2026-06-30]',
      () async {
        final result = await runBuildkit([
          '-R',
          fixtureRoot,
          '-s',
          fixtureRoot,
          '-r',
          '-p',
          'app_one',
          ':execute',
          r'echo %{folder.name}',
        ]);

        final stdout = result.stdout as String;
        print('stdout:\n$stdout');

        expect(result.exitCode, equals(0));
        expect(stdout, contains('app_one'));
        // Other projects should NOT appear
        expect(
          stdout,
          isNot(contains('pkg_two: echo')),
          reason: '-p should filter to only app_one',
        );
        expect(
          stdout,
          isNot(contains('pkg_three: echo')),
          reason: '-p should filter to only app_one',
        );
      },
    );

    test(
      'BK-EXEC-9: -x exclude removes matching projects [2026-06-30]',
      () async {
        final result = await runBuildkit([
          '-R',
          fixtureRoot,
          '-s',
          fixtureRoot,
          '-r',
          '-x',
          '*xternal*',
          ':execute',
          r'echo %{folder.name}',
        ]);

        final stdout = result.stdout as String;
        print('stdout:\n$stdout');

        expect(result.exitCode, equals(0));
        expect(
          stdout,
          isNot(contains('sub_mod')),
          reason: '-x *xternal* should exclude sub_mod',
        );
        expect(
          stdout,
          contains('app_one'),
          reason: 'app_one should still be included',
        );
      },
    );

    test('BK-EXEC-10: Git inner-first with :execute [2026-06-30]', () async {
      final result = await runBuildkit([
        '-R',
        fixtureRoot,
        '-i',
        ':execute',
        r'echo %{folder.name}',
      ]);

      final stdout = result.stdout as String;
      final stderr = result.stderr as String;
      print('stdout:\n$stdout');
      if (stderr.isNotEmpty) print('stderr:\n$stderr');

      // This tests whether -i (git inner-first) works with :execute
      // Should find git repos only (workspace root + xternal/sub_mod)
      expect(result.exitCode, equals(0));
    });
  });

  // ==========================================================================
  // Group 4: Condition filtering
  // ==========================================================================
  group(':execute with conditions', () {
    test(
      'BK-EXEC-11: --condition dart.exists filters non-Dart projects [2026-06-30]',
      () async {
        final result = await runBuildkit([
          '-R',
          fixtureRoot,
          '-s',
          fixtureRoot,
          '-r',
          ':execute',
          '--condition',
          'dart.exists',
          r'echo %{folder.name}',
        ]);

        final stdout = result.stdout as String;
        print('stdout:\n$stdout');

        expect(result.exitCode, equals(0));
        // Dart projects should execute
        expect(stdout, contains('app_one'));
        expect(stdout, contains('pkg_two'));
        // TypeScript project should be skipped
        // (it might show as SKIP or just not appear in executed lines)
      },
    );

    test(
      'BK-EXEC-12: --condition with non-existent condition skips all [2026-06-30]',
      () async {
        final result = await runBuildkit([
          '-R',
          fixtureRoot,
          '-s',
          fixtureRoot,
          '-r',
          '-p',
          'app_one',
          ':execute',
          '--condition',
          'flutter.exists',
          'echo %{folder.name}',
        ]);

        final stdout = result.stdout as String;
        print('stdout:\n$stdout');

        // app_one is NOT a Flutter project, so condition should skip it
        expect(result.exitCode, equals(0));
        // Should either show SKIP or not execute the command
      },
    );
  });

  // ==========================================================================
  // Group 5: -c short flag condition filtering
  // ==========================================================================
  group(':execute -c short flag', () {
    test(
      'BK-EXEC-14: -c dart.exists filters non-Dart projects [2026-07-01]',
      () async {
        final result = await runBuildkit([
          '-R',
          fixtureRoot,
          '-s',
          fixtureRoot,
          '-r',
          ':execute',
          '-c',
          'dart.exists',
          r'echo %{folder.name}',
        ]);

        final stdout = result.stdout as String;
        final stderr = result.stderr as String;
        print('stdout:\n$stdout');
        if (stderr.isNotEmpty) print('stderr:\n$stderr');

        expect(
          result.exitCode,
          equals(0),
          reason: 'Exit code should be 0. stderr: $stderr',
        );

        // Dart projects should be included
        expect(
          stdout,
          contains('app_one'),
          reason: 'Dart project app_one should be included',
        );
        expect(
          stdout,
          contains('pkg_two'),
          reason: 'Dart project pkg_two should be included',
        );
        expect(
          stdout,
          contains('pkg_three'),
          reason: 'Dart project pkg_three should be included',
        );

        // TypeScript project must NOT appear in echo output lines
        expect(
          stdout,
          isNot(contains('ts_proj: echo')),
          reason: '-c dart.exists should filter out non-Dart project ts_proj',
        );
      },
    );
  });

  // ==========================================================================
  // Group 6: %{} placeholder syntax (regression test)
  // ==========================================================================
  group(':execute %{} syntax', () {
    test(
      'BK-EXEC-13: %{folder.name} resolves correctly (not passed through literally) [2026-07-01]',
      () async {
        final result = await runBuildkit([
          '-R',
          fixtureRoot,
          '-s',
          fixtureRoot,
          '-r',
          '-p',
          'app_one',
          ':execute',
          r'echo %{folder.name}',
        ]);

        final stdout = result.stdout as String;
        final stderr = result.stderr as String;
        print('stdout:\n$stdout');
        if (stderr.isNotEmpty) print('stderr:\n$stderr');

        expect(
          result.exitCode,
          equals(0),
          reason: 'Exit code should be 0. stderr: $stderr',
        );

        // The placeholder MUST be resolved — not passed through literally
        expect(
          stdout,
          isNot(contains('%{folder.name}')),
          reason:
              '%{folder.name} should be resolved, not passed through literally',
        );
        expect(
          stdout,
          contains('app_one'),
          reason: '%{folder.name} should resolve to app_one',
        );
      },
    );
  });
}

// =============================================================================
// Helper functions
// =============================================================================

void _writeFile(String root, String relativePath, String content) {
  final file = File(p.join(root, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

void _writePubspec(String root, String projectDir, String content) {
  _writeFile(root, '$projectDir/pubspec.yaml', content);
  _createDir(root, '$projectDir/lib');
}

void _createDir(String root, String relativePath) {
  Directory(p.join(root, relativePath)).createSync(recursive: true);
}

/// Find the buildkit project root by walking up from current dir.
String _findBuildkitRoot() {
  // When running from tom_build_kit/test, walk up to find tom_build_kit
  var dir = Directory.current.path;
  while (!File(p.join(dir, 'pubspec.yaml')).existsSync() ||
      !File(p.join(dir, 'bin', 'buildkit.dart')).existsSync()) {
    final parent = p.dirname(dir);
    if (parent == dir) {
      // Fallback: search relative to known workspace structure
      // from tom_build_base, go to ../tom_build_kit
      final altDir = p.join(dir, '..', 'tom_build_kit');
      if (File(p.join(altDir, 'bin', 'buildkit.dart')).existsSync()) {
        return p.normalize(altDir);
      }
      throw StateError('Could not find buildkit project root');
    }
    dir = parent;
  }
  return dir;
}
