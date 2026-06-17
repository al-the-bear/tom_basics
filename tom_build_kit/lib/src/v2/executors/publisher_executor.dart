/// Native v2 executor for the publisher command.
///
/// Checks publishing readiness for Dart projects: uncommitted changes,
/// unpushed commits, path dependencies, missing files.
library;

import 'dart:io';

import 'package:tom_build_base/tom_build_base.dart' show ProcessRunner;
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:yaml/yaml.dart';

/// Native v2 executor for the `:publisher` command.
class PublisherExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final projectPath = context.path;
    final pubspecFile = File('$projectPath/pubspec.yaml');

    if (!pubspecFile.existsSync()) {
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'skipped (no pubspec.yaml)',
      );
    }

    final cmdOpts = _getCmdOpts(args);
    final showAll = cmdOpts['show-all'] == true;

    try {
      final yaml = loadYaml(pubspecFile.readAsStringSync()) as YamlMap?;
      if (yaml == null) {
        return ItemResult.failure(
          path: projectPath,
          name: context.name,
          error: 'invalid pubspec.yaml',
        );
      }

      final projectName = yaml['name']?.toString() ?? context.name;
      final publishTo = yaml['publish_to']?.toString();

      // Skip publish_to: none unless --show-all
      if (publishTo == 'none' && !showAll) {
        return ItemResult.success(
          path: projectPath,
          name: context.name,
          message: 'publish_to: none (skipped)',
        );
      }

      final issues = <String>[];

      // Check publish_to: none
      if (publishTo == 'none') {
        issues.add('publish_to: none');
      }

      // Check for path dependencies
      final deps = yaml['dependencies'] as YamlMap?;
      if (deps != null) {
        for (final entry in deps.entries) {
          final value = entry.value;
          if (value is YamlMap && value.containsKey('path')) {
            issues.add('path dep: ${entry.key}');
          }
        }
      }

      // Check for missing files
      if (!File('$projectPath/README.md').existsSync()) {
        issues.add('missing README.md');
      }
      if (!File('$projectPath/LICENSE').existsSync()) {
        issues.add('missing LICENSE');
      }
      if (!File('$projectPath/CHANGELOG.md').existsSync()) {
        issues.add('missing CHANGELOG.md');
      }

      // Check git status (if in a git repo)
      final gitIssues = await _checkGitStatus(projectPath);
      issues.addAll(gitIssues);

      // Print result
      if (issues.isEmpty) {
        print('  $projectName: Ready to publish');
      } else {
        print('  $projectName: ${issues.join(', ')}');
      }

      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: issues.isEmpty ? 'ready' : issues.join(', '),
      );
    } catch (e) {
      return ItemResult.failure(
        path: projectPath,
        name: context.name,
        error: 'Failed: $e',
      );
    }
  }

  Map<String, dynamic> _getCmdOpts(CliArgs args) {
    for (final cmd in args.commands) {
      if (cmd == 'publisher' || cmd == 'pub') {
        final cmdArgs = args.commandArgs[cmd];
        if (cmdArgs != null) return cmdArgs.options;
      }
    }
    return args.extraOptions;
  }

  Future<List<String>> _checkGitStatus(String projectPath) async {
    final issues = <String>[];

    try {
      // Check for uncommitted changes
      final statusResult = await ProcessRunner.run('git', [
        'status',
        '--porcelain',
        '--',
        projectPath,
      ], workingDirectory: projectPath);
      if (statusResult.exitCode == 0) {
        final output = statusResult.stdout.trim();
        if (output.isNotEmpty) {
          final lineCount = output.split('\n').length;
          issues.add('uncommitted changes ($lineCount files)');
        }
      }

      // Check for unpushed commits
      final branchResult = await ProcessRunner.run('git', [
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ], workingDirectory: projectPath);
      if (branchResult.exitCode == 0) {
        final branch = branchResult.stdout.trim();
        final logResult = await ProcessRunner.run('git', [
          'log',
          branch,
          '--not',
          '--remotes',
          '--oneline',
        ], workingDirectory: projectPath);
        if (logResult.exitCode == 0) {
          final output = logResult.stdout.trim();
          if (output.isNotEmpty) {
            final count = output.split('\n').length;
            issues.add('unpushed commits ($count)');
          }
        }
      }
    } catch (_) {
      // Not in a git repo or git not available — skip git checks
    }

    return issues;
  }
}
