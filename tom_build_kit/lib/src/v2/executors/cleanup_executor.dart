/// Native v2 executor for the cleanup command.
///
/// Removes generated and temporary files from Dart projects using
/// configurable glob patterns with safety guards.
library;

import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:yaml/yaml.dart';

// =============================================================================
// Configuration
// =============================================================================

/// Configuration for a single cleanup section (patterns + excludes).
class CleanupSection {
  final List<String> globs;
  final List<String> excludes;

  CleanupSection({required this.globs, this.excludes = const []});

  factory CleanupSection.fromJson(dynamic json) {
    if (json is String) return CleanupSection(globs: [json]);
    if (json is Map) {
      final globs = _toStringList(json['globs'] ?? json['glob']);
      final excludes = _toStringList(json['excludes'] ?? json['exclude']);
      if (globs.isEmpty) {
        throw ArgumentError('CleanupSection map must have "globs" key');
      }
      return CleanupSection(globs: globs, excludes: excludes);
    }
    throw ArgumentError(
      'CleanupSection must be a string or map, got: ${json.runtimeType}',
    );
  }
}

/// Configuration for the cleanup tool.
class CleanupConfig {
  final List<CleanupSection> cleanupSections;
  final List<String> globalExcludes;
  final List<String> protectedFolders;

  const CleanupConfig({
    this.cleanupSections = const [],
    this.globalExcludes = const [],
    this.protectedFolders = const [],
  });

  /// Load from buildkit.yaml in the given directory.
  static CleanupConfig? loadFromYaml(String dir) {
    final file = File('$dir/buildkit.yaml');
    if (!file.existsSync()) return null;

    try {
      final content = file.readAsStringSync();
      final yaml = loadYaml(content) as YamlMap?;
      if (yaml == null || !yaml.containsKey('cleanup')) return null;

      final cleanupValue = yaml['cleanup'];
      if (cleanupValue == null) return const CleanupConfig();

      if (cleanupValue is YamlList) {
        return CleanupConfig(
          cleanupSections: [
            for (final item in cleanupValue) CleanupSection.fromJson(item),
          ],
        );
      }

      if (cleanupValue is! YamlMap) return null;
      final cleanupYaml = cleanupValue;

      return CleanupConfig(
        cleanupSections: [
          if (cleanupYaml['cleanup'] is YamlList)
            for (final item in cleanupYaml['cleanup'] as YamlList)
              CleanupSection.fromJson(item),
        ],
        globalExcludes: _toStringList(
          cleanupYaml['excludes'] ?? cleanupYaml['exclude'],
        ),
        protectedFolders: _toStringList(
          cleanupYaml['protected-folders'] ?? cleanupYaml['protectedFolders'],
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Merge (other takes precedence).
  CleanupConfig merge(CleanupConfig other) {
    return CleanupConfig(
      cleanupSections: other.cleanupSections.isNotEmpty
          ? other.cleanupSections
          : cleanupSections,
      globalExcludes: [...globalExcludes, ...other.globalExcludes],
      protectedFolders: [...protectedFolders, ...other.protectedFolders],
    );
  }
}

List<String> _toStringList(dynamic value) {
  if (value == null) return [];
  if (value is String) return [value];
  if (value is List) return value.map((e) => e.toString()).toList();
  return [];
}

// =============================================================================
// Executor
// =============================================================================

/// Built-in folders that must never be deleted.
const _builtinProtectedFolders = {'.git', '.github', '.vscode', '.idea'};

/// Default cleanup patterns when no config is provided.
final _defaultSections = [
  CleanupSection(
    globs: [
      'build',
      '.dart_tool/build',
      '**/*.g.dart',
      '**/*.r.dart',
      '**/*.b.dart',
      '**/*.reflection.dart',
      '**/*.reflectable.dart',
    ],
  ),
];

/// Native v2 executor for the `:cleanup` command.
class CleanupExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final projectPath = context.path;

    // Check if project has cleanup config
    final pubspec = File('$projectPath/pubspec.yaml');
    if (!pubspec.existsSync()) {
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

    // Dump config mode: show cleanup configuration
    if (args.dumpConfig) {
      final config = CleanupConfig.loadFromYaml(projectPath);
      print('  ${context.name}:');
      if (config != null && config.cleanupSections.isNotEmpty) {
        for (final section in config.cleanupSections) {
          print('    globs: ${section.globs.join(', ')}');
          if (section.excludes.isNotEmpty) {
            print('    excludes: ${section.excludes.join(', ')}');
          }
        }
        if (config.globalExcludes.isNotEmpty) {
          print('    global-excludes: ${config.globalExcludes.join(', ')}');
        }
        if (config.protectedFolders.isNotEmpty) {
          print('    protected: ${config.protectedFolders.join(', ')}');
        }
      } else {
        print('    cleanup: (using defaults)');
      }
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'config shown',
      );
    }

    final cmdOpts = _getCmdOpts(args);
    final force = cmdOpts['force'] == true || args.force;
    final maxFiles =
        int.tryParse(cmdOpts['max-files']?.toString() ?? '') ?? 100;

    // Load workspace config from execution root
    var config =
        CleanupConfig.loadFromYaml(context.executionRoot) ??
        const CleanupConfig();

    // Load project config and merge
    final projectConfig = CleanupConfig.loadFromYaml(projectPath);
    if (projectConfig != null) {
      config = config.merge(projectConfig);
    }

    // If no config at all, skip unless there's a cleanup section default
    if (config.cleanupSections.isEmpty && projectConfig == null) {
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'skipped (no cleanup config)',
      );
    }

    final protectedFolders = {
      ..._builtinProtectedFolders,
      ...config.protectedFolders,
    };

    var sections = config.cleanupSections;
    if (sections.isEmpty) sections = _defaultSections;

    // Collect files to delete
    final filesToDelete = <String>[];
    for (final section in sections) {
      for (final pattern in section.globs) {
        _collectMatchingFiles(
          projectPath,
          pattern,
          section.excludes,
          config.globalExcludes,
          protectedFolders,
          filesToDelete,
          verbose: args.verbose,
        );
      }
    }

    if (filesToDelete.isEmpty) {
      if (args.verbose) print('  No files to clean up');
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'clean',
      );
    }

    // Safety check
    if (filesToDelete.length > maxFiles && !force) {
      print('');
      print(
        'WARNING: Cleanup would delete ${filesToDelete.length} files '
        'in ${context.name} (limit: $maxFiles)',
      );
      print('  Use --force or --max-files=${filesToDelete.length} to proceed');
      return ItemResult.failure(
        path: projectPath,
        name: context.name,
        error: 'file count ${filesToDelete.length} exceeds limit $maxFiles',
      );
    }

    if (args.dryRun) {
      print('  [DRY RUN] Would delete ${filesToDelete.length} file(s):');
      for (final file in filesToDelete) {
        print('    - ${p.relative(file, from: projectPath)}');
      }
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'dry-run: ${filesToDelete.length} files',
      );
    }

    // Delete files
    var deleted = 0;
    for (final filePath in filesToDelete) {
      if (_isInProtectedFolder(filePath, protectedFolders)) continue;
      try {
        if (args.verbose) {
          print('  Removing: ${p.relative(filePath, from: projectPath)}');
        }
        final entity = FileSystemEntity.isDirectorySync(filePath)
            ? Directory(filePath)
            : File(filePath);
        entity.deleteSync(recursive: true);
        deleted++;
      } catch (e) {
        if (args.verbose) print('  Warning: Failed to remove $filePath: $e');
      }
    }

    print('  Cleanup: deleted $deleted file(s) in ${context.name}');
    return ItemResult.success(
      path: projectPath,
      name: context.name,
      message: 'deleted $deleted files',
    );
  }

  Map<String, dynamic> _getCmdOpts(CliArgs args) {
    for (final cmd in args.commands) {
      if (cmd == 'cleanup' || cmd == 'clean' || cmd == 'cl') {
        final cmdArgs = args.commandArgs[cmd];
        if (cmdArgs != null) return cmdArgs.options;
      }
    }
    return args.extraOptions;
  }

  void _collectMatchingFiles(
    String projectPath,
    String pattern,
    List<String> sectionExcludes,
    List<String> globalExcludes,
    Set<String> protectedFolders,
    List<String> results, {
    required bool verbose,
  }) {
    final fullPath = '$projectPath/$pattern';

    if (!pattern.contains('*') &&
        !pattern.contains('?') &&
        !pattern.contains('[')) {
      if (_isInProtectedFolder(fullPath, protectedFolders)) return;
      if (FileSystemEntity.isDirectorySync(fullPath)) {
        _collectFilesInDir(Directory(fullPath), protectedFolders, results);
      } else if (File(fullPath).existsSync()) {
        if (!_isExcluded(fullPath, sectionExcludes, globalExcludes)) {
          results.add(fullPath);
        }
      }
      return;
    }

    try {
      final glob = Glob(pattern);
      for (final entity in glob.listSync(root: projectPath)) {
        if (_isInProtectedFolder(entity.path, protectedFolders)) continue;
        if (_isExcluded(entity.path, sectionExcludes, globalExcludes)) continue;
        if (entity is File) {
          results.add(entity.path);
        } else if (entity is Directory) {
          _collectFilesInDir(entity as Directory, protectedFolders, results);
        }
      }
    } catch (e) {
      if (verbose) print('  Warning: Glob error for "$pattern": $e');
    }
  }

  void _collectFilesInDir(
    Directory dir,
    Set<String> protectedFolders,
    List<String> files,
  ) {
    if (_isInProtectedFolder(dir.path, protectedFolders)) return;
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File &&
            !_isInProtectedFolder(entity.path, protectedFolders)) {
          files.add(entity.path);
        }
      }
    } catch (_) {}
  }

  bool _isInProtectedFolder(String path, Set<String> protectedFolders) {
    final parts = p.split(path);
    for (final folder in protectedFolders) {
      if (folder.contains('/') || folder.contains('*')) {
        try {
          if (Glob('**/$folder/**').matches(path) ||
              Glob('$folder/**').matches(path)) {
            return true;
          }
        } catch (_) {
          if (path.contains(folder)) return true;
        }
      } else {
        if (parts.contains(folder)) return true;
      }
    }
    return false;
  }

  bool _isExcluded(
    String path,
    List<String> sectionExcludes,
    List<String> globalExcludes,
  ) {
    for (final exclude in [...sectionExcludes, ...globalExcludes]) {
      try {
        if (Glob(exclude).matches(path)) return true;
      } catch (_) {
        if (path.contains(exclude)) return true;
      }
    }
    return false;
  }
}
