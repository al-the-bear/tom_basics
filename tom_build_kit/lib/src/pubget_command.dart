import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart';

import 'project_scanner.dart';

/// Result of a pub get execution for a single project.
class PubGetResult {
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

  /// Whether the output indicates updates are available.
  bool get hasUpdates => stdout.contains('available)') && !hasUpgrades;

  /// Whether the output indicates incompatible upgrades are available.
  bool get hasUpgrades =>
      stdout.contains('incompatible with dependency constraints');

  /// Whether there was an error.
  bool get hasError => !success || stderr.isNotEmpty;

  PubGetResult({
    required this.projectPath,
    required this.projectName,
    required this.success,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });
}

/// Executes `dart pub get` across multiple projects.
///
/// Collects all output and displays it at the end, with filtering options.
class PubGetCommand {
  final String rootPath;
  final bool verbose;

  PubGetCommand({required this.rootPath, required this.verbose});

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
      'updates',
      abbr: 'u',
      negatable: false,
      help: 'Only show projects with available updates',
    )
    ..addFlag(
      'upgrades',
      abbr: 'U',
      negatable: false,
      help: 'Only show projects with incompatible upgrades',
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
    print('Pub Get Command - Run dart pub get across projects');
    print('');
    print('Usage: buildkit :pubget [options]');
    print(
      '       buildkit :pubgetall  # Shortcut: -R <workspace> --scan <workspace> --recursive',
    );
    print('');
    print('Options:');
    print(parser.usage);
    print('');
    print('Examples:');
    print('  buildkit :pubget --scan . --recursive');
    print('  buildkit :pubget -s . -R --errors');
    print('  buildkit :pubget --project tom_* --updates');
    print('  buildkit :pubgetall             # pub get in entire workspace');
    print('  buildkit :pubgetall --errors    # only show projects with errors');
  }

  /// Execute pub get across projects.
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
    final showUpdates = results['updates'] as bool;
    final showUpgrades = results['upgrades'] as bool;
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
        '[DRY RUN] Would run pub get on '
        '${projectPaths.length} project(s)',
      );
      print('');
      for (final projectPath in projectPaths) {
        final relativePath = p.relative(projectPath, from: rootPath);
        final projectName = _getProjectName(projectPath);
        print('  [$projectName] dart pub get  ($relativePath)');
      }
      print('');
      print('[DRY RUN] ${projectPaths.length} project(s) would be processed');
      return true;
    }

    print('Running pub get on ${projectPaths.length} project(s)...');
    print('');

    // Execute pub get per-project with streaming output
    var successCount = 0;
    var failCount = 0;
    var updateCount = 0;
    var upgradeCount = 0;
    var processedCount = 0;

    for (final projectPath in projectPaths) {
      final relativePath = p.relative(projectPath, from: rootPath);
      final projectName = _getProjectName(projectPath);
      processedCount++;

      final result = await _runPubGet(projectPath, relativePath, projectName);

      // Track counts
      if (result.success) {
        successCount++;
      } else {
        failCount++;
      }
      if (result.hasUpdates) updateCount++;
      if (result.hasUpgrades) upgradeCount++;

      // Stream output immediately — apply filters
      final show = _shouldShow(
        result,
        showErrors: showErrors,
        showUpdates: showUpdates,
        showUpgrades: showUpgrades,
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
    print('Pub Get Summary');
    print('=' * 60);
    print('Total projects: ${projectPaths.length}');
    print('Succeeded: $successCount');
    if (failCount > 0) print('Failed: $failCount');
    if (updateCount > 0) print('With updates available: $updateCount');
    if (upgradeCount > 0) print('With incompatible upgrades: $upgradeCount');

    return failCount == 0;
  }

  /// Run dart pub get in a project directory.
  Future<PubGetResult> _runPubGet(
    String projectPath,
    String relativePath,
    String projectName,
  ) async {
    try {
      final result = await ProcessRunner.run(
        'dart',
        ['pub', 'get'],
        workingDirectory: projectPath,
        runInShell: true,
      );

      return PubGetResult(
        projectPath: relativePath,
        projectName: projectName,
        success: result.exitCode == 0,
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
      );
    } catch (e) {
      return PubGetResult(
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
    PubGetResult result, {
    required bool showErrors,
    required bool showUpdates,
    required bool showUpgrades,
  }) {
    // No filters → show all
    if (!showErrors && !showUpdates && !showUpgrades) return true;
    if (showErrors && result.hasError) return true;
    if (showUpdates && result.hasUpdates) return true;
    if (showUpgrades && result.hasUpgrades) return true;
    return false;
  }

  /// Display a single result immediately (streaming output).
  void _displayResult(
    PubGetResult result,
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
