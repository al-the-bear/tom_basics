import 'dart:io';

import '../run_folder.dart';

/// Buildkit configuration nature.
///
/// Detected when folder contains `buildkit.yaml`.
class BuildkitFolder extends RunFolder {
  /// Project ID from buildkit.yaml (short mnemonic like "BB", "D4G").
  final String? projectId;

  /// Project name from buildkit.yaml.
  final String? projectName;

  /// Recursive flag from buildkit.yaml (default: true).
  final bool recursive;

  /// Raw config map from buildkit.yaml.
  final Map<String, dynamic> config;

  BuildkitFolder(
    super.fsFolder, {
    this.projectId,
    this.projectName,
    this.recursive = true,
    this.config = const {},
  });

  /// Check if a folder has buildkit.yaml.
  static bool hasBuildkitYaml(String dirPath) {
    return File('$dirPath/buildkit.yaml').existsSync();
  }

  @override
  String toString() => 'BuildkitFolder($path, id: $projectId, name: $projectName)';
}

/// Build runner (build.yaml) nature.
///
/// Detected when folder contains `build.yaml`.
class BuildRunnerFolder extends RunFolder {
  /// Raw config map from build.yaml.
  final Map<String, dynamic> config;

  BuildRunnerFolder(
    super.fsFolder, {
    this.config = const {},
  });

  /// Check if a folder has build.yaml.
  static bool hasBuildYaml(String dirPath) {
    return File('$dirPath/build.yaml').existsSync();
  }

  @override
  String toString() => 'BuildRunnerFolder($path)';
}

/// Tom project configuration nature.
///
/// Detected when folder contains `tom_project.yaml`.
class TomBuildFolder extends RunFolder {
  /// Project name from tom_project.yaml (e.g., "buildkit", "core-kernel").
  final String? projectName;

  /// Short project ID from tom_project.yaml (e.g., "BK", "CK").
  final String? shortId;

  /// Raw config map from tom_project.yaml.
  final Map<String, dynamic> config;

  TomBuildFolder(
    super.fsFolder, {
    this.projectName,
    this.shortId,
    this.config = const {},
  });

  /// Check if a folder has tom_project.yaml.
  static bool hasTomProjectYaml(String dirPath) {
    return File('$dirPath/tom_project.yaml').existsSync();
  }

  @override
  String toString() => 'TomBuildFolder($path, name: $projectName, id: $shortId)';
}

/// Tom build master configuration nature.
///
/// Detected when folder contains `buildkit_master.yaml`.
class TomBuildMasterFolder extends RunFolder {
  /// Raw config map from buildkit_master.yaml.
  final Map<String, dynamic> config;

  TomBuildMasterFolder(
    super.fsFolder, {
    this.config = const {},
  });

  /// Check if a folder has buildkit_master.yaml.
  static bool hasTomMasterYaml(String dirPath) {
    return File('$dirPath/buildkit_master.yaml').existsSync();
  }

  @override
  String toString() => 'TomBuildMasterFolder($path)';
}
