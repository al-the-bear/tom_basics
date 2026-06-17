/// Native v2 executor for the :status command.
///
/// Shows buildkit version, binary status, and git state.
/// Replaces the v1 StatusTool that extended ToolBase.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart';

import '../../version.versioner.dart';

// =============================================================================
// Data classes (moved from v1 status_tool.dart)
// =============================================================================

/// Status information for a buildkit tool binary.
class ToolStatus {
  final String name;
  final String? version;
  final String? buildNumber;
  final String? gitCommit;
  final String? buildTime;
  final String? dartSdkVersion;
  final bool available;
  final bool conformant;
  final String? error;

  ToolStatus({
    required this.name,
    this.version,
    this.buildNumber,
    this.gitCommit,
    this.buildTime,
    this.dartSdkVersion,
    this.available = true,
    this.conformant = true,
    this.error,
  });

  /// Whether this tool's version matches the source version.
  bool matchesSource(
    String sourceVersion,
    int sourceBuildNumber,
    String sourceCommit,
  ) {
    return version == sourceVersion &&
        buildNumber == sourceBuildNumber.toString() &&
        gitCommit == sourceCommit;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'available': available,
    'conformant': conformant,
    if (version != null) 'version': version,
    if (buildNumber != null) 'buildNumber': buildNumber,
    if (gitCommit != null) 'gitCommit': gitCommit,
    if (buildTime != null) 'buildTime': buildTime,
    if (dartSdkVersion != null) 'dartSdkVersion': dartSdkVersion,
    if (error != null) 'error': error,
  };
}

/// Git status information for a repository.
class GitRepoStatus {
  final String path;
  final String name;
  final String branch;
  final List<String> stagedFiles;
  final List<String> unstagedFiles;
  final List<String> untrackedFiles;
  final List<String> unpushedCommits;

  GitRepoStatus({
    required this.path,
    required this.name,
    required this.branch,
    this.stagedFiles = const [],
    this.unstagedFiles = const [],
    this.untrackedFiles = const [],
    this.unpushedCommits = const [],
  });

  bool get hasChanges =>
      stagedFiles.isNotEmpty ||
      unstagedFiles.isNotEmpty ||
      untrackedFiles.isNotEmpty;

  bool get hasUnpushed => unpushedCommits.isNotEmpty;

  int get totalChanges =>
      stagedFiles.length + unstagedFiles.length + untrackedFiles.length;

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'branch': branch,
    'hasChanges': hasChanges,
    'hasUnpushed': hasUnpushed,
    'staged': stagedFiles,
    'unstaged': unstagedFiles,
    'untracked': untrackedFiles,
    'unpushedCommits': unpushedCommits,
  };
}

/// Overall status result.
class StatusResult {
  final String sourceVersion;
  final int sourceBuildNumber;
  final String sourceCommit;
  final String sourceBuildTime;
  final String sourceDartSdk;
  final List<ToolStatus> tools;
  final List<GitRepoStatus> repos;
  final int commitsSinceOldest;
  final String? oldestToolCommit;

  StatusResult({
    required this.sourceVersion,
    required this.sourceBuildNumber,
    required this.sourceCommit,
    required this.sourceBuildTime,
    required this.sourceDartSdk,
    this.tools = const [],
    this.repos = const [],
    this.commitsSinceOldest = 0,
    this.oldestToolCommit,
  });

  Map<String, dynamic> toJson() => {
    'source': {
      'version': sourceVersion,
      'buildNumber': sourceBuildNumber,
      'gitCommit': sourceCommit,
      'buildTime': sourceBuildTime,
      'dartSdkVersion': sourceDartSdk,
    },
    'tools': tools.map((t) => t.toJson()).toList(),
    'repos': repos.map((r) => r.toJson()).toList(),
    'commitsSinceOldest': commitsSinceOldest,
    if (oldestToolCommit != null) 'oldestToolCommit': oldestToolCommit,
  };
}

// =============================================================================
// Executor
// =============================================================================

/// Executor for :status — shows buildkit version, binary status, and git state.
class StatusExecutor extends CommandExecutor {
  /// List of buildkit tools to check.
  static const _toolNames = [
    'buildkit',
    'buildsorter',
    'bumpversion',
    'cleanup',
    'compiler',
    'dependencies',
    'gitbranch',
    'gitcheckout',
    'gitclean',
    'gitcommit',
    'gitcompare',
    'gitmerge',
    'gitprune',
    'gitpull',
    'gitrebase',
    'gitreset',
    'gitsquash',
    'gitstash',
    'gitstatus',
    'gitsync',
    'gittag',
    'gitunstash',
    'publisher',
    'runner',
    'versioner',
  ];

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    return ItemResult.failure(
      path: context.path,
      name: context.name,
      error: 'status uses executeWithoutTraversal',
    );
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final verbose = args.verbose;
    final root = args.scan ?? args.root ?? Directory.current.path;

    // Extract per-command options
    final perCmd = args.commandArgs['status'];
    final options = perCmd?.options ?? {};

    final jsonOutput = options['json'] == true;
    final skipBinaries = options['skip-binaries'] == true;
    final skipGit = options['skip-git'] == true;

    // Collect status information
    final result = await _collectStatus(
      executionRoot: root,
      innerFirstGit: args.innerFirstGit,
      outerFirstGit: args.outerFirstGit,
      skipBinaries: skipBinaries,
      skipGit: skipGit,
      verbose: verbose,
    );

    if (jsonOutput) {
      print(const JsonEncoder.withIndent('  ').convert(result.toJson()));
    } else {
      _printStatus(result, verbose: verbose);
    }

    return const ToolResult.success();
  }

  // ---------------------------------------------------------------------------
  // Data collection
  // ---------------------------------------------------------------------------

  Future<StatusResult> _collectStatus({
    required String executionRoot,
    required bool innerFirstGit,
    required bool outerFirstGit,
    required bool skipBinaries,
    required bool skipGit,
    required bool verbose,
  }) async {
    // Get tool status
    List<ToolStatus> tools = [];
    String? oldestCommit;

    if (!skipBinaries) {
      for (final toolName in _toolNames) {
        final status = await _checkToolVersion(toolName);
        tools.add(status);

        if (status.conformant && status.gitCommit != null) {
          oldestCommit ??= status.gitCommit;
        }
      }
    }

    // Get git repo status
    List<GitRepoStatus> repos = [];
    int commitsSinceOldest = 0;

    if (!skipGit) {
      if (innerFirstGit || outerFirstGit) {
        // Find git repos by scanning for .git directories
        final gitRoots = await _findGitRepos(executionRoot);
        for (final repoPath in gitRoots) {
          final status = await _analyzeGitRepo(repoPath);
          if (status != null) repos.add(status);
        }
      } else {
        final gitRoot = _findGitRoot(executionRoot);
        if (gitRoot != null) {
          final status = await _analyzeGitRepo(gitRoot);
          if (status != null) repos.add(status);
        }
      }

      if (oldestCommit != null && repos.isNotEmpty) {
        commitsSinceOldest = await _countCommitsSince(
          repos.first.path,
          oldestCommit,
        );
      }
    }

    return StatusResult(
      sourceVersion: BuildkitVersionInfo.version,
      sourceBuildNumber: BuildkitVersionInfo.buildNumber,
      sourceCommit: BuildkitVersionInfo.gitCommit,
      sourceBuildTime: BuildkitVersionInfo.buildTime,
      sourceDartSdk: BuildkitVersionInfo.dartSdkVersion,
      tools: tools,
      repos: repos,
      commitsSinceOldest: commitsSinceOldest,
      oldestToolCommit: oldestCommit,
    );
  }

  // ---------------------------------------------------------------------------
  // Git helpers
  // ---------------------------------------------------------------------------

  /// Find the git repository root starting from [startPath].
  String? _findGitRoot(String startPath) {
    var current = startPath;
    while (true) {
      final gitDir = Directory(p.join(current, '.git'));
      final gitFile = File(p.join(current, '.git'));
      if (gitDir.existsSync() || gitFile.existsSync()) return current;

      final parent = p.dirname(current);
      if (parent == current) return null;
      current = parent;
    }
  }

  /// Find all git repositories under a directory.
  Future<List<String>> _findGitRepos(String rootDir) async {
    final finder = GitRepoFinder();
    final repos = await finder.findAll(rootDir);
    return repos.map((f) => f.path).toList();
  }

  /// Check a tool's version by running `<tool> --version`.
  Future<ToolStatus> _checkToolVersion(String toolName) async {
    try {
      final result = await ProcessRunner.run(toolName, ['--version']);

      if (result.exitCode != 0) {
        return ToolStatus(
          name: toolName,
          available: false,
          conformant: false,
          error: 'Exit code ${result.exitCode}',
        );
      }

      final output = result.stdout.trim();
      return _parseVersionOutput(toolName, output);
    } on ProcessException {
      return ToolStatus(
        name: toolName,
        available: false,
        conformant: false,
        error: 'Not found in PATH',
      );
    } catch (e) {
      return ToolStatus(
        name: toolName,
        available: false,
        conformant: false,
        error: e.toString(),
      );
    }
  }

  /// Parse version output.
  ///
  /// Expected: `<tool> <version>+<build>.<commit> (<timestamp>) [Dart <sdk>]`
  ToolStatus _parseVersionOutput(String toolName, String output) {
    final regex = RegExp(
      r'^(.+?)\s+(\d+\.\d+\.\d+)\+(\d+)\.([a-f0-9]+)\s+\(([^)]+)\)\s+\[Dart\s+([^\]]+)\]$',
    );

    final match = regex.firstMatch(output);
    if (match == null) return _parsePartialVersion(toolName, output);

    return ToolStatus(
      name: toolName,
      version: match.group(2),
      buildNumber: match.group(3),
      gitCommit: match.group(4),
      buildTime: match.group(5),
      dartSdkVersion: match.group(6),
      available: true,
      conformant: true,
    );
  }

  /// Try to extract partial version info from non-conformant output.
  ToolStatus _parsePartialVersion(String toolName, String output) {
    String? version;
    String? buildNumber;
    String? gitCommit;

    final versionMatch = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(output);
    if (versionMatch != null) version = versionMatch.group(1);

    final buildMatch = RegExp(r'\+(\d+)').firstMatch(output);
    if (buildMatch != null) buildNumber = buildMatch.group(1);

    final commitMatch = RegExp(r'\.([a-f0-9]{7})').firstMatch(output);
    if (commitMatch != null) gitCommit = commitMatch.group(1);

    return ToolStatus(
      name: toolName,
      version: version,
      buildNumber: buildNumber,
      gitCommit: gitCommit,
      available: true,
      conformant: false,
      error: 'Non-conformant version format',
    );
  }

  /// Analyze a git repository for status.
  Future<GitRepoStatus?> _analyzeGitRepo(String repoPath) async {
    final gitDir = Directory(p.join(repoPath, '.git'));
    final gitFile = File(p.join(repoPath, '.git'));
    if (!gitDir.existsSync() && !gitFile.existsSync()) return null;

    final name = p.basename(repoPath);

    // Get current branch
    String branch;
    try {
      final result = await ProcessRunner.run('git', [
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ], workingDirectory: repoPath);
      branch = result.stdout.trim();
    } catch (_) {
      branch = 'unknown';
    }

    // Get status
    List<String> stagedFiles = [];
    List<String> unstagedFiles = [];
    List<String> untrackedFiles = [];

    try {
      final result = await ProcessRunner.run('git', [
        'status',
        '--porcelain',
      ], workingDirectory: repoPath);
      final lines = result.stdout.split('\n').where((l) => l.isNotEmpty);
      for (final line in lines) {
        if (line.length < 3) continue;
        final indexStatus = line[0];
        final workStatus = line[1];
        final file = line.substring(3);

        if (indexStatus == '?' && workStatus == '?') {
          untrackedFiles.add(file);
        } else {
          if (indexStatus != ' ' && indexStatus != '?') {
            stagedFiles.add(file);
          }
          if (workStatus != ' ' && workStatus != '?') {
            unstagedFiles.add(file);
          }
        }
      }
    } catch (_) {
      // Ignore
    }

    // Get unpushed commits
    List<String> unpushedCommits = [];
    try {
      final result = await ProcessRunner.run('git', [
        'log',
        '@{u}..HEAD',
        '--oneline',
      ], workingDirectory: repoPath);
      if (result.exitCode == 0) {
        unpushedCommits = result.stdout
            .split('\n')
            .where((l) => l.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // No upstream or other error
    }

    return GitRepoStatus(
      path: repoPath,
      name: name,
      branch: branch,
      stagedFiles: stagedFiles,
      unstagedFiles: unstagedFiles,
      untrackedFiles: untrackedFiles,
      unpushedCommits: unpushedCommits,
    );
  }

  /// Count commits since a given commit hash.
  Future<int> _countCommitsSince(String repoPath, String commitHash) async {
    try {
      final result = await ProcessRunner.run('git', [
        'rev-list',
        '--count',
        '$commitHash..HEAD',
      ], workingDirectory: repoPath);
      if (result.exitCode == 0) {
        return int.tryParse(result.stdout.trim()) ?? 0;
      }
    } catch (_) {
      // Ignore
    }
    return 0;
  }

  // ---------------------------------------------------------------------------
  // Display
  // ---------------------------------------------------------------------------

  void _printStatus(StatusResult result, {required bool verbose}) {
    print('╔═══════════════════════════════════════════════════════════════╗');
    print('║                     BUILDKIT STATUS                           ║');
    print('╚═══════════════════════════════════════════════════════════════╝');
    print('');
    print('Source Version');
    print('──────────────');
    print(
      '  Version:      ${result.sourceVersion}+${result.sourceBuildNumber}',
    );
    print('  Git Commit:   ${result.sourceCommit}');
    print('  Build Time:   ${result.sourceBuildTime}');
    print('  Dart SDK:     ${result.sourceDartSdk}');
    print('');

    if (result.tools.isNotEmpty) {
      print('Binary Status');
      print('─────────────');

      final current = <ToolStatus>[];
      final outdated = <ToolStatus>[];
      final unavailable = <ToolStatus>[];
      final nonConformant = <ToolStatus>[];

      for (final tool in result.tools) {
        if (!tool.available) {
          unavailable.add(tool);
        } else if (!tool.conformant) {
          nonConformant.add(tool);
        } else if (tool.matchesSource(
          result.sourceVersion,
          result.sourceBuildNumber,
          result.sourceCommit,
        )) {
          current.add(tool);
        } else {
          outdated.add(tool);
        }
      }

      if (current.isNotEmpty) {
        print(
          '  ✓ Current (${current.length}): '
          '${current.map((t) => t.name).join(', ')}',
        );
      }
      if (outdated.isNotEmpty) {
        print('  ⚠ Outdated (${outdated.length}):');
        for (final tool in outdated) {
          print(
            '    ${tool.name}: '
            '${tool.version}+${tool.buildNumber}.${tool.gitCommit}',
          );
        }
      }
      if (unavailable.isNotEmpty) {
        print(
          '  ✗ Unavailable (${unavailable.length}): '
          '${unavailable.map((t) => t.name).join(', ')}',
        );
      }
      if (nonConformant.isNotEmpty) {
        print('  ? Non-conformant (${nonConformant.length}):');
        for (final tool in nonConformant) {
          print('    ${tool.name}: ${tool.error}');
        }
      }
      print('');
    }

    if (result.repos.isNotEmpty) {
      print('Git Status');
      print('──────────');

      final reposWithChanges = result.repos.where((r) => r.hasChanges).toList();
      final reposWithUnpushed = result.repos
          .where((r) => r.hasUnpushed)
          .toList();

      if (reposWithChanges.isEmpty && reposWithUnpushed.isEmpty) {
        print('  All repositories are clean and up to date.');
      } else {
        if (reposWithChanges.isNotEmpty) {
          final totalFiles = reposWithChanges.fold<int>(
            0,
            (sum, r) => sum + r.totalChanges,
          );
          print(
            '  Pending Changes: ${reposWithChanges.length} repo(s), '
            '$totalFiles file(s)',
          );

          if (verbose) {
            for (final repo in reposWithChanges) {
              print('    ${repo.name} (${repo.branch}):');
              for (final f in repo.stagedFiles) {
                print('      [staged] $f');
              }
              for (final f in repo.unstagedFiles) {
                print('      [modified] $f');
              }
              for (final f in repo.untrackedFiles) {
                print('      [untracked] $f');
              }
            }
          } else {
            print(
              '    (Specify --verbose to see the $totalFiles modified files)',
            );
          }
          print('');
        }

        if (reposWithUnpushed.isNotEmpty) {
          final totalCommits = reposWithUnpushed.fold<int>(
            0,
            (sum, r) => sum + r.unpushedCommits.length,
          );
          print(
            '  Unpushed Commits: ${reposWithUnpushed.length} repo(s), '
            '$totalCommits commit(s)',
          );

          if (verbose) {
            for (final repo in reposWithUnpushed) {
              print('    ${repo.name} (${repo.branch}):');
              for (final commit in repo.unpushedCommits) {
                print('      $commit');
              }
            }
          } else {
            print(
              '    (Specify --verbose to see the $totalCommits '
              'unpushed commits)',
            );
          }
        }
      }

      if (result.commitsSinceOldest > 0 && result.oldestToolCommit != null) {
        print('');
        print(
          '  Note: ${result.commitsSinceOldest} commit(s) since oldest '
          'binary (${result.oldestToolCommit})',
        );
      }
    }
  }
}
