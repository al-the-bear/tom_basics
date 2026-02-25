import 'dart:io';

import 'package:path/path.dart' as p;

/// Walks up the directory tree to find "anchor" directories.
///
/// An **anchor** is a directory that marks a workspace or repository root:
/// - `.git` directory or file (git repo or submodule)
/// - `tom_workspace.yaml` (Tom workspace root)
/// - `buildkit_master.yaml` (buildkit workspace root)
///
/// This is useful for finding the appropriate workspace root when a command
/// is run from deep within a project structure.
///
/// Example:
/// ```dart
/// final walker = AnchorWalker();
/// final anchors = walker.collectAnchors('/path/to/deep/nested/folder');
/// // Returns anchors closest-first, e.g.:
/// // ['/path/to/deep', '/path/to', '/path']
/// ```
class AnchorWalker {
  /// Additional anchor markers to check (beyond the defaults).
  final List<String> additionalMarkers;

  /// Whether to print verbose output.
  final bool verbose;

  /// Output function for verbose messages.
  final void Function(String)? log;

  /// Default anchor markers checked for every directory.
  static const defaultMarkers = [
    '.git', // Git repository or submodule
    'tom_workspace.yaml', // Tom workspace root
    'buildkit_master.yaml', // Buildkit workspace root
  ];

  const AnchorWalker({
    this.additionalMarkers = const [],
    this.verbose = false,
    this.log,
  });

  /// Walk up from [startDir] collecting anchor directories.
  ///
  /// Returns anchors ordered closest-first (starting directory first).
  /// Stops at the filesystem root or on permission errors.
  List<String> collectAnchors(String startDir) {
    final anchors = <String>[];
    var current = p.normalize(p.absolute(startDir));
    final root = p.rootPrefix(current);

    while (current != root) {
      try {
        if (isAnchor(current)) {
          anchors.add(current);
        }
      } on FileSystemException catch (e) {
        // Permission denied or other OS error — treat as boundary.
        if (verbose) {
          log?.call('AnchorWalker: stopped at $current (${e.message})');
        }
        break;
      }
      current = p.dirname(current);
    }

    // Also check the filesystem root itself.
    try {
      if (isAnchor(root)) {
        anchors.add(root);
      }
    } on FileSystemException {
      // Ignore.
    }

    return anchors;
  }

  /// Find the nearest anchor from [startDir].
  ///
  /// Returns null if no anchor is found before reaching the filesystem root.
  String? findNearestAnchor(String startDir) {
    final anchors = collectAnchors(startDir);
    return anchors.isNotEmpty ? anchors.first : null;
  }

  /// Whether [dir] is an anchor directory.
  bool isAnchor(String dir) {
    final allMarkers = [...defaultMarkers, ...additionalMarkers];

    for (final marker in allMarkers) {
      final markerPath = p.join(dir, marker);
      // Check both file and directory (e.g., .git can be either)
      if (File(markerPath).existsSync() || Directory(markerPath).existsSync()) {
        return true;
      }
    }

    return false;
  }

  /// Get the specific marker that makes [dir] an anchor.
  ///
  /// Returns null if [dir] is not an anchor.
  String? getAnchorMarker(String dir) {
    final allMarkers = [...defaultMarkers, ...additionalMarkers];

    for (final marker in allMarkers) {
      final markerPath = p.join(dir, marker);
      if (File(markerPath).existsSync() || Directory(markerPath).existsSync()) {
        return marker;
      }
    }

    return null;
  }
}
