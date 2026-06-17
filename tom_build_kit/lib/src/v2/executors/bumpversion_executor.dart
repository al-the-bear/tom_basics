/// Native v2 executor for the bumpversion command.
///
/// Bumps pubspec.yaml versions across projects. All projects get a patch
/// bump by default; use --minor/--major to specify projects for different
/// bump types. Optionally runs the versioner after bumping.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:yaml/yaml.dart';

import 'versioner_executor.dart';

// =============================================================================
// Bump Types
// =============================================================================

/// The type of version bump.
enum BumpType {
  major,
  minor,
  patch;

  @override
  String toString() => name;
}

// =============================================================================
// BumpVersion Executor
// =============================================================================

/// Native v2 executor for the `:bumpversion` command.
///
/// Uses `requiresTraversal: false` because it needs post-traversal processing
/// (optionally running versioner after all bumps). Performs its own traversal
/// via [BuildBase.traverse].
class BumpVersionExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    return ItemResult.failure(
      path: context.path,
      name: context.name,
      error: ':bumpversion uses executeWithoutTraversal',
    );
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final cmdOpts = _getCommandOptions(args);

    // Parse minor/major project lists
    final minorProjects = _expandProjectList(cmdOpts['minor']);
    final majorProjects = _expandProjectList(cmdOpts['major']);
    final runVersioner = cmdOpts['versioner'] == true;

    final executionRoot = args.root ?? Directory.current.path;

    // Build traversal info from CLI args
    final traversalInfo = args.toProjectTraversalInfo(executionRoot: executionRoot);

    // List mode
    if (args.listOnly) {
      print('Projects with pubspec.yaml:');
      await BuildBase.traverse(
        info: traversalInfo,
        worksWithNatures: {DartProjectFolder},
        run: (context) async {
          if (File('${context.path}/pubspec.yaml').existsSync()) {
            print('  ${context.relativePath}');
          }
          return true;
        },
      );
      return const ToolResult.success();
    }

    // Bump each project
    final results = <ItemResult>[];
    var bumped = 0;
    var skipped = 0;

    await BuildBase.traverse(
      info: traversalInfo,
      worksWithNatures: {DartProjectFolder},
      run: (context) async {
        final pubspecFile = File('${context.path}/pubspec.yaml');
        if (!pubspecFile.existsSync()) {
          skipped++;
          return true;
        }

        final bumpType = _determineBumpType(
          context.name,
          context.path,
          minorProjects,
          majorProjects,
        );

        // Show mode
        if (args.dumpConfig) {
          final version = _readCurrentVersion(context.path);
          if (version != null) {
            print('  ${context.relativePath}: '
                '$version -> ${_bumpVersionString(version, bumpType)} ($bumpType)');
          }
          return true;
        }

        final success = _bumpProject(
          context.path,
          bumpType,
          executionRoot,
          verbose: args.verbose,
          dryRun: args.dryRun,
        );

        if (success) {
          bumped++;
          results.add(ItemResult.success(
            path: context.path,
            name: context.name,
            message: 'bumped ($bumpType)',
          ));
        } else {
          results.add(ItemResult.failure(
            path: context.path,
            name: context.name,
            error: 'bump failed',
          ));
        }
        return true;
      },
    );

    if (bumped > 0 || skipped > 0) {
      print('');
      print('Version bump summary: $bumped bumped, $skipped skipped');
    }

    // Run versioner if requested
    if (runVersioner && results.every((r) => r.success)) {
      print('');
      print('________ Running versioner');
      print('');

      final versionerExecutor = VersionerExecutor();
      await BuildBase.traverse(
        info: traversalInfo,
        worksWithNatures: {DartProjectFolder},
        run: (context) async {
          final result = await versionerExecutor.execute(context, args);
          return result.success;
        },
      );
    }

    return ToolResult.fromItems(results);
  }

  /// Get the per-command options for the bumpversion command.
  Map<String, dynamic> _getCommandOptions(CliArgs args) {
    for (final cmdName in args.commands) {
      if (cmdName == 'bumpversion' || cmdName == 'bump') {
        final cmdArgs = args.commandArgs[cmdName];
        if (cmdArgs != null && cmdArgs.options.isNotEmpty) {
          return cmdArgs.options;
        }
      }
    }
    return args.extraOptions;
  }

  /// Expand a list of project arguments, splitting comma-separated values.
  Set<String> _expandProjectList(dynamic value) {
    final result = <String>{};
    if (value == null) return result;

    List<String> items;
    if (value is String) {
      items = [value];
    } else if (value is List) {
      items = value.map((e) => e.toString()).toList();
    } else {
      return result;
    }

    for (final arg in items) {
      for (final name in arg.split(',')) {
        final trimmed = name.trim();
        if (trimmed.isNotEmpty) result.add(trimmed);
      }
    }
    return result;
  }

  /// Determine bump type for a project.
  BumpType _determineBumpType(
    String projectName,
    String projectPath,
    Set<String> minorProjects,
    Set<String> majorProjects,
  ) {
    if (_matchesProjectList(projectName, projectPath, majorProjects)) {
      return BumpType.major;
    }
    if (_matchesProjectList(projectName, projectPath, minorProjects)) {
      return BumpType.minor;
    }
    return BumpType.patch;
  }

  /// Check if a project matches any entry in a project list.
  bool _matchesProjectList(
    String projectName,
    String projectPath,
    Set<String> projectList,
  ) {
    if (projectList.contains(projectName)) return true;
    for (final pattern in projectList) {
      if (projectPath.endsWith(pattern)) return true;
    }
    return false;
  }

  /// Read the current version from pubspec.yaml.
  String? _readCurrentVersion(String projectPath) {
    final pubspecFile = File('$projectPath/pubspec.yaml');
    if (!pubspecFile.existsSync()) return null;

    try {
      final content = pubspecFile.readAsStringSync();
      final yaml = loadYaml(content) as YamlMap?;
      return yaml?['version']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Bump the version in a project's pubspec.yaml.
  bool _bumpProject(
    String projectPath,
    BumpType bumpType,
    String basePath, {
    required bool verbose,
    required bool dryRun,
  }) {
    final pubspecFile = File('$projectPath/pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      print('  Error: No pubspec.yaml in ${p.relative(projectPath, from: basePath)}');
      return false;
    }

    try {
      final content = pubspecFile.readAsStringSync();
      final yaml = loadYaml(content) as YamlMap?;
      if (yaml == null || !yaml.containsKey('version')) {
        if (verbose) {
          print('  Skipping ${p.basename(projectPath)}: no version field');
        }
        return true;
      }

      final currentVersion = yaml['version'].toString();
      final newVersion = _bumpVersionString(currentVersion, bumpType);

      if (dryRun) {
        print('  [DRY RUN] ${p.basename(projectPath)}: '
            '$currentVersion -> $newVersion ($bumpType)');
        return true;
      }

      // Update pubspec.yaml
      final newContent = _updateVersionInYaml(content, newVersion);
      pubspecFile.writeAsStringSync(newContent);

      // Reset build counter
      _resetBuildCounter(projectPath, verbose: verbose);

      print('  ${p.basename(projectPath)}: $currentVersion -> $newVersion ($bumpType)');
      return true;
    } catch (e) {
      print('  Error bumping ${p.basename(projectPath)}: $e');
      return false;
    }
  }

  /// Bump a version string.
  String _bumpVersionString(String version, BumpType type) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version);
    if (match == null) return version;

    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    final patch = int.parse(match.group(3)!);

    switch (type) {
      case BumpType.major:
        return '${major + 1}.0.0';
      case BumpType.minor:
        return '$major.${minor + 1}.0';
      case BumpType.patch:
        return '$major.$minor.${patch + 1}';
    }
  }

  /// Update the version field in YAML content while preserving formatting.
  String _updateVersionInYaml(String content, String newVersion) {
    final versionRegex = RegExp(r'^version:\s*[\S]+', multiLine: true);
    return content.replaceFirst(versionRegex, 'version: $newVersion');
  }

  /// Reset the build counter in tom_build_state.json.
  void _resetBuildCounter(String projectPath, {required bool verbose}) {
    final stateFile = File('$projectPath/tom_build_state.json');
    try {
      stateFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'buildNumber': 0,
          'lastBuild': DateTime.now().toUtc().toIso8601String(),
          'lastVersionBump': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      if (verbose) print('    Build counter reset to 0');
    } catch (e) {
      if (verbose) print('    Warning: Could not reset build counter: $e');
    }
  }
}
