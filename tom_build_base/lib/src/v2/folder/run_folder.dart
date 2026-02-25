import 'fs_folder.dart';

/// Base class for folder natures detected during execution.
///
/// A folder can have multiple natures simultaneously (e.g., a folder
/// can be both a GitFolder and a DartProjectFolder). Each nature
/// provides type-specific information and capabilities.
abstract class RunFolder {
  /// The underlying filesystem folder.
  final FsFolder fsFolder;

  RunFolder(this.fsFolder);

  /// Absolute path to the folder.
  String get path => fsFolder.path;

  /// Folder name (basename of path).
  String get name => fsFolder.name;
}
