/// Native v2 executor for the :bumppubspec command.
///
/// Updates version constraints in pubspec.yaml files for specified packages.
/// Replaces the v1 BumpPubspecTool that extended ToolBase.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../../project_scanner.dart';

/// Executor for :bumppubspec — updates package version references in
/// pubspec.yaml files across the workspace.
///
/// Options (via per-command args):
/// - `refs`: Package names to update (comma-separated).
///   If omitted, discovers all publishable packages.
/// - `replace-any`: Replace "any" constraints with current version.
/// - `replace-path`: Replace path: dependencies with current version.
/// - `replace-git`: Replace git: dependencies with current version.
class BumpPubspecExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    return ItemResult.failure(
      path: context.path,
      name: context.name,
      error: 'bumppubspec uses executeWithoutTraversal',
    );
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final verbose = args.verbose;
    final dryRun = args.dryRun;
    final listMode = args.listOnly;
    final showMode = args.dumpConfig;
    final root = args.scan ?? args.root ?? Directory.current.path;

    // Extract per-command options
    final perCmd = args.commandArgs['bumppubspec'];
    final options = perCmd?.options ?? {};

    final refsOption = options['refs'] as String?;
    final replaceAny = options['replace-any'] == true;
    final replacePath = options['replace-path'] == true;
    final replaceGit = options['replace-git'] == true;

    // Get package references
    List<String> packageRefs;
    if (refsOption != null && refsOption.isNotEmpty) {
      packageRefs = refsOption.split(',').map((s) => s.trim()).toList();
    } else {
      // Discover publishable packages
      if (verbose) {
        print('No --refs specified, discovering publishable packages...');
      }
      final scanner = WorkspaceScanner(verbose: verbose);
      final publishable = await scanner.findPublishable(root);
      packageRefs = publishable.map((p) => p.projectName).toList();
      if (packageRefs.isEmpty) {
        print('No publishable packages found in workspace');
        return const ToolResult.failure('No publishable packages found');
      }
      if (verbose) {
        print(
          'Found ${packageRefs.length} publishable package(s): '
          '${packageRefs.join(", ")}',
        );
      }
    }

    // Find package versions
    final packageVersions = <String, String>{};
    final projects = scanForDartProjects(
      root,
      recursive: true,
      verbose: verbose,
    );

    for (final packageName in packageRefs) {
      final version = _findPackageVersion(packageName, projects);
      if (version != null) {
        packageVersions[packageName] = version;
        if (verbose) {
          print('Found $packageName: $version');
        }
      } else {
        print('Warning: Could not find version for package: $packageName');
      }
    }

    if (packageVersions.isEmpty) {
      return ToolResult.failure(
        'No package versions found for: ${packageRefs.join(", ")}',
      );
    }

    // Find projects to update
    final targetProjects = _resolveProjects(args, root);

    if (targetProjects.isEmpty) {
      print('No projects found.');
      return const ToolResult.failure('No projects found');
    }

    // List mode
    if (listMode) {
      print('Projects with pubspec.yaml:');
      for (final project in targetProjects) {
        if (File(p.join(project, 'pubspec.yaml')).existsSync()) {
          print('  ${p.relative(project, from: root)}');
        }
      }
      return const ToolResult.success();
    }

    // Show mode
    if (showMode) {
      for (final project in targetProjects) {
        if (!File(p.join(project, 'pubspec.yaml')).existsSync()) continue;
        final changes = _checkProjectForChanges(
          project,
          packageVersions,
          replaceAny: replaceAny,
          replacePath: replacePath,
          replaceGit: replaceGit,
        );
        if (changes.isNotEmpty) {
          print('${p.relative(project, from: root)}:');
          for (final change in changes) {
            print('  $change');
          }
        }
      }
      return const ToolResult.success();
    }

    // Process each project
    var updated = 0;
    var skipped = 0;
    var errors = false;

    for (final projectPath in targetProjects) {
      if (!File(p.join(projectPath, 'pubspec.yaml')).existsSync()) {
        skipped++;
        continue;
      }

      final result = _updateProject(
        projectPath,
        packageVersions,
        root,
        replaceAny: replaceAny,
        replacePath: replacePath,
        replaceGit: replaceGit,
        dryRun: dryRun,
        verbose: verbose,
      );
      if (result > 0) {
        updated++;
      } else if (result < 0) {
        errors = true;
      }
    }

    if (updated > 0 || skipped > 0) {
      print('');
      print('Pubspec update summary: $updated updated, $skipped skipped');
    }

    return errors
        ? const ToolResult.failure('Some projects had errors')
        : const ToolResult.success();
  }

  // ---------------------------------------------------------------------------
  // Project scanning
  // ---------------------------------------------------------------------------

  /// Resolve which projects to process based on CliArgs.
  List<String> _resolveProjects(CliArgs args, String root) {
    if (args.projectPatterns.isNotEmpty) {
      return resolveProjectPatterns(
        args.projectPatterns.join(','),
        basePath: root,
      );
    }
    // Default: scan from root recursively
    final scanDir = args.scan ?? root;
    return scanForDartProjects(
      scanDir,
      recursive: args.effectiveRecursive,
      verbose: args.verbose,
    );
  }

  // ---------------------------------------------------------------------------
  // Version discovery
  // ---------------------------------------------------------------------------

  /// Find the version of a package by scanning project pubspec.yaml files.
  String? _findPackageVersion(String packageName, List<String> projects) {
    for (final project in projects) {
      final pubspecPath = p.join(project, 'pubspec.yaml');
      final file = File(pubspecPath);
      if (!file.existsSync()) continue;

      try {
        final content = file.readAsStringSync();
        final yaml = loadYaml(content);
        if (yaml is YamlMap && yaml['name'] == packageName) {
          final version = yaml['version'];
          if (version is String) return version;
        }
      } catch (_) {
        // Skip malformed pubspec files
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Pubspec modification
  // ---------------------------------------------------------------------------

  /// Check what changes would be made to a project.
  List<String> _checkProjectForChanges(
    String projectPath,
    Map<String, String> packageVersions, {
    required bool replaceAny,
    required bool replacePath,
    required bool replaceGit,
  }) {
    final changes = <String>[];
    final pubspecPath = p.join(projectPath, 'pubspec.yaml');

    if (!File(pubspecPath).existsSync()) return changes;

    final content = File(pubspecPath).readAsStringSync();
    final yaml = loadYaml(content) as YamlMap?;
    if (yaml == null) return changes;

    void checkDependencies(YamlMap? deps, String section) {
      if (deps == null) return;
      for (final entry in deps.entries) {
        final name = entry.key as String;
        if (!packageVersions.containsKey(name)) continue;

        final value = entry.value;
        final newVersion = '^${packageVersions[name]}';

        if (value == null || value == 'any') {
          if (replaceAny) {
            changes.add('$section $name: any → $newVersion');
          }
        } else if (value is YamlMap) {
          if (value.containsKey('path') && replacePath) {
            changes.add('$section $name: path: ${value['path']} → $newVersion');
          } else if (value.containsKey('git') && replaceGit) {
            changes.add('$section $name: git: ... → $newVersion');
          }
        } else if (value is String && value != newVersion) {
          changes.add('$section $name: $value → $newVersion');
        }
      }
    }

    checkDependencies(yaml['dependencies'] as YamlMap?, 'dependencies:');
    checkDependencies(
      yaml['dev_dependencies'] as YamlMap?,
      'dev_dependencies:',
    );

    return changes;
  }

  /// Update a project's pubspec.yaml.
  ///
  /// Returns: >0 if updated, 0 if no changes needed, <0 if error.
  int _updateProject(
    String projectPath,
    Map<String, String> packageVersions,
    String executionRoot, {
    required bool replaceAny,
    required bool replacePath,
    required bool replaceGit,
    required bool dryRun,
    required bool verbose,
  }) {
    final pubspecPath = p.join(projectPath, 'pubspec.yaml');
    if (!File(pubspecPath).existsSync()) return 0;

    final content = File(pubspecPath).readAsStringSync();
    final editor = YamlEditor(content);
    var changeCount = 0;

    void updateDependencies(String section) {
      final yaml = loadYaml(content) as YamlMap?;
      if (yaml == null) return;

      final deps = yaml[section] as YamlMap?;
      if (deps == null) return;

      for (final entry in deps.entries) {
        final name = entry.key as String;
        if (!packageVersions.containsKey(name)) continue;

        final value = entry.value;
        final newVersion = '^${packageVersions[name]}';
        var shouldUpdate = false;
        var oldValue = '';

        if (value == null || value == 'any') {
          if (replaceAny) {
            shouldUpdate = true;
            oldValue = value?.toString() ?? 'null';
          }
        } else if (value is YamlMap) {
          if (value.containsKey('path') && replacePath) {
            shouldUpdate = true;
            oldValue = 'path: ${value['path']}';
          } else if (value.containsKey('git') && replaceGit) {
            shouldUpdate = true;
            oldValue = 'git: ...';
          }
        } else if (value is String) {
          if (value != newVersion) {
            shouldUpdate = true;
            oldValue = value;
          }
        }

        if (shouldUpdate) {
          try {
            editor.update([section, name], newVersion);
            changeCount++;

            final relProjectPath = p.relative(projectPath, from: executionRoot);
            if (dryRun) {
              print('[DRY-RUN] $relProjectPath: $name $oldValue → $newVersion');
            } else if (verbose) {
              print('$relProjectPath: $name $oldValue → $newVersion');
            }
          } catch (e) {
            print('Error updating $name in $projectPath: $e');
          }
        }
      }
    }

    updateDependencies('dependencies');
    updateDependencies('dev_dependencies');

    if (changeCount > 0 && !dryRun) {
      try {
        File(pubspecPath).writeAsStringSync(editor.toString());
        print(
          'Updated: ${p.relative(projectPath, from: executionRoot)} '
          '($changeCount changes)',
        );
      } catch (e) {
        print('Error writing $pubspecPath: $e');
        return -1;
      }
    }

    return changeCount;
  }
}
