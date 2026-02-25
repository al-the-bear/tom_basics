import 'package:path/path.dart' as p;

import '../folder/fs_folder.dart';
import '../folder/natures/dart_project_folder.dart';
import '../folder/natures/git_folder.dart';
import '../folder/run_folder.dart';
import 'traversal_info.dart';

/// Context provided to commands during execution.
///
/// Contains the folder being processed, its detected natures,
/// and traversal configuration.
class CommandContext {
  /// The scanned folder.
  final FsFolder fsFolder;

  /// Detected natures for this folder (GitFolder, DartProjectFolder, etc.).
  final List<RunFolder> natures;

  /// Execution root path.
  final String executionRoot;

  /// Traversal configuration.
  final BaseTraversalInfo? traversal;

  CommandContext({
    required this.fsFolder,
    required this.natures,
    required this.executionRoot,
    this.traversal,
  });

  /// Absolute path to folder.
  String get path => fsFolder.path;

  /// Folder name.
  String get name => fsFolder.name;

  /// Relative path from execution root.
  String get relativePath => p.relative(path, from: executionRoot);

  /// Check if folder has a specific nature.
  bool hasNature<T extends RunFolder>() => natures.whereType<T>().isNotEmpty;

  /// Get a specific nature (throws if not present).
  T getNature<T extends RunFolder>() {
    final matches = natures.whereType<T>();
    if (matches.isEmpty) {
      throw StateError('Folder $name does not have nature $T');
    }
    return matches.first;
  }

  /// Get a specific nature or null.
  T? tryGetNature<T extends RunFolder>() {
    final matches = natures.whereType<T>();
    return matches.isNotEmpty ? matches.first : null;
  }

  /// Check if this is a Dart project of any kind.
  bool get isDartProject => hasNature<DartProjectFolder>();

  /// Check if this is a git repository.
  bool get isGitRepo => hasNature<GitFolder>();

  @override
  String toString() => 'CommandContext($path, natures: ${natures.length})';
}
