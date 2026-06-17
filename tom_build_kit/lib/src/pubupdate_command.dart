import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart';

import 'project_scanner.dart';

/// Result of a pub upgrade execution for a single project.
class PubUpdateResult {
  /// The project path (relative to workspace).
  final String projectPath;

  /// The project name from pubspec.yaml.
  final String projectName;

  /// Whether the command succeeded.
  final bool success;

  /// Standard output from the command.
  final String stdout;

  /// Standard error from the command.
  final String stderr;

  /// Exit code from the command.
  final int exitCode;

  /// Whether the output indicates packages were upgraded.
  bool get hasChanges =>
      stdout.contains('Changed ') || stdout.contains('Upgraded ');

  /// Whether there was an error.
  bool get hasError => !success || stderr.isNotEmpty;

  PubUpdateResult({
    required this.projectPath,
    required this.projectName,
    required this.success,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });
}

/// Executes `dart pub upgrade` across multiple projects.
///
/// Collects all output and displays it at the end, with filtering options.
class PubUpdateCommand {
  final String rootPath;
  final bool verbose;

  PubUpdateCommand({required this.rootPath, required this.verbose});

  /// Parse command arguments.
  static ArgParser get parser => ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help')
    ..addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: 'Show what would be done without executing',
    )
    ..addFlag(
      'errors',
      abbr: 'e',
      negatable: false,
      help: 'Only show projects with errors',
    )
    ..addFlag(
      'changes',
      abbr: 'c',
      negatable: false,
      help: 'Only show projects with changed packages',
    )
    ..addFlag(
      'major-versions',
      negatable: false,
      help: 'Allow upgrading to latest resolvable versions (major versions)',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show detailed output',
    )
    ..addFlag(
      'recursive',
      abbr: 'R',
      negatable: true,
      defaultsTo: false,
      help: 'Scan directories recursively (use --no-recursive to disable)',
    )
    ..addOption(
      'scan',
      abbr: 's',
      help: 'Scan directory for projects to process',
    )
    ..addOption(
      'project',
      abbr: 'p',
      help: 'Project(s) to process (comma-separated, globs supported)',
    );

  /// Print usage help.
  static void printUsage() {
    print('Pub Update Command - Run dart pub upgrade across projects');
    print('');
    print('Usage: buildkit :pubupdate [options]');
    print(
      '       buildkit :pubupdateall  # Shortcut: -R <workspace> --scan <workspace> --recursive',
    );
    print('');
    print('Options:');
    print(parser.usage);
    print('');
    print('Examples:');
    print('  buildkit :pubupdate --scan . --recursive');
    print('  buildkit :pubupdate -s . -R --errors');
    print('  buildkit :pubupdate --project tom_* --changes');
    print('  buildkit :pubupdate --major-versions');
    print(
      '  buildkit :pubupdateall             # pub upgrade in entire workspace',
    );
    print(
      '  buildkit :pubupdateall --errors    # only show projects with errors',
    );
  }

  /// Execute pub upgrade across projects.
  ///
  /// Returns true if all projects succeeded, false if any failed.
  /// Streams output per-project so errors are visible immediately.
  /// Respects `--dry-run` — prints what would be executed without running.
  Future<bool> execute(List<String> args) async {
    ArgResults results;
    try {
      results = parser.parse(args);
    } catch (e) {
      print('Error parsing arguments: $e');
      printUsage();
      return false;
    }

    if (results['help'] as bool) {
      printUsage();
      return true;
    }

    final dryRun = results['dry-run'] as bool;
    final showErrors = results['errors'] as bool;
    final showChanges = results['changes'] as bool;
    final majorVersions = results['major-versions'] as bool;
    final isVerbose = verbose || (results['verbose'] as bool);
    final recursive = results['recursive'] as bool;
    final scanPath = results['scan'] as String?;
    final projectArg = results['project'] as String?;

    // Determine projects to process
    final currentDir = Directory.current.path;
    List<String> projectPaths;

    if (scanPath != null) {
      final scanDir = p.isAbsolute(scanPath)
          ? scanPath
          : p.join(currentDir, scanPath);
      projectPaths = scanForDartProjects(
        scanDir,
        recursive: recursive,
        verbose: isVerbose,
      );
    } else if (projectArg != null) {
      projectPaths = resolveProjectPatterns(projectArg, basePath: currentDir);
    } else {
      // Default: current directory
      projectPaths = [currentDir];
    }

    if (projectPaths.isEmpty) {
      print('No projects found.');
      return false;
    }

    if (dryRun) {
      print(
        '[DRY RUN] Would run pub upgrade on '
        '${projectPaths.length} project(s)',
      );
      if (majorVersions) print('[DRY RUN] with --major-versions');
      print('');
      for (final projectPath in projectPaths) {
        final relativePath = p.relative(projectPath, from: rootPath);
        final projectName = _getProjectName(projectPath);
        final cmd = majorVersions
            ? 'dart pub upgrade --major-versions'
            : 'dart pub upgrade';
        print('  [$projectName] $cmd  ($relativePath)');
      }
      print('');
      print('[DRY RUN] ${projectPaths.length} project(s) would be processed');
      return true;
    }

    print('Running pub upgrade on ${projectPaths.length} project(s)...');
    if (majorVersions) {
      print('(with --major-versions)');
    }
    print('');

    // Execute pub upgrade per-project with streaming output
    var successCount = 0;
    var failCount = 0;
    var changesCount = 0;
    var processedCount = 0;

    for (final projectPath in projectPaths) {
      final relativePath = p.relative(projectPath, from: rootPath);
      final projectName = _getProjectName(projectPath);
      processedCount++;

      final result = await _runPubUpgrade(
        projectPath,
        relativePath,
        projectName,
        majorVersions: majorVersions,
      );

      // Track counts
      if (result.success) {
        successCount++;
      } else {
        failCount++;
      }
      if (result.hasChanges) changesCount++;

      // Stream output immediately — apply filters
      final show = _shouldShow(
        result,
        showErrors: showErrors,
        showChanges: showChanges,
      );
      if (show) {
        _displayResult(result, isVerbose, processedCount, projectPaths.length);
      } else if (!result.success) {
        // Always show failures even when filtering
        _displayResult(result, isVerbose, processedCount, projectPaths.length);
      } else {
        // Compact progress for filtered-out successes
        print(
          '  ($processedCount/${projectPaths.length}) '
          '$projectName ✓',
        );
      }
    }

    // Summary
    print('');
    print('=' * 60);
    print('Pub Update Summary');
    print('=' * 60);
    print('Total projects: ${projectPaths.length}');
    print('Succeeded: $successCount');
    if (failCount > 0) print('Failed: $failCount');
    if (changesCount > 0) print('With package changes: $changesCount');

    return failCount == 0;
  }

  /// Run dart pub upgrade in a project directory.
  Future<PubUpdateResult> _runPubUpgrade(
    String projectPath,
    String relativePath,
    String projectName, {
    required bool majorVersions,
  }) async {
    try {
      final args = ['pub', 'upgrade'];
      if (majorVersions) {
        args.add('--major-versions');
      }

      final result = await ProcessRunner.run(
        'dart',
        args,
        workingDirectory: projectPath,
        runInShell: true,
      );

      return PubUpdateResult(
        projectPath: relativePath,
        projectName: projectName,
        success: result.exitCode == 0,
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
      );
    } catch (e) {
      return PubUpdateResult(
        projectPath: relativePath,
        projectName: projectName,
        success: false,
        stdout: '',
        stderr: 'Error: $e',
        exitCode: -1,
      );
    }
  }

  /// Get project name from pubspec.yaml.
  String _getProjectName(String projectPath) {
    final pubspecFile = File(p.join(projectPath, 'pubspec.yaml'));
    if (pubspecFile.existsSync()) {
      final content = pubspecFile.readAsStringSync();
      final nameMatch = RegExp(
        r'^name:\s*(.+)$',
        multiLine: true,
      ).firstMatch(content);
      if (nameMatch != null) {
        return nameMatch.group(1)?.trim() ?? p.basename(projectPath);
      }
    }
    return p.basename(projectPath);
  }

  /// Check if a result should be shown based on filter options.
  bool _shouldShow(
    PubUpdateResult result, {
    required bool showErrors,
    required bool showChanges,
  }) {
    // No filters → show all
    if (!showErrors && !showChanges) return true;
    if (showErrors && result.hasError) return true;
    if (showChanges && result.hasChanges) return true;
    return false;
  }

  /// Display a single result immediately (streaming output).
  void _displayResult(
    PubUpdateResult result,
    bool isVerbose,
    int current,
    int total,
  ) {
    final status = result.success ? '✓' : '✗ FAILED';
    print('  ($current/$total) ${result.projectName}  $status');
    print('   ${result.projectPath}');

    if (result.stdout.isNotEmpty) {
      final lines = result.stdout
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      for (final line in lines) {
        print('    $line');
      }
    }

    if (result.stderr.isNotEmpty) {
      print('    STDERR:');
      final lines = result.stderr
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      for (final line in lines) {
        print('    $line');
      }
    }
  }
}
