import 'dart:io';

import 'package:path/path.dart' as p;

/// Filesystem folder during scanning (minimal info).
///
/// Represents a folder discovered during filesystem scanning, before
/// nature detection. This is a lightweight class used during the
/// initial scan phase.
class FsFolder {
  /// Absolute path to the folder.
  final String path;

  /// List of detected natures (populated by NatureDetector).
  final List<dynamic> natures = [];

  FsFolder({required this.path});

  /// Folder name (basename of path).
  String get name => p.basename(path);

  /// Check if the folder exists on disk.
  bool get exists => Directory(path).existsSync();

  @override
  String toString() => 'FsFolder($path)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsFolder && runtimeType == other.runtimeType && path == other.path;

  @override
  int get hashCode => path.hashCode;
}
