/// Integration tests for the compiler tool.
///
/// Target project: `_build` (has `compiler:` config with compiles + postcompile).
/// All tests use `--dry-run` or read-only flags to avoid actual compilation.
///
/// Test IDs: CMP_LST01, CMP_SHW01, CMP_DRY01, CMP_TGT01, CMP_PLC01, CMP_PHS01
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
    print('║          Compiler Integration Tests                  ║');
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
    print('  ── Compiler Tests: Tear-down ──');
    await ws.verifyHeadRefs();
    // Symmetric with requireCleanWorkspace's deprovision at suite start:
    // remove the test-provisioned `_build` so the tree is clean post-run.
    await ws.deprovisionBuildProject();
    print('  ── Compiler Tests: Complete ──');
  });

  // ----------- Tests ----------- //

  group('compiler', () {
    test('--list shows compiler-configured projects', () async {
      log.start('CMP_LST01', '--list shows compiler-configured projects');
      final result = await ws.runTool('compiler', [
        '--scan',
        '.',
        '--recursive',
        '--list',
      ]);
      log.capture('compiler --scan . -r --list', result);

      final stdout = (result.stdout as String);
      expect(result.exitCode, equals(0));
      // _build has compiler config → should be listed
      expect(
        stdout,
        contains('_build'),
        reason: '_build has compiler config, should appear in --list',
      );
      log.expectation('_build listed', stdout.contains('_build'));
    });

    test('--dump-config displays compiler config', () async {
      log.start('CMP_SHW01', '--dump-config displays compiler config');
      final result = await ws.runTool('compiler', [
        '--project',
        '_build',
        '--dump-config',
      ]);
      log.capture('compiler --project _build --dump-config', result);

      final stdout = (result.stdout as String);
      expect(result.exitCode, equals(0));
      // Should show compile sections (files, targets, platforms)
      final hasCompilerInfo =
          stdout.contains('compiles') ||
          stdout.contains('commandline') ||
          stdout.contains('compiler');
      expect(
        hasCompilerInfo,
        isTrue,
        reason: 'Should display compiler configuration details',
      );
      log.expectation('shows compiler info', hasCompilerInfo);
    });

    test('--dry-run shows commands without executing', () async {
      log.start('CMP_DRY01', '--dry-run shows planned commands');
      final result = await ws.runTool('compiler', [
        '--project',
        '_build',
        '--dry-run',
      ]);
      log.capture('compiler --project _build --dry-run', result);

      final stdout = (result.stdout as String);
      expect(result.exitCode, equals(0));
      // Dry-run should produce [DRY RUN] markers
      expect(
        stdout.toLowerCase(),
        contains('dry run'),
        reason: 'Dry-run should show planned commands with DRY RUN marker',
      );

      // No actual binaries should be produced — just verify the marker
      log.expectation(
        'has DRY RUN output',
        stdout.toLowerCase().contains('dry run'),
      );
    });

    test('--targets filters compilation to specific platforms', () async {
      log.start('CMP_TGT01', '--targets filters platforms');
      // Request only linux-x64 target
      final result = await ws.runTool('compiler', [
        '--project',
        '_build',
        '--dry-run',
        '--targets',
        'linux-x64',
      ]);
      log.capture('compiler --dry-run --targets linux-x64', result);

      final stdout = (result.stdout as String);
      expect(result.exitCode, equals(0));

      // With --targets linux-x64, only linux-x64 compilations should appear.
      // Other targets (darwin-arm64, linux-arm64, linux-armhf) should be absent
      // from the compile output. (Postcompile phases use current-platform and
      // may contain darwin-arm64, so we exclude postcompile lines.)
      final lines = stdout.split('\n');
      // Only check lines that are compile operations, not postcompile
      final compileLines = lines
          .where(
            (l) =>
                l.toLowerCase().contains('dry run') &&
                l.toLowerCase().contains('compile') &&
                !l.toLowerCase().contains('postcompile') &&
                !l.toLowerCase().contains('precompile'),
          )
          .toList();

      if (compileLines.isNotEmpty) {
        // Verify compile lines target linux-x64 only
        final hasDarwinTarget = compileLines.any(
          (l) => l.contains('(darwin-arm64)') || l.contains('target-os=macos'),
        );
        expect(
          hasDarwinTarget,
          isFalse,
          reason:
              'With --targets linux-x64, compile lines should not '
              'target darwin-arm64. Lines: ${compileLines.join('\n')}',
        );
        log.expectation('no darwin-arm64 target in compiles', !hasDarwinTarget);
      } else {
        // On platforms where no compile section matches, no output
        print('    ℹ️  No compile dry-run lines (platform filter may apply)');
      }
      log.expectation('exit code 0', result.exitCode == 0);
    });

    test('placeholder resolution in commandlines', () async {
      log.start('CMP_PLC01', 'placeholder resolution');
      final result = await ws.runTool('compiler', [
        '--project',
        '_build',
        '--dry-run',
      ]);
      log.capture('compiler --dry-run (placeholder check)', result);

      final stdout = (result.stdout as String);
      expect(result.exitCode, equals(0));

      // Check dry-run lines for unresolved placeholders
      final dryRunLines = stdout
          .split('\n')
          .where((l) => l.toLowerCase().contains('dry run'));

      for (final line in dryRunLines) {
        // Common placeholders that should be resolved:
        expect(
          line,
          isNot(contains('\${file}')),
          reason: 'Placeholder \${file} should be resolved in: $line',
        );
        expect(
          line,
          isNot(contains('\${target-os}')),
          reason: 'Placeholder \${target-os} should be resolved in: $line',
        );
        expect(
          line,
          isNot(contains('\${target-platform}')),
          reason: 'Placeholder \${target-platform} should be resolved',
        );
        expect(
          line,
          isNot(contains('\${target-platform-vs}')),
          reason: 'Placeholder \${target-platform-vs} should be resolved',
        );
        expect(
          line,
          isNot(contains('%{dart-target-os}')),
          reason: 'Placeholder %{dart-target-os} should be resolved in: $line',
        );
        expect(
          line,
          isNot(contains('%{dart-target-arch}')),
          reason:
              'Placeholder %{dart-target-arch} should be resolved in: $line',
        );

        if (line.contains('dart compile exe') &&
            (line.contains('--target-os=') ||
                line.contains('--target-platform'))) {
          expect(
            line,
            contains('--target-arch='),
            reason:
                'Compiler commands targeting a specific platform must include '
                '--target-arch to avoid host-arch fallback: $line',
          );
        }
      }
      log.expectation('no unresolved placeholders', true);
    });

    test('compile failure yields non-zero exit and names the project', () async {
      log.start(
        'CMP_FAIL01',
        'failed compile -> non-zero exit + named project',
      );
      // Overlay a compiler config on _build whose only compile section runs
      // `shell exit 1` — a deterministic, cross-platform compilation failure.
      await ws.installFixture('compile_fail');

      // No --dry-run: the failing command must actually run.
      final result = await ws.runTool('compiler', ['--project', '_build']);
      log.capture('compiler --project _build (failing config)', result);

      final stdout = (result.stdout as String);

      // Regression guard for tool_run_analysis §b.5: a real compile failure
      // must produce a non-zero exit code (CI relies on it).
      expect(
        result.exitCode,
        isNot(0),
        reason: 'A failed compile must produce a non-zero exit code',
      );
      log.expectation('non-zero exit', result.exitCode != 0);

      // The failing project must be named so the operator knows what broke.
      expect(
        stdout,
        contains('_build'),
        reason: 'The failing project must be named in the error output',
      );
      log.expectation('_build named in errors', stdout.contains('_build'));

      // The run must report errors, not "Done. No errors."
      expect(
        stdout,
        isNot(contains('Done. No errors.')),
        reason: 'A failing run must not report "Done. No errors."',
      );
      log.expectation(
        'no false success message',
        !stdout.contains('Done. No errors.'),
      );
    });

    test('postcompile phase appears in dry-run', () async {
      log.start('CMP_PHS01', 'pre/postcompile phases in dry-run');
      final result = await ws.runTool('compiler', [
        '--project',
        '_build',
        '--dry-run',
      ]);
      log.capture('compiler --dry-run (phases check)', result);

      final stdout = (result.stdout as String);
      expect(result.exitCode, equals(0));

      // _build has postcompile with chmod command (platforms: [macos, linux]).
      // On macOS (darwin-arm64), the macos platform filter should match.
      final hasPostcompile =
          stdout.toLowerCase().contains('postcompile') ||
          stdout.contains('chmod');
      if (hasPostcompile) {
        log.expectation('postcompile phase present', true);
      } else {
        // If platform doesn't match, postcompile is skipped — still valid
        print('    ℹ️  Postcompile not shown (platform filter may not match)');
        // At minimum, compile phase should be present
        expect(
          stdout.toLowerCase(),
          contains('dry run'),
          reason: 'At least some dry-run output should be present',
        );
        log.expectation('compile phase present', true);
      }
    });
  });
}
