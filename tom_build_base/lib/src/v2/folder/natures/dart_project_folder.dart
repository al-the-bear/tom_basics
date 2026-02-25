import 'dart:io';

import '../run_folder.dart';

/// Base class for Dart project natures.
///
/// Detected when a folder contains `pubspec.yaml`.
/// Can be instantiated directly for generic Dart projects that don't fit
/// specific subtypes (FlutterProjectFolder, DartConsoleFolder, DartPackageFolder).
class DartProjectFolder extends RunFolder {
  /// Project name from pubspec.yaml.
  final String projectName;

  /// Version from pubspec.yaml.
  final String? version;

  /// Dependencies map from pubspec.yaml.
  final Map<String, dynamic> dependencies;

  /// Dev dependencies map from pubspec.yaml.
  final Map<String, dynamic> devDependencies;

  /// Raw pubspec content as parsed YAML.
  final Map<String, dynamic> pubspec;

  DartProjectFolder(
    super.fsFolder, {
    required this.projectName,
    this.version,
    this.dependencies = const {},
    this.devDependencies = const {},
    this.pubspec = const {},
  });

  /// Whether this package is publishable to pub.dev.
  ///
  /// Returns true if the package:
  /// - Has a version
  /// - Does NOT have `publish_to: none` in pubspec.yaml
  bool get isPublishable {
    if (version == null || version!.isEmpty) return false;
    final publishTo = pubspec['publish_to'];
    return publishTo != 'none';
  }

  /// Check if a folder is a Dart project.
  static bool isDartProject(String dirPath) {
    return File('$dirPath/pubspec.yaml').existsSync();
  }

  @override
  String toString() => 'DartProjectFolder($path, name: $projectName)';
}

/// Flutter project nature.
///
/// Detected when pubspec.yaml contains `flutter` SDK dependency.
class FlutterProjectFolder extends DartProjectFolder {
  /// Platforms enabled for this Flutter project.
  final List<String> platforms;

  /// Whether this is a Flutter plugin.
  final bool isPlugin;

  FlutterProjectFolder(
    super.fsFolder, {
    required super.projectName,
    super.version,
    super.dependencies,
    super.devDependencies,
    super.pubspec,
    this.platforms = const [],
    this.isPlugin = false,
  });

  @override
  String toString() => 'FlutterProjectFolder($path, name: $projectName)';
}

/// Dart console application nature.
///
/// Detected when folder has `pubspec.yaml` and `bin/` directory but no Flutter SDK.
class DartConsoleFolder extends DartProjectFolder {
  /// List of executable entry points in bin/.
  final List<String> executables;

  DartConsoleFolder(
    super.fsFolder, {
    required super.projectName,
    super.version,
    super.dependencies,
    super.devDependencies,
    super.pubspec,
    this.executables = const [],
  });

  @override
  String toString() => 'DartConsoleFolder($path, name: $projectName)';
}

/// Dart package nature (library).
///
/// Detected when folder has `pubspec.yaml` AND `lib/src/` directory exists.
class DartPackageFolder extends DartProjectFolder {
  /// Whether the package has lib/src/ directory.
  final bool hasLibSrc;

  DartPackageFolder(
    super.fsFolder, {
    required super.projectName,
    super.version,
    super.dependencies,
    super.devDependencies,
    super.pubspec,
    this.hasLibSrc = false,
  });

  @override
  String toString() => 'DartPackageFolder($path, name: $projectName)';
}
