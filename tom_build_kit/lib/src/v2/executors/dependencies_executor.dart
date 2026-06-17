/// Native v2 executor for the dependencies command.
///
/// Shows dependency tree for Dart projects, parsing pubspec.yaml
/// and pubspec_overrides.yaml.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:yaml/yaml.dart';

// =============================================================================
// Data Types
// =============================================================================

/// A parsed dependency entry.
class _DepEntry {
  final String name;
  final String source; // 'hosted', 'path', 'git', 'sdk'
  final String? version;
  final String? path;
  final bool isOverridden;
  final bool isDev;

  _DepEntry({
    required this.name,
    required this.source,
    this.version,
    this.path,
    this.isOverridden = false,
    this.isDev = false,
  });

  String get displaySource {
    final buf = StringBuffer();
    switch (source) {
      case 'path':
        buf.write('path: ${path ?? "?"}');
      case 'git':
        buf.write('git: ${path ?? "?"}');
      case 'sdk':
        buf.write('sdk: ${version ?? "?"}');
      default:
        buf.write(version ?? 'any');
    }
    if (isOverridden) buf.write(' [override]');
    return buf.toString();
  }
}

// =============================================================================
// Executor
// =============================================================================

/// Native v2 executor for the `:dependencies` command.
class DependenciesExecutor extends CommandExecutor {
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

    // List mode: just print project path
    if (args.listOnly) {
      print('  ${p.relative(projectPath, from: context.executionRoot)}');
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'listed',
      );
    }

    final cmdOpts = _getCmdOpts(args);
    final showDev = cmdOpts['dev'] == true;
    final showAll = cmdOpts['all'] == true;
    final showDeep = cmdOpts['deep'] == true;

    try {
      final content = pubspecFile.readAsStringSync();
      final yaml = loadYaml(content) as YamlMap?;
      if (yaml == null) {
        return ItemResult.failure(
          path: projectPath,
          name: context.name,
          error: 'invalid pubspec.yaml',
        );
      }

      final projectName = yaml['name']?.toString() ?? context.name;

      // Parse overrides
      final overrideNames = <String>{};
      final overridesFile = File('$projectPath/pubspec_overrides.yaml');
      if (overridesFile.existsSync()) {
        try {
          final oYaml = loadYaml(overridesFile.readAsStringSync()) as YamlMap?;
          if (oYaml != null) {
            final deps = oYaml['dependency_overrides'] as YamlMap?;
            if (deps != null) overrideNames.addAll(deps.keys.cast<String>());
          }
        } catch (_) {}
      }

      // Parse dependencies
      final deps = <_DepEntry>[];
      final depsYaml = yaml['dependencies'] as YamlMap?;
      if (depsYaml != null && !showDev) {
        deps.addAll(_parseDeps(depsYaml, overrideNames, isDev: false));
      }
      final devDepsYaml = yaml['dev_dependencies'] as YamlMap?;
      if (devDepsYaml != null && (showDev || showAll)) {
        deps.addAll(_parseDeps(devDepsYaml, overrideNames, isDev: true));
      }

      // If neither --dev nor --all, show normal deps
      if (!showDev && !showAll && depsYaml != null) {
        // Already added above
      }

      // Sort
      deps.sort((a, b) {
        if (a.isDev != b.isDev) return a.isDev ? 1 : -1;
        return a.name.compareTo(b.name);
      });

      // Print
      print('');
      print('$projectName (${context.relativePath})');
      if (deps.isEmpty) {
        print('  (no dependencies)');
      } else {
        for (final dep in deps) {
          final prefix = dep.isDev ? '  +> ' : '  -> ';
          print('$prefix${dep.name}: ${dep.displaySource}');
        }
      }

      if (showDeep) {
        print('  --- recursive tree ---');
        _printDeepTree(projectPath, projectName, overrideNames, visited: {});
      }

      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: '${deps.length} dependencies',
      );
    } catch (e) {
      return ItemResult.failure(
        path: projectPath,
        name: context.name,
        error: 'Failed to parse pubspec: $e',
      );
    }
  }

  Map<String, dynamic> _getCmdOpts(CliArgs args) {
    for (final cmd in args.commands) {
      if (cmd == 'dependencies' || cmd == 'deps') {
        final cmdArgs = args.commandArgs[cmd];
        if (cmdArgs != null) return cmdArgs.options;
      }
    }
    return args.extraOptions;
  }

  List<_DepEntry> _parseDeps(
    YamlMap depsYaml,
    Set<String> overrideNames, {
    required bool isDev,
  }) {
    final result = <_DepEntry>[];
    for (final entry in depsYaml.entries) {
      final name = entry.key.toString();
      final value = entry.value;
      final isOverridden = overrideNames.contains(name);

      if (value == null || value is String) {
        result.add(
          _DepEntry(
            name: name,
            source: 'hosted',
            version: value?.toString() ?? 'any',
            isOverridden: isOverridden,
            isDev: isDev,
          ),
        );
      } else if (value is YamlMap) {
        if (value.containsKey('path')) {
          result.add(
            _DepEntry(
              name: name,
              source: 'path',
              path: value['path'].toString(),
              isOverridden: isOverridden,
              isDev: isDev,
            ),
          );
        } else if (value.containsKey('git')) {
          final git = value['git'];
          final url = git is String ? git : (git as YamlMap?)?.value['url'];
          result.add(
            _DepEntry(
              name: name,
              source: 'git',
              path: url?.toString(),
              isOverridden: isOverridden,
              isDev: isDev,
            ),
          );
        } else if (value.containsKey('sdk')) {
          result.add(
            _DepEntry(
              name: name,
              source: 'sdk',
              version: value['sdk'].toString(),
              isOverridden: isOverridden,
              isDev: isDev,
            ),
          );
        } else {
          result.add(
            _DepEntry(
              name: name,
              source: 'hosted',
              version: value['version']?.toString() ?? 'any',
              isOverridden: isOverridden,
              isDev: isDev,
            ),
          );
        }
      }
    }
    return result;
  }

  /// Print recursive dependency tree following path dependencies.
  void _printDeepTree(
    String projectPath,
    String projectName,
    Set<String> overrideNames, {
    required Set<String> visited,
    String indent = '  ',
  }) {
    if (visited.contains(projectPath)) {
      print('$indent(circular: $projectName)');
      return;
    }
    visited.add(projectPath);

    final pubspecFile = File('$projectPath/pubspec.yaml');
    if (!pubspecFile.existsSync()) return;

    try {
      final yaml = loadYaml(pubspecFile.readAsStringSync()) as YamlMap?;
      if (yaml == null) return;

      final depsYaml = yaml['dependencies'] as YamlMap?;
      if (depsYaml == null) return;

      for (final entry in depsYaml.entries) {
        final name = entry.key.toString();
        final value = entry.value;
        if (value is YamlMap && value.containsKey('path')) {
          final depPath = p.normalize(
            p.join(projectPath, value['path'].toString()),
          );
          print('$indent├── $name (path)');
          if (File('$depPath/pubspec.yaml').existsSync()) {
            _printDeepTree(
              depPath,
              name,
              overrideNames,
              visited: visited,
              indent: '$indent│   ',
            );
          }
        } else {
          final ver = value is String
              ? value
              : (value is YamlMap ? value['version']?.toString() : null);
          print('$indent├── $name ${ver ?? ""}');
        }
      }
    } catch (_) {}
  }
}
