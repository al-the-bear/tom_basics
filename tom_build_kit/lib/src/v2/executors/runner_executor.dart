/// Native v2 executor for the runner (build_runner) command.
///
/// Wraps `dart run build_runner` with multi-project scanning and
/// builder include/exclude filtering.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart'
    show findWorkspaceRoot, toStringList, ProcessRunner;
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:yaml/yaml.dart';

// =============================================================================
// Configuration
// =============================================================================

/// Builder include/exclude filtering with 3-level precedence.
class _BuilderFilter {
  final List<String> include;
  final List<String> exclude;

  const _BuilderFilter({this.include = const [], this.exclude = const []});
  bool get isEmpty => include.isEmpty && exclude.isEmpty;
  bool get isNotEmpty => !isEmpty;

  static _BuilderFilter getEffective({
    required String projectPath,
    String? rootPath,
    List<String> cliInclude = const [],
    List<String> cliExclude = const [],
  }) {
    // Level 1: CLI
    if (cliInclude.isNotEmpty || cliExclude.isNotEmpty) {
      return _BuilderFilter(include: cliInclude, exclude: cliExclude);
    }

    // Level 2: project buildkit.yaml
    final projectFilter = _loadFilter('$projectPath/buildkit.yaml');
    if (projectFilter != null && projectFilter.isNotEmpty) return projectFilter;

    // Level 3: workspace buildkit_master.yaml
    if (rootPath != null && rootPath != projectPath) {
      final masterFilter = _loadFilter('$rootPath/buildkit_master.yaml');
      if (masterFilter != null && masterFilter.isNotEmpty) return masterFilter;
    }

    return const _BuilderFilter();
  }

  static _BuilderFilter? _loadFilter(String yamlPath) {
    final file = File(yamlPath);
    if (!file.existsSync()) return null;
    try {
      final yaml = loadYaml(file.readAsStringSync()) as YamlMap?;
      final br = yaml?['build_runner'] as YamlMap?;
      if (br == null) return null;
      return _BuilderFilter(
        include: toStringList(br['include-builders'] ?? br['include_builders']),
        exclude: toStringList(br['exclude-builders'] ?? br['exclude_builders']),
      );
    } catch (_) {
      return null;
    }
  }
}

// =============================================================================
// Executor
// =============================================================================

/// Native v2 executor for the `:runner` command.
class RunnerExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final projectPath = context.path;
    final hasBuildYaml = File('$projectPath/build.yaml').existsSync();

    // Parse command options early so skip messages can include the command name
    final cmdOpts = _getCmdOpts(args);
    final command = cmdOpts['command']?.toString() ?? 'build';

    // List mode: print project path if it has build.yaml
    if (args.listOnly) {
      if (!hasBuildYaml) {
        return ItemResult.success(
          path: projectPath,
          name: context.name,
          message: 'skipped (no build.yaml)',
        );
      }
      print('  ${p.relative(projectPath, from: context.executionRoot)}');
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'listed',
      );
    }

    // Dump config mode: show builder information (even if no build.yaml)
    if (args.dumpConfig) {
      if (!hasBuildYaml) {
        print('  ${context.name}: (no build.yaml)');
        return ItemResult.success(
          path: projectPath,
          name: context.name,
          message: 'no build.yaml',
        );
      }
      final builders = _extractBuilders(projectPath);
      print('  ${context.name}:');
      print('    build.yaml: $projectPath/build.yaml');
      if (builders.isNotEmpty) {
        print('    builders:');
        for (final b in builders) {
          print('      - $b');
        }
      } else {
        print('    builders: (none detected)');
      }
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'config shown',
      );
    }

    // Requires build.yaml for actual execution
    if (!hasBuildYaml) {
      if (args.dryRun) {
        print('  [DRY RUN] ${context.name}: skipped $command (no build.yaml)');
        return ItemResult.success(
          path: projectPath,
          name: context.name,
          message: 'skipped (no build.yaml)',
        );
      }
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'skipped (no build.yaml)',
      );
    }

    final deleteConflicting = cmdOpts['delete-conflicting'] == true;
    final configName = cmdOpts['config']?.toString();
    final release = cmdOpts['release'] == true;

    // Parse builder filters
    final cliInclude = _toStringList(cmdOpts['include-builders']);
    final cliExclude = _toStringList(cmdOpts['exclude-builders']);

    final rootPath = findWorkspaceRoot(context.executionRoot);

    // Get effective filter
    final filter = _BuilderFilter.getEffective(
      projectPath: projectPath,
      rootPath: rootPath,
      cliInclude: cliInclude,
      cliExclude: cliExclude,
    );

    // Extract configured builders from build.yaml
    final configuredBuilders = _extractBuilders(projectPath);

    // Apply filters to determine which builders run vs disable
    var buildersToRun = List.of(configuredBuilders);
    if (filter.include.isNotEmpty) {
      buildersToRun = buildersToRun
          .where(
            (b) =>
                filter.include.any((inc) => b.contains(inc) || inc.contains(b)),
          )
          .toList();
    }
    if (filter.exclude.isNotEmpty) {
      buildersToRun = buildersToRun
          .where(
            (b) => !filter.exclude.any(
              (exc) => b.contains(exc) || exc.contains(b),
            ),
          )
          .toList();
    }
    final buildersToDisable = configuredBuilders
        .where((b) => !buildersToRun.contains(b))
        .toList();

    if (args.verbose && filter.isNotEmpty) {
      print('  Builders to run: ${buildersToRun.join(', ')}');
      if (buildersToDisable.isNotEmpty) {
        print('  Builders disabled: ${buildersToDisable.join(', ')}');
      }
    }

    // Build command args
    final dartArgs = ['run', 'build_runner', command];

    if (deleteConflicting && (command == 'build' || command == 'watch')) {
      dartArgs.add('--delete-conflicting-outputs');
    }
    if (configName != null) dartArgs.add('--config=$configName');
    if (release) dartArgs.add('--release');
    if (args.verbose) dartArgs.add('--verbose');

    for (final builder in buildersToDisable) {
      dartArgs.add('--define=$builder=enabled=false');
    }

    if (args.dryRun) {
      print('  [DRY RUN] dart ${dartArgs.join(' ')}');
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'dry-run',
      );
    }

    if (args.verbose) {
      print('  Running: dart ${dartArgs.join(' ')}');
      print('  Working directory: ${p.basename(projectPath)}');
    }

    final result = await ProcessRunner.run(
      'dart',
      dartArgs,
      workingDirectory: projectPath,
      runInShell: Platform.isWindows,
    );

    final failed = result.exitCode != 0;
    final combined =
        '${result.stdout.toLowerCase()}\n${result.stderr.toLowerCase()}';
    final hasSignalWords = combined.contains('error') ||
        combined.contains('warn') ||
        combined.contains('fail');

    // Only show subprocess output in verbose mode, or when there are
    // errors/warnings/failures.
    if (args.verbose || failed || hasSignalWords) {
      if (result.stdout.isNotEmpty) stdout.write(result.stdout);
      if (result.stderr.isNotEmpty) stderr.write(result.stderr);
    }

    if (failed) {
      return ItemResult.failure(
        path: projectPath,
        name: context.name,
        error: 'build_runner $command failed (exit ${result.exitCode})',
      );
    }

    return ItemResult.success(
      path: projectPath,
      name: context.name,
      message: 'ok',
    );
  }

  Map<String, dynamic> _getCmdOpts(CliArgs args) {
    for (final cmd in args.commands) {
      if (cmd == 'runner' || cmd == 'run') {
        final cmdArgs = args.commandArgs[cmd];
        if (cmdArgs != null) return cmdArgs.options;
      }
    }
    return args.extraOptions;
  }

  List<String> _toStringList(dynamic value) {
    if (value == null) return [];
    if (value is String) return [value];
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }

  /// Extract builder keys from build.yaml.
  List<String> _extractBuilders(String projectPath) {
    final file = File('$projectPath/build.yaml');
    if (!file.existsSync()) return [];

    try {
      final yaml = loadYaml(file.readAsStringSync()) as YamlMap?;
      if (yaml == null) return [];

      final builders = <String>{};

      final targets = yaml['targets'] as YamlMap?;
      if (targets != null) {
        for (final target in targets.values) {
          if (target is! YamlMap) continue;
          final targetBuilders = target['builders'] as YamlMap?;
          if (targetBuilders == null) continue;
          for (final entry in targetBuilders.entries) {
            final config = entry.value as YamlMap?;
            if (config?['enabled'] as bool? ?? true) {
              builders.add(entry.key.toString());
            }
          }
        }
      }

      final globalOptions = yaml['global_options'] as YamlMap?;
      if (globalOptions != null) {
        builders.addAll(globalOptions.keys.map((k) => k.toString()));
      }

      return builders.toList();
    } catch (_) {
      return [];
    }
  }
}
