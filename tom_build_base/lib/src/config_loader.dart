import 'dart:io' show Platform;

import 'package:dcli/dcli.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'yaml_utils.dart';

/// Global skip file that blocks all tools.
const kTomSkipYaml = 'tom_skip.yaml';

/// Pattern for mode-prefixed keys (e.g., DEV-defines, CI-enabled).
final _modePrefixPattern = RegExp(r'^([A-Z][A-Z0-9]*)-(.+)$');

/// Pattern for define placeholders: @[name]
final _definePlaceholderPattern = RegExp(r'@\[([a-zA-Z_][a-zA-Z0-9_-]*)\]');

/// Pattern for tool placeholders: @{name}
final _toolPlaceholderPattern = RegExp(r'@\{([a-zA-Z_][a-zA-Z0-9_-]*)\}');

/// Pattern for environment variables: $VAR or $[VAR]
final _envVarPattern = RegExp(r'\$([a-zA-Z_][a-zA-Z0-9_]*)\b|\$\[([a-zA-Z_][a-zA-Z0-9_]*)\]');

/// Result of configuration loading with all modes and placeholders resolved.
class LoadedConfig {
  /// Processed master config (no @[...], @{...}, or MODE- keys).
  final Map<String, dynamic> masterConfig;

  /// Processed project config (no @[...], @{...}, or MODE- keys).
  final Map<String, dynamic> projectConfig;

  /// Active modes that were applied.
  final List<String> appliedModes;

  /// The defines that were resolved (for debugging/help).
  final Map<String, String> resolvedDefines;

  const LoadedConfig({
    this.masterConfig = const {},
    this.projectConfig = const {},
    this.appliedModes = const [],
    this.resolvedDefines = const {},
  });
}

/// Placeholder definition for registration and help output.
class PlaceholderDefinition {
  /// Placeholder name (without @{} or ${} syntax).
  final String name;

  /// Human-readable description.
  final String description;

  /// Optional resolver function.
  final String Function(PlaceholderContext ctx)? resolver;

  const PlaceholderDefinition({
    required this.name,
    required this.description,
    this.resolver,
  });
}

/// Context for placeholder resolution.
class PlaceholderContext {
  /// Current project path.
  final String projectPath;

  /// Workspace root path.
  final String workspaceRoot;

  /// Tool name.
  final String toolName;

  /// Tool version.
  final String toolVersion;

  /// Active modes.
  final List<String> activeModes;

  const PlaceholderContext({
    required this.projectPath,
    required this.workspaceRoot,
    required this.toolName,
    this.toolVersion = '1.0.0',
    this.activeModes = const [],
  });

  /// Project name (basename of project path).
  String get projectName => p.basename(projectPath);
}

/// Loads and processes configuration files with mode and placeholder resolution.
///
/// The loader performs these steps:
/// 1. Load {basename}_master.yaml from workspace root
/// 2. Load {basename}.yaml from project root
/// 3. Apply mode processing (merge MODE-keys, discard inactive)
/// 4. Resolve @[...] define placeholders (from defines: section)
/// 5. Resolve @{...} tool placeholders (project-path, workspace-root, etc.)
/// 6. Return clean configs ready for tool-specific merge
class ConfigLoader {
  /// Tool's config file basename (e.g., 'buildkit', 'testkit').
  final String basename;

  /// Tool placeholders available for @{...} resolution.
  final Map<String, PlaceholderDefinition> toolPlaceholders;

  /// Whether to print verbose output.
  final bool verbose;

  ConfigLoader({
    required this.basename,
    this.toolPlaceholders = const {},
    this.verbose = false,
  });

  /// Master config filename.
  String get masterFilename => '${basename}_master.yaml';

  /// Project config filename.
  String get projectFilename => '$basename.yaml';

  /// Tool-specific skip filename.
  String get skipFilename => '${basename}_skip.yaml';

  /// Load configuration for a project.
  ///
  /// Steps performed automatically:
  /// 1. Load {basename}_master.yaml from workspace root
  /// 2. Load {basename}.yaml from project root
  /// 3. Apply mode processing (merge MODE-keys, discard inactive)
  /// 4. Resolve @[...] define placeholders
  /// 5. Resolve @{...} tool placeholders
  /// 6. Return clean configs ready for tool-specific merge
  Future<LoadedConfig> load({
    required String workspaceRoot,
    required String projectPath,
    required List<String> activeModes,
  }) async {
    // 1. Load master config
    final masterRaw = _loadYamlFile(p.join(workspaceRoot, masterFilename));

    // 2. Load project config
    final projectRaw = _loadYamlFile(p.join(projectPath, projectFilename));

    // 3. Apply mode processing
    final masterProcessed = _processModes(masterRaw, activeModes);
    final projectProcessed = _processModes(projectRaw, activeModes);

    // 4. Extract defines and resolve @[...] placeholders
    final defines = _extractDefines(masterProcessed, projectProcessed);
    final masterWithDefines = _resolveDefinePlaceholders(masterProcessed, defines);
    final projectWithDefines = _resolveDefinePlaceholders(projectProcessed, defines);

    // 5. Resolve @{...} tool placeholders
    final ctx = PlaceholderContext(
      projectPath: projectPath,
      workspaceRoot: workspaceRoot,
      toolName: basename,
      activeModes: activeModes,
    );
    final toolValues = _buildToolPlaceholderValues(ctx);
    final masterFinal = _resolveToolPlaceholders(masterWithDefines, toolValues);
    final projectFinal = _resolveToolPlaceholders(projectWithDefines, toolValues);

    return LoadedConfig(
      masterConfig: masterFinal,
      projectConfig: projectFinal,
      appliedModes: activeModes,
      resolvedDefines: defines,
    );
  }

  /// Load YAML file and return as Map, or empty map if not found.
  Map<String, dynamic> _loadYamlFile(String path) {
    if (!exists(path)) return {};

    try {
      final content = read(path).toParagraph();
      final yaml = loadYaml(content);
      if (yaml is YamlMap) {
        return yamlToMap(yaml);
      }
      return {};
    } catch (e) {
      if (verbose) {
        print('Warning: Failed to load $path: $e');
      }
      return {};
    }
  }

  /// Process modes in a config map.
  ///
  /// For active modes, merges MODE-key into base key.
  /// Removes all MODE-* keys from the result.
  Map<String, dynamic> _processModes(
    Map<String, dynamic> config,
    List<String> activeModes,
  ) {
    final result = <String, dynamic>{};

    // First pass: copy non-mode keys
    for (final entry in config.entries) {
      final match = _modePrefixPattern.firstMatch(entry.key);
      if (match == null) {
        // Not a mode-prefixed key
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          result[entry.key] = _processModes(value, activeModes);
        } else if (value is List) {
          result[entry.key] = _processListModes(value, activeModes);
        } else {
          result[entry.key] = value;
        }
      }
    }

    // Second pass: apply active mode overrides in order
    for (final mode in activeModes) {
      for (final entry in config.entries) {
        final match = _modePrefixPattern.firstMatch(entry.key);
        if (match != null && match.group(1) == mode) {
          final baseKey = match.group(2)!;
          final value = entry.value;

          if (value is Map<String, dynamic> && result[baseKey] is Map<String, dynamic>) {
            // Merge maps
            result[baseKey] = _mergeMaps(
              result[baseKey] as Map<String, dynamic>,
              _processModes(value, activeModes),
            );
          } else if (value is Map<String, dynamic>) {
            result[baseKey] = _processModes(value, activeModes);
          } else if (value is List) {
            // Lists replace, not merge
            result[baseKey] = _processListModes(value, activeModes);
          } else {
            // Scalar values replace
            result[baseKey] = value;
          }
        }
      }
    }

    return result;
  }

  /// Process modes in list items (if they are maps).
  List<dynamic> _processListModes(List<dynamic> list, List<String> activeModes) {
    return list.map((item) {
      if (item is Map<String, dynamic>) {
        return _processModes(item, activeModes);
      }
      return item;
    }).toList();
  }

  /// Merge two maps (shallow merge, second overrides first).
  Map<String, dynamic> _mergeMaps(
    Map<String, dynamic> base,
    Map<String, dynamic> override,
  ) {
    final result = Map<String, dynamic>.from(base);
    for (final entry in override.entries) {
      result[entry.key] = entry.value;
    }
    return result;
  }

  /// Extract defines from both configs.
  Map<String, String> _extractDefines(
    Map<String, dynamic> master,
    Map<String, dynamic> project,
  ) {
    final defines = <String, String>{};

    // Extract from both configs, project overrides master
    void extractFrom(Map<String, dynamic>? definesSection) {
      if (definesSection == null) return;
      for (final entry in definesSection.entries) {
        defines[entry.key.toString()] = entry.value.toString();
      }
    }

    // Look in top-level 'defines:' and in tool-specific section
    extractFrom(_asMap(master['defines']));
    extractFrom(_asMap(master[basename]?['defines']));
    extractFrom(_asMap(project['defines']));
    extractFrom(_asMap(project[basename]?['defines']));

    // Resolve defines that reference other defines
    return _resolveDefineChain(defines);
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  /// Resolve define values that reference other defines.
  Map<String, String> _resolveDefineChain(Map<String, String> defines) {
    final resolved = <String, String>{};
    const maxDepth = 10;

    String resolveValue(String value, int depth) {
      if (depth > maxDepth) return value;

      return value.replaceAllMapped(_definePlaceholderPattern, (match) {
        final name = match.group(1)!;
        final replacement = defines[name];
        if (replacement != null) {
          return resolveValue(replacement, depth + 1);
        }
        return match.group(0)!; // Keep unresolved
      });
    }

    for (final entry in defines.entries) {
      resolved[entry.key] = resolveValue(entry.value, 0);
    }

    return resolved;
  }

  /// Resolve @[...] define placeholders in a config.
  Map<String, dynamic> _resolveDefinePlaceholders(
    Map<String, dynamic> config,
    Map<String, String> defines,
  ) {
    return _resolveInMap(config, defines, _definePlaceholderPattern);
  }

  /// Resolve @{...} tool placeholders in a config.
  Map<String, dynamic> _resolveToolPlaceholders(
    Map<String, dynamic> config,
    Map<String, String> toolValues,
  ) {
    return _resolveInMap(config, toolValues, _toolPlaceholderPattern);
  }

  /// Generic placeholder resolution in a map.
  Map<String, dynamic> _resolveInMap(
    Map<String, dynamic> config,
    Map<String, String> values,
    RegExp pattern,
  ) {
    final result = <String, dynamic>{};

    for (final entry in config.entries) {
      result[entry.key] = _resolveValue(entry.value, values, pattern);
    }

    return result;
  }

  /// Resolve placeholders in a value (recursive for maps/lists).
  dynamic _resolveValue(
    dynamic value,
    Map<String, String> values,
    RegExp pattern,
  ) {
    if (value is String) {
      return _resolveString(value, values, pattern);
    } else if (value is Map<String, dynamic>) {
      return _resolveInMap(value, values, pattern);
    } else if (value is Map) {
      return _resolveInMap(Map<String, dynamic>.from(value), values, pattern);
    } else if (value is List) {
      return value.map((item) => _resolveValue(item, values, pattern)).toList();
    }
    return value;
  }

  /// Resolve placeholders in a string with max depth.
  String _resolveString(
    String template,
    Map<String, String> values,
    RegExp pattern, {
    int depth = 0,
    int maxDepth = 10,
  }) {
    if (depth > maxDepth) return template;

    var result = template;
    var changed = false;

    result = result.replaceAllMapped(pattern, (match) {
      final name = match.group(1)!;
      final replacement = values[name];
      if (replacement != null) {
        changed = true;
        return replacement;
      }
      return match.group(0)!; // Keep unresolved
    });

    // Recurse if we made replacements (resolved value may contain more placeholders)
    if (changed) {
      return _resolveString(result, values, pattern, depth: depth + 1, maxDepth: maxDepth);
    }

    return result;
  }

  /// Build tool placeholder values from context.
  Map<String, String> _buildToolPlaceholderValues(PlaceholderContext ctx) {
    final values = <String, String>{
      'project-path': ctx.projectPath,
      'project-name': ctx.projectName,
      'workspace-root': ctx.workspaceRoot,
      'tool-name': ctx.toolName,
      'tool-version': ctx.toolVersion,
    };

    // Add custom tool placeholders
    for (final entry in toolPlaceholders.entries) {
      final resolver = entry.value.resolver;
      if (resolver != null) {
        try {
          values[entry.key] = resolver(ctx);
        } catch (_) {
          // Skip on error
        }
      }
    }

    return values;
  }

  /// Check if a directory should be skipped.
  ///
  /// Returns true if either:
  /// - tom_skip.yaml exists (global skip for all tools)
  /// - {basename}_skip.yaml exists (tool-specific skip)
  bool shouldSkipDirectory(String dirPath) {
    // Check global skip first
    if (exists(p.join(dirPath, kTomSkipYaml))) {
      return true;
    }
    // Check tool-specific skip
    if (exists(p.join(dirPath, skipFilename))) {
      return true;
    }
    return false;
  }

  /// Get the skip reason if a skip file exists.
  String? getSkipReason(String dirPath) {
    // Check global skip first
    final globalSkipPath = p.join(dirPath, kTomSkipYaml);
    if (exists(globalSkipPath)) {
      return _readSkipReason(globalSkipPath) ?? 'tom_skip.yaml (all tools)';
    }

    // Check tool-specific skip
    final toolSkipPath = p.join(dirPath, skipFilename);
    if (exists(toolSkipPath)) {
      return _readSkipReason(toolSkipPath) ?? skipFilename;
    }

    return null;
  }

  String? _readSkipReason(String filePath) {
    try {
      final content = read(filePath).toParagraph();
      if (content.trim().isEmpty) return null;

      final yaml = loadYaml(content);
      if (yaml is YamlMap) {
        final reason = yaml['reason'];
        if (reason is String) return reason;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// Resolve placeholders in a string template.
///
/// Supports:
/// - @[name] - Define placeholders
/// - @{name} - Tool placeholders
/// - $VAR or $[VAR] - Environment variables (if resolveEnvVars is true)
///
/// Returns the resolved string. Unresolved placeholders remain unchanged.
String resolvePlaceholders(
  String template,
  Map<String, String> values, {
  bool resolveEnvVars = false,
  int maxDepth = 10,
}) {
  var result = template;

  // Resolve @[...] and @{...} placeholders
  for (var depth = 0; depth < maxDepth; depth++) {
    final previous = result;

    // Resolve @[name]
    result = result.replaceAllMapped(_definePlaceholderPattern, (match) {
      final name = match.group(1)!;
      return values[name] ?? match.group(0)!;
    });

    // Resolve @{name}
    result = result.replaceAllMapped(_toolPlaceholderPattern, (match) {
      final name = match.group(1)!;
      return values[name] ?? match.group(0)!;
    });

    if (result == previous) break;
  }

  // Resolve environment variables if requested
  if (resolveEnvVars) {
    result = result.replaceAllMapped(_envVarPattern, (match) {
      final name = match.group(1) ?? match.group(2)!;
      return Platform.environment[name] ?? match.group(0)!;
    });
  }

  return result;
}
