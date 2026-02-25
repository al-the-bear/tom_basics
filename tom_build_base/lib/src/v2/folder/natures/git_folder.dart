import 'dart:io';

import '../run_folder.dart';

/// Git repository nature.
///
/// Detected when a folder contains `.git/` directory or `.git` file
/// (for submodules).
class GitFolder extends RunFolder {
  /// Current branch name.
  final String currentBranch;

  /// Whether there are uncommitted changes.
  final bool hasUncommittedChanges;

  /// Whether there are commits not pushed to remote.
  final bool hasUnpushedCommits;

  /// Whether this is a git submodule (has .git file instead of .git/).
  final bool isSubmodule;

  /// List of configured remotes.
  final List<String> remotes;

  /// Submodule name (if this is a submodule, extracted from parent's .gitmodules).
  final String? submoduleName;

  GitFolder(
    super.fsFolder, {
    required this.currentBranch,
    this.hasUncommittedChanges = false,
    this.hasUnpushedCommits = false,
    this.isSubmodule = false,
    this.remotes = const [],
    this.submoduleName,
  });

  /// Check if a folder is a git repository.
  static bool isGitFolder(String dirPath) {
    final gitDir = Directory('$dirPath/.git');
    final gitFile = File('$dirPath/.git');
    return gitDir.existsSync() || gitFile.existsSync();
  }

  /// Check if this is a submodule (has .git file instead of directory).
  static bool isSubmoduleFolder(String dirPath) {
    final gitFile = File('$dirPath/.git');
    return gitFile.existsSync() && !Directory('$dirPath/.git').existsSync();
  }

  @override
  String toString() => 'GitFolder($path, branch: $currentBranch)';
}
