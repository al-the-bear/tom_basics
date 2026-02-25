import 'package:dcli/dcli.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'yaml_utils.dart';

/// Configuration loaded from buildkit.yaml for a specific tool.
/// 
/// This class provides shared CLI configuration options that are common
/// across Tom build tools. Tool-specific options are accessible via
/// [toolOptions].
class TomBuildConfig {
  /// Filename for the workspace-level build configuration.
  static const masterFilename = 'buildkit_master.yaml';

  /// Filename for the project-level build configuration.
  static const projectFilename = 'buildkit.yaml';
  /// Path to a single project directory.
  final String? project;
  
  /// Glob patterns for projects to process.
  final List<String> projects;
  
  /// Path to a specific config file.
  final String? config;
  
  /// Directory to scan for projects.
  final String? scan;
  
  /// Whether to process subprojects recursively.
  final bool recursive;
  
  /// Glob patterns for projects to exclude from processing.
  final List<String> exclude;

  /// Glob patterns to exclude projects by folder name.
  ///
  /// Unlike [exclude] which matches against full paths, these patterns
  /// match against the directory basename only (e.g., `zom_*`).
  final List<String> excludeProjects;

  /// Glob patterns to exclude from recursive traversal.
  final List<String> recursionExclude;
  
  /// Whether to show detailed output.
  final bool verbose;
  
  /// Tool-specific options as a raw map.
  /// Tools can extract additional options from this.
  final Map<String, dynamic> toolOptions;

  const TomBuildConfig({
    this.project,
    this.projects = const [],
    this.config,
    this.scan,
    this.recursive = false,
    this.exclude = const [],
    this.excludeProjects = const [],
    this.recursionExclude = const [],
    this.verbose = false,
    this.toolOptions = const {},
  });

  /// Load configuration from buildkit.yaml file for a specific tool.
  /// 
  /// [dir] - Directory containing buildkit.yaml
  /// [toolKey] - The tool's section key in the YAML (e.g., 'versioner')
  /// 
  /// Returns null if:
  /// - buildkit.yaml doesn't exist
  /// - The file is invalid YAML
  /// - The tool's section doesn't exist
  static TomBuildConfig? load({
    required String dir,
    required String toolKey,
  }) {
    return _loadFromFile(
      filePath: p.join(dir, projectFilename),
      toolKey: toolKey,
    );
  }

  /// Load configuration from buildkit_master.yaml for a specific tool.
  /// 
  /// [dir] - Directory containing buildkit_master.yaml
  /// [toolKey] - The tool's section key in the YAML
  /// 
  /// Returns null if not found or invalid.
  static TomBuildConfig? loadMaster({
    required String dir,
    required String toolKey,
  }) {
    return _loadFromFile(
      filePath: p.join(dir, masterFilename),
      toolKey: toolKey,
    );
  }

  /// Internal: load config from a specific YAML file path.
  ///
  /// For workspace-level (master) files, navigation fields (scan, recursive,
  /// exclude, recursion-exclude) are read from the shared `navigation:` section
  /// and used as defaults if the tool section doesn't define them.
  static TomBuildConfig? _loadFromFile({
    required String filePath,
    required String toolKey,
  }) {
    if (!exists(filePath)) return null;

    try {
      final content = read(filePath).toParagraph();
      final rootYaml = loadYaml(content) as YamlMap?;
      if (rootYaml == null) return null;

      // Look for tool's section
      final yaml = rootYaml[toolKey] as YamlMap?;
      if (yaml == null) return null;

      final toolConfig = TomBuildConfig.fromYamlMap(yaml);

      // Check for shared navigation: section (workspace-level config)
      final navYaml = rootYaml['navigation'] as YamlMap?;
      if (navYaml != null) {
        final navConfig = TomBuildConfig.fromYamlMap(navYaml);
        // Navigation section provides defaults; tool section overrides
        return navConfig.merge(toolConfig);
      }

      return toolConfig;
    } catch (_) {
      return null;
    }
  }

  /// Create a config from a YAML map (tool's section).
  factory TomBuildConfig.fromYamlMap(YamlMap yaml) {
    // Convert YamlMap to regular Map for toolOptions
    final toolOptions = <String, dynamic>{};
    for (final key in yaml.keys) {
      final value = yaml[key];
      if (value is YamlMap) {
        toolOptions[key.toString()] = yamlToMap(value);
      } else if (value is YamlList) {
        toolOptions[key.toString()] = yamlListToList(value);
      } else {
        toolOptions[key.toString()] = value;
      }
    }

    return TomBuildConfig(
      project: yaml['project'] as String?,
      projects: _toStringList(yaml['projects']),
      config: yaml['config'] as String?,
      scan: yaml['scan'] as String?,
      recursive: yaml['recursive'] as bool? ?? false,
      exclude: _toStringList(yaml['exclude']),
      excludeProjects: _toStringList(
        yaml['exclude-projects'] ?? yaml['excludeProjects'],
      ),
      recursionExclude: _toStringList(
        yaml['recursion-exclude'] ?? yaml['recursionExclude'],
      ),
      verbose: yaml['verbose'] as bool? ?? false,
      toolOptions: toolOptions,
    );
  }

  static List<String> _toStringList(dynamic value) {
    if (value == null) return [];
    if (value is String) return [value];
    if (value is YamlList) return value.map((e) => e.toString()).toList();
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }

  /// Check if any project/scan/config option is specified.
  bool get hasProjectOptions =>
      project != null || projects.isNotEmpty || config != null || scan != null;

  /// Merge with another config (other takes precedence for non-null values).
  TomBuildConfig merge(TomBuildConfig other) {
    return TomBuildConfig(
      project: other.project ?? project,
      projects: other.projects.isNotEmpty ? other.projects : projects,
      config: other.config ?? config,
      scan: other.scan ?? scan,
      recursive: other.recursive || recursive,
      exclude: other.exclude.isNotEmpty ? other.exclude : exclude,
      excludeProjects: other.excludeProjects.isNotEmpty
          ? other.excludeProjects
          : excludeProjects,
      recursionExclude: other.recursionExclude.isNotEmpty
          ? other.recursionExclude
          : recursionExclude,
      verbose: other.verbose || verbose,
      toolOptions: {...toolOptions, ...other.toolOptions},
    );
  }

  /// Create a copy with updated values.
  TomBuildConfig copyWith({
    String? project,
    List<String>? projects,
    String? config,
    String? scan,
    bool? recursive,
    List<String>? exclude,
    List<String>? excludeProjects,
    List<String>? recursionExclude,
    bool? verbose,
    Map<String, dynamic>? toolOptions,
  }) {
    return TomBuildConfig(
      project: project ?? this.project,
      projects: projects ?? this.projects,
      config: config ?? this.config,
      scan: scan ?? this.scan,
      recursive: recursive ?? this.recursive,
      exclude: exclude ?? this.exclude,
      excludeProjects: excludeProjects ?? this.excludeProjects,
      recursionExclude: recursionExclude ?? this.recursionExclude,
      verbose: verbose ?? this.verbose,
      toolOptions: toolOptions ?? this.toolOptions,
    );
  }
}

/// Check if a directory has buildkit.yaml with a specific tool section.
///
/// Returns true if the tool key is present in the YAML, even if the value
/// is null (bare key like `cleanup:` with no sub-keys). This allows tools
/// to be activated with just the key present, using workspace or default config.
bool hasTomBuildConfig(String dirPath, String toolKey) {
  final yamlPath = p.join(dirPath, TomBuildConfig.projectFilename);
  if (!exists(yamlPath)) return false;

  try {
    final content = read(yamlPath).toParagraph();
    final yaml = loadYaml(content) as YamlMap?;
    // Check containsKey instead of != null to support bare keys (cleanup:)
    return yaml != null && yaml.containsKey(toolKey);
  } catch (_) {
    return false;
  }
}
