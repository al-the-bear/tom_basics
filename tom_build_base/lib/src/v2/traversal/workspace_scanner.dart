import 'dart:io';

import 'package:path/path.dart' as p;

import '../folder/fs_folder.dart';
import '../folder/run_folder.dart';
import '../folder/natures/dart_project_folder.dart';
import '../folder/natures/git_folder.dart';
import 'folder_scanner.dart';
import 'nature_detector.dart';

/// Result of workspace scanning with nature detection.
///
/// Provides type-safe access to scanned folders by their nature.
class ScanResults {
  /// All scanned folder contexts with their detected natures.
  final List<FolderContext> folders;

  ScanResults(this.folders);

  /// Get all folders that have a specific nature type.
  ///
  /// Example:
  /// ```dart
  /// var gitFolders = results.byNature<GitFolder>();
  /// var dartProjects = results.byNature<DartProjectFolder>();
  /// ```
  Iterable<T> byNature<T extends RunFolder>() {
    return folders
        .expand((f) => f.natures)
        .whereType<T>();
  }

  /// Get all FolderContexts that have a specific nature type.
  ///
  /// Useful when you need both the folder path and the nature object.
  Iterable<FolderContext> withNature<T extends RunFolder>() {
    return folders.where(
        (f) => f.natures.any((n) => n is T));
  }

  /// Get all folder paths.
  Iterable<String> get paths => folders.map((f) => f.path);
}

/// A scanned folder with its detected natures.
class FolderContext {
  /// The underlying filesystem folder.
  final FsFolder fsFolder;

  /// All natures detected for this folder.
  final List<RunFolder> natures;

  FolderContext({
    required this.fsFolder,
    required this.natures,
  });

  /// Path to the folder.
  String get path => fsFolder.path;

  /// Folder name.
  String get name => p.basename(path);

  /// Check if this folder has a specific nature.
  bool hasNature<T extends RunFolder>() =>
      natures.any((n) => n is T);

  /// Get a specific nature, or null if not present.
  T? getNature<T extends RunFolder>() {
    for (final nature in natures) {
      if (nature is T) return nature;
    }
    return null;
  }
}

/// Scans workspace directories and detects folder natures.
///
/// Combines [FolderScanner] and [NatureDetector] into a simple API
/// that returns typed results.
///
/// Example usage:
/// ```dart
/// final scanner = WorkspaceScanner();
/// final results = await scanner.scan('/path/to/workspace');
///
/// // Get all git repositories
/// var gitRepos = results.byNature<GitFolder>();
///
/// // Get all Dart projects
/// var dartProjects = results.byNature<DartProjectFolder>();
///
/// // Get publishable packages
/// var publishable = results.byNature<DartProjectFolder>()
///     .where((p) => p.isPublishable);
/// ```
class WorkspaceScanner {
  final FolderScanner _scanner;
  final NatureDetector _detector;
  final bool verbose;

  WorkspaceScanner({
    FolderScanner? scanner,
    NatureDetector? detector,
    this.verbose = false,
  })  : _scanner = scanner ?? FolderScanner(verbose: verbose),
        _detector = detector ?? NatureDetector();

  /// Scan a directory for projects and detect their natures.
  ///
  /// [root] - Root directory to scan (uses current directory if null).
  /// [recursive] - Whether to scan subdirectories.
  /// [recursionExclude] - Patterns for directories to skip during recursion.
  Future<ScanResults> scan(
    String? root, {
    bool recursive = true,
    List<String>? recursionExclude,
  }) async {
    final startPath = root ?? Directory.current.path;

    final fsFolders = await _scanner.scan(
      startPath,
      recursive: recursive,
      recursionExclude: recursionExclude ?? const [],
    );

    final contexts = <FolderContext>[];
    for (final folder in fsFolders) {
      final natures = _detector.detectNatures(folder);
      folder.natures.addAll(natures);
      contexts.add(FolderContext(
        fsFolder: folder,
        natures: natures,
      ));
    }

    return ScanResults(contexts);
  }

  /// Find all git repositories under [root].
  ///
  /// Convenience method that scans recursively and filters by GitFolder nature.
  /// Includes the root itself if it's a git repository.
  Future<List<GitFolder>> findGitRepos(String root) async {
    final results = await scan(root);
    return results.byNature<GitFolder>().toList();
  }

  /// Find all Dart projects under [root].
  ///
  /// Returns all folders with pubspec.yaml files.
  Future<List<DartProjectFolder>> findDartProjects(String root) async {
    final results = await scan(root);
    return results.byNature<DartProjectFolder>().toList();
  }

  /// Find all publishable Dart packages under [root].
  ///
  /// Returns packages where:
  /// - `publish_to` is not set to 'none'
  /// - Has a valid version string
  Future<List<DartProjectFolder>> findPublishable(String root) async {
    final projects = await findDartProjects(root);
    return projects.where((p) => p.isPublishable).toList();
  }

  // --- Convenience methods returning paths directly ---

  /// Find git repository paths (shallow workspace-aware search).
  ///
  /// This is the recommended method for workspace-level git operations.
  /// Searches root, direct children, and xternal/xternal_apps children.
  /// Drop-in replacement for legacy `_findGitRepositories` methods.
  List<String> findGitRepoPaths(String root) {
    final finder = GitRepoFinder();
    return finder.findWorkspaceRepos(root);
  }

  /// Find git repository paths recursively (deep search).
  ///
  /// Searches all subdirectories. Use [findGitRepoPaths] for workspace-level
  /// operations, this for comprehensive scanning.
  Future<List<String>> findGitRepoPathsDeep(String root) async {
    final repos = await findGitRepos(root);
    return repos.map((g) => g.fsFolder.path).toList();
  }

  /// Find all Dart project paths under [root].
  Future<List<String>> findDartProjectPaths(String root) async {
    final projects = await findDartProjects(root);
    return projects.map((p) => p.fsFolder.path).toList();
  }

  /// Find all publishable Dart package paths under [root].
  Future<List<String>> findPublishablePaths(String root) async {
    final projects = await findPublishable(root);
    return projects.map((p) => p.fsFolder.path).toList();
  }
}
