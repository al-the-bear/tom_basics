import 'dart:io';

import '../run_folder.dart';

/// Git repository nature.
///
/// Detected when a folder contains a `.git/` directory (a clone) or a `.git`
/// file (a submodule checkout or a worktree).
class GitFolder extends RunFolder {
  /// Current branch name.
  final String currentBranch;

  /// Whether there are uncommitted changes.
  final bool hasUncommittedChanges;

  /// Whether there are commits not pushed to remote.
  final bool hasUnpushedCommits;

  /// True when `.git` is a file: a submodule checkout or a worktree.
  ///
  /// Information only: ordering and the `--modules` filters do not depend
  /// on it (an independent clone has a `.git` directory and is false).
  final bool isSubmodule;

  /// List of configured remotes.
  final List<String> remotes;

  /// When `.git` is a file: the submodule name from its `gitdir:` path
  /// (`.git/modules/<name>`), else the folder name. Null for a `.git`
  /// directory. `--modules` matches it besides the path.
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

  /// True when `.git` in [dirPath] is a file: a submodule checkout or a
  /// worktree.
  static bool isSubmoduleFolder(String dirPath) {
    final gitFile = File('$dirPath/.git');
    return gitFile.existsSync() && !Directory('$dirPath/.git').existsSync();
  }

  @override
  String toString() => 'GitFolder($path, branch: $currentBranch)';
}
