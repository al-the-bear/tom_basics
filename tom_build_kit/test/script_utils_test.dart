/// Unit and integration tests for multi-line scripts and stdin piping.
///
/// Tests both the parsing utilities in script_utils.dart and the
/// end-to-end pipeline execution of multi-line shell scripts and
/// stdin-piped commands.
///
/// Test IDs: SCR_PRS01, SCR_PRS02, SCR_PRS03, SCR_PRS04, SCR_PRS05,
///           SCR_PRS06, SCR_MLN01, SCR_MLN02, SCR_STD01, SCR_STD02,
///           SCR_DRY01, SCR_DRY02
@TestOn('!browser')
@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_kit/src/script_utils.dart';

import 'helpers/test_workspace.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // Unit Tests — script_utils parsing functions
  // ═══════════════════════════════════════════════════════════════════════

  group('script_utils parsing', () {
    test('isMultiLineShellScript detects shell\\n prefix', () {
      // SCR_PRS01: Multi-line shell script detection
      expect(isMultiLineShellScript('shell\necho "hello"'), isTrue);
      expect(isMultiLineShellScript('shell\nline1\nline2\nline3'), isTrue);
      expect(isMultiLineShellScript('  shell\necho "hello"  '), isTrue);
    });

    test('isMultiLineShellScript rejects non-multiline', () {
      // SCR_PRS02: Single-line shell is NOT multi-line
      expect(isMultiLineShellScript('shell echo "hello"'), isFalse);
      expect(isMultiLineShellScript('versioner --list'), isFalse);
      expect(isMultiLineShellScript(''), isFalse);
    });

    test('extractScriptBody extracts content after shell\\n', () {
      // SCR_PRS03: Script body extraction
      expect(
        extractScriptBody('shell\necho "hello"\necho "world"'),
        equals('echo "hello"\necho "world"'),
      );
      expect(
        extractScriptBody('shell\nline1'),
        equals('line1'),
      );
    });

    test('isStdinCommand detects stdin prefix with newline', () {
      // SCR_PRS04: Stdin command detection
      expect(isStdinCommand('stdin cat\nhello'), isTrue);
      expect(isStdinCommand('stdin dcli\nimport "dart:io";'), isTrue);
      expect(isStdinCommand('  stdin cat\nhello  '), isTrue);
    });

    test('isStdinCommand rejects invalid formats', () {
      // SCR_PRS05: Invalid stdin commands
      expect(isStdinCommand('stdin cat'), isFalse); // no newline
      expect(isStdinCommand('shell echo'), isFalse); // wrong prefix
      expect(isStdinCommand(''), isFalse);
    });

    test('parseStdinCommand extracts command and content', () {
      // SCR_PRS06: Stdin parsing
      final result = parseStdinCommand('stdin cat\nhello\nworld');
      expect(result, isNotNull);
      expect(result!.command, equals('cat'));
      expect(result.stdinContent, equals('hello\nworld'));

      // With extra flags
      final result2 = parseStdinCommand('stdin dcli --verbose\nDart code');
      expect(result2, isNotNull);
      expect(result2!.command, equals('dcli --verbose'));
      expect(result2.stdinContent, equals('Dart code'));

      // Invalid: no content
      expect(parseStdinCommand('stdin cat'), isNull);

      // Invalid: empty command
      expect(parseStdinCommand('stdin \nhello'), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Integration Tests — pipeline execution of multi-line commands
  // ═══════════════════════════════════════════════════════════════════════

  group('multi-line pipeline execution', () {
    late TestWorkspace ws;
    late TestLogger log;

    setUpAll(() async {
      ws = TestWorkspace();
      print('');
      print('╔══════════════════════════════════════════════════════╗');
      print('║       Multi-Line Script Integration Tests            ║');
      print('╚══════════════════════════════════════════════════════╝');
      print('Workspace root:  ${ws.workspaceRoot}');
      print('Buildkit root:   ${ws.buildkitRoot}');
      await ws.requireCleanWorkspace();
      await ws.saveHeadRefs();
    });

    setUp(() async {
      log = TestLogger(ws);
      await ws.installFixture('pipeline');
    });

    tearDown(() async {
      log.finish();
      await ws.revertAll();
    });

    tearDownAll(() async {
      print('');
      print('  ── Multi-Line Script Tests: Tear-down ──');
      await ws.verifyHeadRefs();
      // Symmetric with requireCleanWorkspace's deprovision at suite start:
      // remove the test-provisioned `_build` so the tree is clean post-run.
      await ws.deprovisionBuildProject();
      print('  ── Multi-Line Script Tests: Complete ──');
    });

    test('multi-line shell script executes all lines', () async {
      log.start('SCR_MLN01',
          'multi-line shell script executes all lines');
      final result = await ws.runPipeline('test-multiline-shell', []);
      log.capture('buildkit test-multiline-shell', result);

      final stdout = result.stdout as String;
      expect(result.exitCode, equals(0),
          reason: 'Pipeline should succeed');
      expect(stdout, contains('multi-line-1'));
      expect(stdout, contains('multi-line-2'));
      expect(stdout, contains('multi-line-3'));
      log.expectation('all three echo lines present', true);
    });

    test('multi-line shell script in verbose mode', () async {
      log.start('SCR_MLN02',
          'multi-line shell script verbose output');
      // Global flags must come BEFORE the pipeline name
      final binPath = p.join(ws.buildkitRoot, 'bin', 'buildkit.dart');
      final result = await Process.run(
        'dart',
        ['run', binPath, '--verbose', 'test-multiline-shell'],
        workingDirectory: ws.workspaceRoot,
      );
      log.capture('buildkit --verbose test-multiline-shell', result);

      final stdout = result.stdout as String;
      expect(result.exitCode, equals(0));
      // Canonical verbose format: the runner echoes the executed shell command
      // under the structured `[PIPELINE:shell]` marker (alongside `[startup]`
      // timing lines and, for piped steps, `[PIPELINE:stdin]` / `[DRY RUN]`).
      // The old ad-hoc human label 'Multi-line shell script' was removed in
      // favour of this machine-parseable scheme; assert the structured marker.
      expect(stdout, contains('[PIPELINE:shell]'),
          reason: 'verbose mode should echo the multi-line shell command under '
              'the structured [PIPELINE:shell] marker');
      log.expectation(
          'verbose echoes shell command under [PIPELINE:shell]',
          stdout.contains('[PIPELINE:shell]'));
    });

    test('stdin piping sends content to command', () async {
      log.start('SCR_STD01',
          'stdin piping sends content to command');
      final result = await ws.runPipeline('test-stdin', []);
      log.capture('buildkit test-stdin', result);

      final stdout = result.stdout as String;
      expect(result.exitCode, equals(0),
          reason: 'Pipeline should succeed');
      // The `test-stdin` fixture pipes "Hello stdin world\nline two" to `cat`,
      // which echoes it back. Assert that real piped content (the stale
      // 'stdin-line-1'/'stdin-line-2' strings were left over from an older
      // fixture body and never appear in the current output).
      expect(stdout, contains('Hello stdin world'),
          reason: 'cat should echo the piped stdin content');
      expect(stdout, contains('line two'),
          reason: 'cat should echo all piped stdin lines');
      log.expectation('stdin content appears in output',
          stdout.contains('Hello stdin world') && stdout.contains('line two'));
    });

    test('stdin piping in verbose mode', () async {
      log.start('SCR_STD02',
          'stdin piping verbose output');
      final binPath = p.join(ws.buildkitRoot, 'bin', 'buildkit.dart');
      final result = await Process.run(
        'dart',
        ['run', binPath, '--verbose', 'test-stdin'],
        workingDirectory: ws.workspaceRoot,
      );
      log.capture('buildkit --verbose test-stdin', result);

      final stdout = result.stdout as String;
      expect(result.exitCode, equals(0));
      // Canonical verbose format (see AA16): the runner echoes the stdin step
      // under the structured `[PIPELINE:stdin]` marker (parallel to
      // `[PIPELINE:shell]`), not the old prose label 'Piping stdin to'.
      expect(stdout, contains('[PIPELINE:stdin]'),
          reason: 'verbose mode should echo the stdin step under the '
              'structured [PIPELINE:stdin] marker');
      log.expectation('verbose echoes stdin step under [PIPELINE:stdin]',
          stdout.contains('[PIPELINE:stdin]'));
    });

    test('multi-line shell dry-run shows preview', () async {
      log.start('SCR_DRY01',
          'multi-line shell dry-run shows preview');
      final binPath = p.join(ws.buildkitRoot, 'bin', 'buildkit.dart');
      final result = await Process.run(
        'dart',
        ['run', binPath, '--dry-run', 'test-multiline-shell'],
        workingDirectory: ws.workspaceRoot,
      );
      log.capture('buildkit --dry-run test-multiline-shell', result);

      final stdout = result.stdout as String;
      expect(result.exitCode, equals(0));
      // Canonical dry-run format for pipeline shell steps (see AA16; source:
      // tom_build_base pipeline_executor `_runShell`): the command is previewed
      // under the structured `[PIPELINE:shell]` marker, then NOT executed
      // (`if (dryRun) return true;`). The old '[DRY RUN]' / 'Would execute'
      // prose is not emitted for pipeline steps.
      expect(stdout, contains('[PIPELINE:shell]'),
          reason: 'dry-run should preview the shell command under the '
              'structured [PIPELINE:shell] marker');
      // Verify the command was previewed but NOT executed: the bare echo result
      // line 'multi-line-1' must be absent. (The command text
      // 'echo "multi-line-1"' is shown by the marker, but the command does not
      // run, so its output never appears.)
      final executed = stdout
          .split('\n')
          .map((line) => line.trim())
          .contains('multi-line-1');
      expect(executed, isFalse,
          reason: 'dry-run should not execute the shell command');
      log.expectation('dry-run previews command without executing',
          stdout.contains('[PIPELINE:shell]') && !executed);
    });

    test('stdin dry-run shows preview', () async {
      log.start('SCR_DRY02',
          'stdin dry-run shows preview');
      final binPath = p.join(ws.buildkitRoot, 'bin', 'buildkit.dart');
      final result = await Process.run(
        'dart',
        ['run', binPath, '--dry-run', 'test-stdin'],
        workingDirectory: ws.workspaceRoot,
      );
      log.capture('buildkit --dry-run test-stdin', result);

      final stdout = result.stdout as String;
      expect(result.exitCode, equals(0));
      expect(stdout, contains('[DRY RUN]'));
      expect(stdout, contains('stdin'));
      log.expectation('stdin dry-run preview shown', true);
    });
  });
}
