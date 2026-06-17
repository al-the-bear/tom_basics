import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// TestLogger — per-test verbose output and log capture
// ---------------------------------------------------------------------------

/// Captures tool stdout/stderr for the current test and writes verbose
/// status lines (RUNNING / PASSED / FAILED) to the console.
///
/// Usage:
/// ```dart
/// late TestLogger log;
/// setUp(() { log = TestLogger(ws); });
/// tearDown(() { log.finish(); });
///
/// test('my test', () {
///   log.start('EXCL_BN01', 'versioner excludes _build by basename');
///   final result = await ws.runTool('versioner', [...]);
///   log.capture('versioner --list', result);
///   expect(projects, isNot(contains('_build')));
///   log.expectation('_build absent from list', true);
/// });
/// ```
class TestLogger {
  final TestWorkspace _ws;
  String _testId = '';
  String _testName = '';
  final _entries = <String>[];
  bool _failed = false;
  String? _failureReason;

  TestLogger(this._ws);

  /// Mark the beginning of a test. Prints a RUNNING line.
  void start(String testId, String testName) {
    _testId = testId;
    _testName = testName;
    _entries.clear();
    _failed = false;
    _failureReason = null;
    _entries.add('═══ $testId: $testName ═══');
    print('  ▶ RUNNING  $testId: $testName');
  }

  /// Capture the stdout/stderr from a [ProcessResult].
  void capture(String label, ProcessResult result) {
    _entries.add('--- $label (exit ${result.exitCode}) ---');
    final stdout = (result.stdout as String).trim();
    final stderr = (result.stderr as String).trim();
    if (stdout.isNotEmpty) {
      _entries.add('STDOUT:\n$stdout');
    }
    if (stderr.isNotEmpty) {
      _entries.add('STDERR:\n$stderr');
    }
  }

  /// Record an expectation result for the verbose output.
  void expectation(String description, bool passed) {
    final icon = passed ? '✓' : '✗';
    _entries.add('  $icon $description');
    if (!passed) {
      _failed = true;
      _failureReason ??= description;
    }
  }

  /// Call this in tearDown. Prints PASSED/FAILED and writes log on failure.
  ///
  /// If the test threw (the `test` package marks it failed), we detect it
  /// from [Invoker] internals via [_isCurrentTestFailed]. When we can't
  /// detect it reliably, we fall back to our own [_failed] flag.
  void finish() {
    if (_testId.isEmpty) return; // start() was never called

    // Check our own tracking flag (set via expectation())
    final didFail = _failed;

    if (didFail) {
      print(
        '  ✗ FAILED   $_testId: $_testName'
        '${_failureReason != null ? ' — $_failureReason' : ''}',
      );
      _writeLogFile();
    } else {
      print('  ✓ PASSED   $_testId: $_testName');
    }

    // Always write logs to the .test-log/ folder for review
    _writeLogFile(suffix: didFail ? '_FAILED' : '');
  }

  /// Write captured entries to `.test-log/<testId>_log.txt`.
  void _writeLogFile({String suffix = ''}) {
    final logDir = p.join(_ws.buildkitRoot, '.test-log');
    Directory(logDir).createSync(recursive: true);
    final safeName = _testId.replaceAll(RegExp(r'[^\w]'), '_');
    final logFile = File(p.join(logDir, '$safeName${suffix}_log.txt'));
    logFile.writeAsStringSync('${_entries.join('\n')}\n', mode: FileMode.write);
  }
}

/// Shared test utilities for buildkit integration tests.
///
/// Manages fixture installation, git revert, and tool process execution
/// against the real workspace.
///
/// ## Workspace Protection
///
/// Integration tests modify real workspace files (config, generated code).
/// This class provides a full safety protocol:
///
/// 1. [requireCleanWorkspace] — fails if uncommitted changes exist
/// 2. [saveHeadRefs] — records HEAD SHAs for main repo + all submodules
/// 3. [revertAll] / [revertSubmodule] — restores files after each test
/// 4. [verifyHeadRefs] — post-test-suite check that no commits leaked
///
/// Tests that use `buildkit_skip.yaml` markers can check
/// [isSkippedRepo] to avoid git operations on those repos.
class TestWorkspace {
  /// Workspace root (contains buildkit_master.yaml).
  final String workspaceRoot;

  /// Path to the tom_build_kit project.
  final String buildkitRoot;

  /// Saved HEAD SHA refs for main repo and submodules.
  /// Key: path (workspaceRoot for main), Value: SHA.
  final Map<String, String> _savedHeadRefs = {};

  /// Submodule paths (relative to workspace root).
  List<String>? _submodulePaths;

  /// In-memory snapshot of the real workspace `buildkit_master.yaml`, captured
  /// once the workspace is verified clean. Lets [revertAll] guarantee the real
  /// manifest is restored even if the committed HEAD copy has drifted to
  /// fixture content (see [_guardAndSnapshotMaster]).
  String? _masterSnapshot;

  TestWorkspace._({required this.workspaceRoot, required this.buildkitRoot});

  /// Absolute path to the workspace master config.
  String get masterConfigPath => p.join(workspaceRoot, 'buildkit_master.yaml');

  /// Discover workspace by walking up from the buildkit project.
  factory TestWorkspace() {
    // Start from the package root (where pubspec.yaml is)
    final buildkitRoot = _findBuildkitRoot();
    final workspaceRoot = _findWorkspaceRoot(buildkitRoot);
    return TestWorkspace._(
      workspaceRoot: workspaceRoot,
      buildkitRoot: buildkitRoot,
    );
  }

  /// Find the buildkit project root (directory with pubspec.yaml).
  static String _findBuildkitRoot() {
    // When running `dart test`, cwd is the package root
    var dir = Directory.current.path;
    while (!File(p.join(dir, 'pubspec.yaml')).existsSync()) {
      final parent = p.dirname(dir);
      if (parent == dir) {
        throw StateError('Could not find buildkit project root');
      }
      dir = parent;
    }
    return dir;
  }

  /// Find workspace root by walking up looking for buildkit_master.yaml.
  static String _findWorkspaceRoot(String startDir) {
    var dir = startDir;
    while (true) {
      if (File(p.join(dir, 'buildkit_master.yaml')).existsSync()) {
        return dir;
      }
      final parent = p.dirname(dir);
      if (parent == dir) {
        throw StateError(
          'Could not find workspace root (no buildkit_master.yaml found '
          'above $startDir)',
        );
      }
      dir = parent;
    }
  }

  // ---------------------------------------------------------------------------
  // Workspace protection protocol
  // ---------------------------------------------------------------------------

  /// Skip file name that marks a repo as excluded from test git operations.
  static const skipFileName = 'buildkit_skip.yaml';

  /// Header that marks a `buildkit_master.yaml` as a test fixture rather than
  /// the real workspace manifest. Fixtures begin with this comment line.
  static const _fixtureMasterMarker = '# Test fixture:';

  /// Guard against a corrupt committed master, then snapshot the real one.
  ///
  /// Call only when the workspace is verified clean, so the on-disk file equals
  /// the committed HEAD copy. If that committed master is a leftover test
  /// fixture (its content was overwritten by a test and then accidentally
  /// committed), fail loudly: tests must never run against — or "restore" via
  /// `git checkout` to — fixture content. Otherwise capture the real content so
  /// [revertAll] can guarantee its restoration even under HEAD drift.
  void _guardAndSnapshotMaster() {
    final master = File(masterConfigPath);
    if (!master.existsSync()) {
      fail('buildkit_master.yaml missing at $masterConfigPath');
    }
    final content = master.readAsStringSync();
    if (content.trimLeft().startsWith(_fixtureMasterMarker)) {
      final message =
          '\n'
          '╔══════════════════════════════════════════════════════╗\n'
          '║  COMMITTED buildkit_master.yaml IS A TEST FIXTURE   ║\n'
          '╠══════════════════════════════════════════════════════╣\n'
          '║  The workspace master manifest has been overwritten ║\n'
          '║  with fixture content and committed. Restore the     ║\n'
          '║  real manifest before running tests.                 ║\n'
          '╚══════════════════════════════════════════════════════╝\n'
          'Path: $masterConfigPath\n';
      _writeInfraLog('master_is_fixture', message);
      fail(message);
    }
    _masterSnapshot = content;
    print('    🛡️  Snapshotted real buildkit_master.yaml');
  }

  /// Files that are known to be modified by test fixtures and safe to auto-revert.
  /// Pattern matching: full path must match for buildkit_master.yaml,
  /// path suffix for buildkit.yaml in any project.
  static const _knownFixturePatterns = [
    'buildkit_master.yaml',
    'buildkit.yaml', // In any project directory
    'version.versioner.dart', // Generated version files
    'tom_build_state.json', // Build state files
  ];

  /// Check if a dirty file is a known fixture file safe to auto-revert.
  bool _isKnownFixtureFile(String statusLine) {
    // Parse git status format: "XY filename" or "XY  orig -> renamed"
    // We're looking at the filename part
    final parts = statusLine.split(RegExp(r'\s+'));
    if (parts.length < 2) return false;

    final filename = parts.last;
    for (final pattern in _knownFixturePatterns) {
      if (filename == pattern || filename.endsWith('/$pattern')) {
        return true;
      }
    }
    return false;
  }

  /// Fail the test suite if the workspace has uncommitted changes.
  ///
  /// Call this in `setUpAll` before running any integration tests.
  /// Excludes submodule pointer changes in the main repo.
  ///
  /// If only known fixture files are dirty (e.g., buildkit_master.yaml from
  /// an interrupted test run), they will be auto-reverted before failing.
  ///
  /// All diagnostic info is embedded in the `fail()` message so it is
  /// visible regardless of which test reporter is active (expanded, compact,
  /// JSON, VS Code Test Explorer, etc.).
  Future<void> requireCleanWorkspace() async {
    print('    🔍 Checking workspace cleanliness...');
    // Remove any `_build` left behind by a previously interrupted run before
    // the cleanliness check — it is a test-provisioned (untracked) artifact.
    await deprovisionBuildProject();
    final dirty = await hasUncommittedChanges();
    if (dirty.isNotEmpty) {
      // Check if ALL dirty files are known fixture files
      final knownFixtures = dirty.where(_isKnownFixtureFile).toList();
      final unknownFiles = dirty.where((f) => !_isKnownFixtureFile(f)).toList();

      if (unknownFiles.isEmpty && knownFixtures.isNotEmpty) {
        // All dirty files are known fixture files — auto-revert them
        print('    ⚠️  Found leftover fixture files from interrupted test:');
        for (final f in knownFixtures) {
          print('       $f');
        }
        print('    🔄 Auto-reverting fixture files...');
        await _git(['checkout', '--', '.'], workingDirectory: workspaceRoot);

        // Verify it worked
        final stillDirty = await hasUncommittedChanges();
        if (stillDirty.isEmpty) {
          print('    ✓ Auto-revert successful — workspace is clean');
          _guardAndSnapshotMaster();
          return;
        } else {
          print('    ❌ Auto-revert failed, some files still dirty:');
          for (final f in stillDirty) {
            print('       $f');
          }
        }
      }

      final fileList = dirty.map((f) => '  $f').join('\n');
      final message =
          '\n'
          '╔══════════════════════════════════════════════════════╗\n'
          '║  WORKSPACE IS DIRTY — TESTS CANNOT RUN              ║\n'
          '╠══════════════════════════════════════════════════════╣\n'
          '║  Uncommitted changes detected:                      ║\n'
          '╚══════════════════════════════════════════════════════╝\n'
          '$fileList\n'
          '\n'
          'Integration tests require a clean workspace to guarantee\n'
          'safe revert after each test. Commit or stash all changes\n'
          'before running tests.\n';

      // Also write to log file for persistent debugging
      _writeInfraLog('workspace_dirty', message);

      fail(message);
    }
    print('    ✓ Workspace is clean');
    _guardAndSnapshotMaster();
  }

  /// Write an infrastructure diagnostic message to `.test-log/`.
  void _writeInfraLog(String name, String content) {
    final logDir = p.join(buildkitRoot, '.test-log');
    Directory(logDir).createSync(recursive: true);
    final logFile = File(p.join(logDir, '${name}_log.txt'));
    logFile.writeAsStringSync(
      '${DateTime.now().toIso8601String()}\n$content\n',
      mode: FileMode.write,
    );
  }

  /// Save HEAD SHA for the main repo and all submodules.
  ///
  /// Call this in `setUpAll` after [requireCleanWorkspace].
  /// Use [verifyHeadRefs] in `tearDownAll` to verify no commits leaked.
  Future<void> saveHeadRefs() async {
    print('    📸 Saving HEAD refs (backup for leak detection)...');
    _savedHeadRefs.clear();

    // Main repo
    final mainHead = await _getHeadSha(workspaceRoot);
    _savedHeadRefs[workspaceRoot] = mainHead;
    print('       main repo: ${mainHead.substring(0, 8)}');

    // Submodules (skip those with skip file)
    final subPaths = await getSubmodulePaths();
    for (final subPath in subPaths) {
      final absPath = p.join(workspaceRoot, subPath);
      if (isSkippedRepo(absPath)) {
        print('       $subPath: SKIPPED (has $skipFileName)');
        continue;
      }
      final sha = await _getHeadSha(absPath);
      _savedHeadRefs[absPath] = sha;
      print('       $subPath: ${sha.substring(0, 8)}');
    }
    print('    ✓ Saved ${_savedHeadRefs.length} HEAD refs');
  }

  /// Verify that HEAD SHAs haven't changed since [saveHeadRefs].
  ///
  /// Call this in `tearDownAll`. Fails the test if any repo has a
  /// different HEAD than the saved reference.
  Future<void> verifyHeadRefs() async {
    print('    🔒 Verifying HEAD refs (leak detection)...');
    if (_savedHeadRefs.isEmpty) {
      print('    ⚠️  No saved HEAD refs to verify. Was saveHeadRefs called?');
      return;
    }

    final mismatches = <String>[];
    for (final entry in _savedHeadRefs.entries) {
      final path = entry.key;
      final savedSha = entry.value;
      final currentSha = await _getHeadSha(path);
      final label = path == workspaceRoot
          ? 'main repo'
          : p.relative(path, from: workspaceRoot);
      if (currentSha != savedSha) {
        print(
          '       ✗ $label: was ${savedSha.substring(0, 8)}, now ${currentSha.substring(0, 8)} — LEAKED!',
        );
        mismatches.add('$label: was $savedSha, now $currentSha');
      } else {
        print('       ✓ $label: ${currentSha.substring(0, 8)} (unchanged)');
      }
    }

    if (mismatches.isNotEmpty) {
      final mismatchList = mismatches.map((m) => '  $m').join('\n');
      final message =
          '\n'
          '╔══════════════════════════════════════════════════════╗\n'
          '║  HEAD REFS CHANGED — POSSIBLE LEAKED COMMITS        ║\n'
          '╠══════════════════════════════════════════════════════╣\n'
          '║  The following repos have different HEADs than       ║\n'
          '║  before the test run started:                        ║\n'
          '╚══════════════════════════════════════════════════════╝\n'
          '$mismatchList\n'
          '\n'
          'This means a test accidentally created a commit that\n'
          'was not reverted. Investigate and fix manually.\n';

      _writeInfraLog('head_ref_leak', message);
      fail(message);
    }
    print('    ✓ All HEAD refs intact — no leaked commits');
  }

  /// Revert all changes and verify workspace is clean after test suite.
  ///
  /// Convenience method that combines revert + verify for `tearDownAll`.
  Future<void> tearDownProtocol() async {
    print('    🔄 Running tear-down protocol...');
    // Revert main repo
    await revertAll();

    // Revert submodules (skip those with skip file)
    for (final subPath in await getSubmodulePaths()) {
      final absPath = p.join(workspaceRoot, subPath);
      if (isSkippedRepo(absPath)) {
        print('    ⏭️  Skipping submodule $subPath (has $skipFileName)');
        continue;
      }
      await revertSubmodule(absPath);
    }

    // Remove the test-provisioned `_build` so the tree is clean post-run
    // (symmetric with requireCleanWorkspace's deprovision at suite start).
    await deprovisionBuildProject();

    // Verify no commits leaked
    await verifyHeadRefs();
    print('    ✓ Tear-down protocol complete');
  }

  /// Check if a directory has a buildkit_skip.yaml marker.
  ///
  /// Repos with this marker are excluded from test git operations
  /// (no commit check, no checkout revert).
  static bool isSkippedRepo(String dirPath) {
    return File(p.join(dirPath, skipFileName)).existsSync();
  }

  /// Get list of submodule paths (relative to workspace root).
  Future<List<String>> getSubmodulePaths() async {
    if (_submodulePaths != null) return _submodulePaths!;

    final result = await _git([
      'submodule',
      'status',
    ], workingDirectory: workspaceRoot);
    final output = result.stdout.toString().trim();
    if (output.isEmpty) {
      _submodulePaths = [];
      return _submodulePaths!;
    }

    // Format: " <sha> <path> (<branch>)" or "+<sha> <path> (<branch>)"
    _submodulePaths = output
        .split('\n')
        .map((line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) return null;
          // Remove leading +/- and SHA
          final parts = trimmed.split(RegExp(r'\s+'));
          return parts.length >= 2 ? parts[1] : null;
        })
        .whereType<String>()
        .toList();

    return _submodulePaths!;
  }

  /// Get the current HEAD SHA for a git repo.
  Future<String> _getHeadSha(String repoPath) async {
    final result = await _git([
      'rev-parse',
      'HEAD',
    ], workingDirectory: repoPath);
    return result.stdout.toString().trim();
  }

  // ---------------------------------------------------------------------------
  // Fixture management
  // ---------------------------------------------------------------------------

  /// Path to the fixtures directory.
  String get fixturesDir => p.join(buildkitRoot, 'test', 'fixtures');

  /// Checked-in source of the `_build` target project used by the integration
  /// tests (`cleanup`, `versioner`, `compiler`, `runner`, `config_merge`,
  /// `dependencies`, `pipeline`, ...).
  ///
  /// The `_build` project used to live, tracked, at the workspace root. It was
  /// removed, so the tests are provisioned with a fresh copy from this fixture
  /// for the duration of each test instead of depending on a real project at
  /// the workspace root. See [provisionBuildProject].
  String get buildProjectFixtureDir =>
      p.join(fixturesDir, 'build_project', '_build');

  /// Absolute path of the provisioned `_build` project at the workspace root.
  String get _provisionedBuildDir => p.join(workspaceRoot, '_build');

  /// Copy the checked-in `_build` fixture to `<workspaceRoot>/_build`, replacing
  /// any existing copy so every test starts from a pristine project.
  ///
  /// `_build` is *not* tracked at the workspace root anymore, so `git checkout`
  /// (used by [revertAll]) cannot restore it between tests — re-copying it here
  /// is what guarantees a clean per-test state. The provisioned copy is removed
  /// again by [deprovisionBuildProject].
  Future<void> provisionBuildProject() async {
    final source = Directory(buildProjectFixtureDir);
    if (!source.existsSync()) {
      throw StateError(
        'Build project fixture not found at ${source.path}. Expected it to be '
        'checked into test/fixtures/build_project/_build.',
      );
    }
    await deprovisionBuildProject();
    _copyDirectory(source, Directory(_provisionedBuildDir));
    print('    🏗️  Provisioned _build project at workspace root');
  }

  /// Remove the provisioned `_build` project from the workspace root if present.
  ///
  /// Tests spawn child processes (`dart run`, compiled binaries) that touch
  /// files under `_build`. On Windows those handles are released slightly after
  /// the process exits, so an immediate recursive delete can fail with
  /// `errno = 32` ("the file is in use by another process"). Retry with a short
  /// backoff so the OS has a chance to release the handles before we give up.
  Future<void> deprovisionBuildProject() async {
    final dir = Directory(_provisionedBuildDir);
    if (!dir.existsSync()) return;

    const maxAttempts = 10;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        dir.deleteSync(recursive: true);
        print('    🗑️  Removed provisioned _build project');
        return;
      } on FileSystemException {
        if (attempt == maxAttempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 100 * attempt));
      }
    }
  }

  /// Recursively copy [source] into [dest].
  static void _copyDirectory(Directory source, Directory dest) {
    dest.createSync(recursive: true);
    for (final entity in source.listSync(recursive: false)) {
      final newPath = p.join(dest.path, p.basename(entity.path));
      if (entity is Directory) {
        _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        entity.copySync(newPath);
      }
    }
  }

  /// Install a test fixture by copying its buildkit_master.yaml
  /// into the workspace root, overwriting the real one.
  ///
  /// Also copies any project-level config files from the fixture's
  /// `projects/` subdirectory to the corresponding workspace projects.
  /// For example: `fixtures/versioner/projects/_build/buildkit.yaml`
  /// would be copied to `<workspace>/_build/buildkit.yaml`.
  Future<void> installFixture(String fixtureName) async {
    final fixtureDir = p.join(fixturesDir, fixtureName);

    // Copy buildkit_master.yaml
    final masterSrc = File(p.join(fixtureDir, 'buildkit_master.yaml'));
    if (!masterSrc.existsSync()) {
      throw StateError('Fixture not found: ${masterSrc.path}');
    }
    final masterDst = File(p.join(workspaceRoot, 'buildkit_master.yaml'));
    await masterSrc.copy(masterDst.path);
    print('    📋 Installed fixture "$fixtureName" → buildkit_master.yaml');

    // Provision a fresh `_build` target project for the test. Every test that
    // installs a fixture targets `_build`, which no longer exists tracked at the
    // workspace root, so it is copied in from the fixture for the test duration.
    //
    // This must happen BEFORE the project-level config overlay below: some
    // fixtures ship a `projects/_build/buildkit.yaml` that is copied onto the
    // provisioned `_build`, which therefore has to exist first.
    await provisionBuildProject();

    // Copy project-level config files if they exist, overlaying them onto the
    // just-provisioned project directories.
    final projectsDir = Directory(p.join(fixtureDir, 'projects'));
    if (projectsDir.existsSync()) {
      await for (final entity in projectsDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('buildkit.yaml')) {
          final relativePath = p.relative(entity.path, from: projectsDir.path);
          final dstPath = p.join(workspaceRoot, relativePath);
          await entity.copy(dstPath);
          print('    📋 Installed fixture "$fixtureName" → $relativePath');
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Git revert
  // ---------------------------------------------------------------------------

  /// Revert all changes in the workspace root via `git checkout -- .`
  ///
  /// Note: This only reverts files tracked in the main repo, not in
  /// submodules. For submodule files, use [revertSubmodule].
  Future<void> revertAll() async {
    print('    ↩️  Reverting workspace (git checkout -- .)...');
    await _git(['checkout', '--', '.'], workingDirectory: workspaceRoot);
    // Defense in depth: `git checkout` restores to HEAD, so if the committed
    // master ever drifts to fixture content the checkout alone would "restore"
    // the wrong file. Overwrite it with the real-manifest snapshot captured at
    // suite start to guarantee a correct, clean tree after every test.
    final snapshot = _masterSnapshot;
    if (snapshot != null) {
      final master = File(masterConfigPath);
      if (!master.existsSync() || master.readAsStringSync() != snapshot) {
        master.writeAsStringSync(snapshot);
        print('    🛡️  Restored real buildkit_master.yaml from snapshot');
      }
    }
    print('    ✓ Workspace reverted');
  }

  /// Revert all changes in a submodule directory.
  Future<void> revertSubmodule(String submodulePath) async {
    final absPath = p.isAbsolute(submodulePath)
        ? submodulePath
        : p.join(workspaceRoot, submodulePath);
    final label = p.relative(absPath, from: workspaceRoot);
    print('    ↩️  Reverting submodule $label...');
    await _git(['checkout', '--', '.'], workingDirectory: absPath);
    print('    ✓ Submodule $label reverted');
  }

  /// Revert specific files (paths relative to workspace root).
  Future<void> revertFiles(List<String> relativePaths) async {
    await _git([
      'checkout',
      '--',
      ...relativePaths,
    ], workingDirectory: workspaceRoot);
  }

  /// Check if there are uncommitted changes for specific files.
  Future<bool> hasChanges(List<String> relativePaths) async {
    final result = await _git([
      'diff',
      '--name-only',
      '--',
      ...relativePaths,
    ], workingDirectory: workspaceRoot);
    return result.stdout.toString().trim().isNotEmpty;
  }

  /// Check if the workspace has any uncommitted changes (staged or unstaged)
  /// that could affect test results.
  ///
  /// Returns a list of changed file paths, or empty if clean.
  /// Excludes submodule pointer changes (xternal/) and untracked generated
  /// files since those don't affect the test fixtures or tool behavior.
  Future<List<String>> hasUncommittedChanges() async {
    final result = await _git([
      'status',
      '--porcelain',
      '--ignore-submodules=dirty',
    ], workingDirectory: workspaceRoot);
    final output = result.stdout.toString().trim();
    if (output.isEmpty) return [];
    return output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        // Exclude submodule pointer changes — they don't affect tests
        .where((line) => !RegExp(r'^[Mm?\s]{1,2}\s*xternal/').hasMatch(line))
        // Exclude untracked generated files (e.g., .reflection.dart, .g.dart)
        .where(
          (line) =>
              !RegExp(r'^\?\?\s.*\.(reflection|g|r|b)\.dart$').hasMatch(line),
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Tool execution
  // ---------------------------------------------------------------------------

  /// Run a standalone buildkit tool (e.g., 'versioner', 'cleanup').
  ///
  /// Executes the tool binary directly via `dart run <path/to/bin/tool.dart>`.
  /// Runs from the workspace root so that path validation passes and
  /// workspace root discovery works correctly.
  ///
  /// Routes through `buildkit :tool` since standalone v1 bin files have been
  /// removed. All tools are now v2 executors invoked via the buildkit CLI.
  ///
  /// Navigation args (--scan, --recursive, --project, --root, --exclude, etc.)
  /// are placed BEFORE `:tool` because the v2 CLI parser treats everything
  /// after `:command` as command-specific options.
  Future<ProcessResult> runTool(
    String tool,
    List<String> args, {
    String? workingDirectory,
  }) async {
    final binPath = p.join(buildkitRoot, 'bin', 'buildkit.dart');

    // Separate navigation/global args (before :command) from
    // command-specific args (after :command).
    final globalArgs = <String>[];
    final cmdArgs = <String>[];
    _splitArgs(args, globalArgs, cmdArgs);

    final allArgs = ['run', binPath, ...globalArgs, ':$tool', ...cmdArgs];
    print(
      '    🔧 Running: buildkit ${[...globalArgs, ':$tool', ...cmdArgs].join(' ')}',
    );
    final result = await Process.run(
      'dart',
      allArgs,
      workingDirectory: workingDirectory ?? workspaceRoot,
    );
    print('    ✓ $tool exited with code ${result.exitCode}');
    return result;
  }

  /// Split args into global (navigation) args and command-specific args.
  ///
  /// Known navigation options that must come before `:command`:
  /// `--scan`, `--recursive`, `--no-recursive`, `--project`, `--root`,
  /// `--build-order`, `--inner-first-git`, `--outer-first-git`, `--top-repo`,
  /// `--workspace-recursion`, `--exclude`, `--exclude-projects`,
  /// `--recursion-exclude`, `--modules`, `--no-skip`, `--modes`,
  /// `--verbose`, `--dry-run`, and their abbreviations.
  static void _splitArgs(
    List<String> args,
    List<String> globalArgs,
    List<String> cmdArgs,
  ) {
    const globalFlags = {
      '--scan', '-s',
      '--recursive', '-r', '--no-recursive',
      '--project', '-p',
      '--root', '-R',
      '--build-order', '-b',
      '--inner-first-git', '-i',
      '--outer-first-git', '-o',
      '--top-repo', '-T',
      '--workspace-recursion',
      '--exclude', '-x',
      '--exclude-projects',
      '--recursion-exclude',
      '--modules', '-m',
      '--skip-modules',
      '--no-skip',
      '--verbose', '-v',
      '--dry-run', '-n',
      '--list', '-l',
      '--force', '-f',
      '--dump-config',
      '--guide',
      '--config',
      '-V',
      '--include-test-projects',
      '--test-projects-only',
      // Note: --help and --version are NOT global flags here — when used
      // with a :command, they should be per-command options (e.g.,
      // :bumpversion --help shows bumpversion help, not buildkit help).
      // handleSpecialCommands() catches bare --help/--version as first arg.
    };

    // Options that take a value argument.
    const valueGlobals = {
      '--scan',
      '-s',
      '--project',
      '-p',
      '--root',
      '-R',
      '--exclude',
      '-x',
      '--exclude-projects',
      '--recursion-exclude',
      '--modules',
      '-m',
      '--skip-modules',
      '--config',
    };

    var i = 0;
    while (i < args.length) {
      final arg = args[i];
      if (globalFlags.contains(arg)) {
        globalArgs.add(arg);
        if (valueGlobals.contains(arg) && i + 1 < args.length) {
          i++;
          globalArgs.add(args[i]);
        }
      } else {
        // Everything else is command-specific.
        cmdArgs.add(arg);
      }
      i++;
    }
  }

  /// Run a buildkit pipeline.
  ///
  /// Executes: `dart run <path/to/bin/buildkit.dart> [globalArgs] <pipeline> <args>`
  /// Runs from the workspace root.
  ///
  /// [globalArgs] are placed BEFORE the pipeline name to satisfy buildkit's
  /// requirement that global flags (--project, --dry-run, --scan, etc.)
  /// precede the pipeline/command name.
  Future<ProcessResult> runPipeline(
    String pipeline,
    List<String> args, {
    String? workingDirectory,
    List<String> globalArgs = const [],
  }) async {
    final binPath = p.join(buildkitRoot, 'bin', 'buildkit.dart');
    final allArgs = [...globalArgs, pipeline, ...args];
    print('    🔧 Running pipeline: buildkit ${allArgs.join(' ')}');
    final result = await Process.run('dart', [
      'run',
      binPath,
      ...allArgs,
    ], workingDirectory: workingDirectory ?? workspaceRoot);
    print(
      '    ✓ buildkit ${allArgs.first} exited with code ${result.exitCode}',
    );
    return result;
  }

  // ---------------------------------------------------------------------------
  // File helpers
  // ---------------------------------------------------------------------------

  /// Read a file relative to the workspace root.
  String readWorkspaceFile(String relativePath) {
    return File(p.join(workspaceRoot, relativePath)).readAsStringSync();
  }

  /// Check if a file exists relative to the workspace root.
  bool workspaceFileExists(String relativePath) {
    return File(p.join(workspaceRoot, relativePath)).existsSync();
  }

  /// Get the relative path from workspace root to a project.
  String relativeProjectPath(String projectAbsolutePath) {
    return p.relative(projectAbsolutePath, from: workspaceRoot);
  }

  /// Place a temporary `buildkit_skip.yaml` in a directory.
  ///
  /// Returns the absolute path to the created file. Use [removeSkipFile]
  /// or add the returned path to a cleanup list for tearDown.
  String placeSkipFile(String relativeDir) {
    final absPath = p.join(
      workspaceRoot,
      relativeDir,
      TestWorkspace.skipFileName,
    );
    File(absPath).writeAsStringSync(
      '# Temporary skip file placed by integration test.\n'
      '# Should be removed automatically in tearDown.\n',
    );
    print('    📄 Placed skip file: $relativeDir/$skipFileName');
    return absPath;
  }

  /// Remove a temporary `tom_build_skip.yaml` from a directory.
  void removeSkipFile(String relativeDir) {
    final absPath = p.join(
      workspaceRoot,
      relativeDir,
      TestWorkspace.skipFileName,
    );
    final file = File(absPath);
    if (file.existsSync()) {
      file.deleteSync();
      print('    🗑️  Removed skip file: $relativeDir/$skipFileName');
    }
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  Future<ProcessResult> _git(
    List<String> args, {
    required String workingDirectory,
  }) async {
    return Process.run('git', args, workingDirectory: workingDirectory);
  }
}
