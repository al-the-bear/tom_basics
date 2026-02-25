import 'package:dcli/dcli.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'yaml_utils.dart';

/// Utilities for working with build.yaml files.
///
/// Provides common functionality for detecting builder definitions vs
/// consumer configurations in build.yaml files. This helps CLI tools
/// distinguish between:
/// - Packages that DEFINE a builder (have `builders:` section) - should be ignored
/// - Packages that USE a builder (have `targets:` section with builder config)

/// Check if a directory contains a build.yaml with a `builders:` section.
///
/// Packages with `builders:` sections are builder DEFINITIONS and should
/// typically be ignored by CLI tools that process builder consumers.
///
/// Returns true if build.yaml exists and contains a top-level `builders:` key.
bool isBuildYamlBuilderDefinition(String dirPath) {
  final buildYamlPath = p.join(dirPath, 'build.yaml');

  if (!exists(buildYamlPath)) return false;

  try {
    final content = read(buildYamlPath).toParagraph();
    final yaml = loadYaml(content) as YamlMap?;
    if (yaml == null) return false;

    // Check for top-level `builders:` section
    return yaml.containsKey('builders');
  } catch (_) {
    return false;
  }
}

/// Check if a directory's build.yaml has consumer configuration for a specific builder.
///
/// Looks for `targets.$default.builders.{builderName}` configuration.
///
/// [dirPath] - Directory containing build.yaml
/// [builderName] - Full builder name (e.g., 'tom_d4rt_generator:d4rt_bridge_builder')
///
/// Returns true if build.yaml has consumer config for the specified builder.
bool hasBuildYamlConsumerConfig(String dirPath, String builderName) {
  final buildYamlPath = p.join(dirPath, 'build.yaml');

  if (!exists(buildYamlPath)) return false;

  try {
    final content = read(buildYamlPath).toParagraph();
    final yaml = loadYaml(content) as YamlMap?;
    if (yaml == null) return false;

    // Look for targets.$default.builders.{builderName}
    final targets = yaml['targets'] as YamlMap?;
    if (targets == null) return false;

    final defaultTarget = targets[r'$default'] as YamlMap?;
    if (defaultTarget == null) return false;

    final builders = defaultTarget['builders'] as YamlMap?;
    if (builders == null) return false;

    return builders.containsKey(builderName);
  } catch (_) {
    return false;
  }
}

/// Get the options map for a specific builder from build.yaml.
///
/// Extracts `targets.$default.builders.{builderName}.options` as a Map.
///
/// [dirPath] - Directory containing build.yaml
/// [builderName] - Full builder name (e.g., 'tom_build_kit:version_builder')
///
/// Returns the options map, or null if not found or build.yaml doesn't exist.
Map<String, dynamic>? getBuildYamlBuilderOptions(
  String dirPath,
  String builderName,
) {
  final buildYamlPath = p.join(dirPath, 'build.yaml');

  if (!exists(buildYamlPath)) return null;

  try {
    final content = read(buildYamlPath).toParagraph();
    final yaml = loadYaml(content) as YamlMap?;
    if (yaml == null) return null;

    // Look for targets.$default.builders.{builderName}.options
    final targets = yaml['targets'] as YamlMap?;
    if (targets == null) return null;

    final defaultTarget = targets[r'$default'] as YamlMap?;
    if (defaultTarget == null) return null;

    final builders = defaultTarget['builders'] as YamlMap?;
    if (builders == null) return null;

    final builderConfig = builders[builderName] as YamlMap?;
    if (builderConfig == null) return null;

    final options = builderConfig['options'] as YamlMap?;
    if (options == null) return null;

    return yamlToMap(options);
  } catch (_) {
    return null;
  }
}

/// Check if a builder is enabled in build.yaml.
///
/// Looks for `targets.$default.builders.{builderName}.enabled`.
/// Returns true if enabled is true or not specified (default is enabled).
/// Returns false only if explicitly set to false.
///
/// [dirPath] - Directory containing build.yaml
/// [builderName] - Full builder name
bool isBuildYamlBuilderEnabled(String dirPath, String builderName) {
  final buildYamlPath = p.join(dirPath, 'build.yaml');

  if (!exists(buildYamlPath)) return false;

  try {
    final content = read(buildYamlPath).toParagraph();
    final yaml = loadYaml(content) as YamlMap?;
    if (yaml == null) return false;

    final targets = yaml['targets'] as YamlMap?;
    if (targets == null) return false;

    final defaultTarget = targets[r'$default'] as YamlMap?;
    if (defaultTarget == null) return false;

    final builders = defaultTarget['builders'] as YamlMap?;
    if (builders == null) return false;

    final builderConfig = builders[builderName] as YamlMap?;
    if (builderConfig == null) return false;

    // Default is enabled if builder config exists
    final enabled = builderConfig['enabled'];
    if (enabled == null) return true;
    return enabled == true;
  } catch (_) {
    return false;
  }
}
