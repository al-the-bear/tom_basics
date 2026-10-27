/// A repository somebody works in, opened from a folder they picked.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../repository.dart';
import '../errors.dart';
import 'directory_repository.dart';

/// A repository on disk as a person keeps it: a working repository (its
/// `.git` folder, or a linked worktree's `.git` file), or a bare one.
///
/// [repository] reads and writes objects and branches in git's own layout, so
/// git sees every commit this library makes and this library sees git's. What
/// it never touches is a working tree or the index — which is why
/// [checkedOutBranches] exists: a commit moved onto a branch some working tree
/// has checked out leaves that tree and its index describing the commit
/// before, and `git status` then shows the new commit as a change to undo.
/// git refuses a push to such a branch for the same reason
/// (`receive.denyCurrentBranch`).
///
/// `HEAD` is read whenever it is asked about, never cached: the person may
/// check out another branch while the repository is open.
class GitLocalRepository {
  GitLocalRepository._({
    required this.folder,
    required this.gitDir,
    required this.commonDir,
    required this.isBare,
    required this.repository,
  });

  /// Opens the repository [folder] names: a folder holding `.git` (a folder,
  /// or a file reading `gitdir: <path>`), a bare repository, or a `.git`
  /// folder itself. Throws [GitNotARepositoryException] for anything else.
  factory GitLocalRepository.open(String folder) {
    final dotGit = p.join(folder, '.git');
    String gitDir;
    bool bare;
    if (Directory(dotGit).existsSync()) {
      gitDir = dotGit;
      bare = false;
    } else if (File(dotGit).existsSync()) {
      gitDir = _gitDirFromFile(File(dotGit), folder);
      bare = false;
    } else if (_isGitDir(folder)) {
      gitDir = folder;
      bare = _configSaysBare(folder);
    } else {
      throw GitNotARepositoryException(folder);
    }
    final commonDir = _commonDirOf(gitDir);
    if (!File(p.join(gitDir, 'HEAD')).existsSync() || !_isGitDir(commonDir)) {
      throw GitNotARepositoryException(folder);
    }
    return GitLocalRepository._(
      folder: folder,
      gitDir: gitDir,
      commonDir: commonDir,
      isBare: bare,
      repository: gitOpenDirectory(commonDir),
    );
  }

  /// The folder that was opened.
  final String folder;

  /// The git directory: `.git`, a linked worktree's directory, or the bare
  /// repository itself. Holds this repository's `HEAD`.
  final String gitDir;

  /// Where objects and branches live — [gitDir], or for a linked worktree the
  /// main repository's git directory its `commondir` names.
  final String commonDir;

  /// Whether no working tree belongs to [gitDir].
  final bool isBare;

  /// Objects and refs, over [commonDir].
  final GitRepository repository;

  /// The branch `HEAD` names, or null when it is detached. For a bare
  /// repository this is its default branch; for a working one, the branch
  /// checked out.
  String? headBranch() => _branchOf(File(p.join(gitDir, 'HEAD')));

  /// Every branch some working tree of this repository has checked out: the
  /// main working tree's (unless the repository is bare) and each linked
  /// worktree's.
  Set<String> checkedOutBranches() {
    final branches = <String>{};
    if (_hasMainWorktree()) {
      final main = _branchOf(File(p.join(commonDir, 'HEAD')));
      if (main != null) branches.add(main);
    }
    final worktrees = Directory(p.join(commonDir, 'worktrees'));
    if (worktrees.existsSync()) {
      for (final dir in worktrees.listSync().whereType<Directory>()) {
        final branch = _branchOf(File(p.join(dir.path, 'HEAD')));
        if (branch != null) branches.add(branch);
      }
    }
    return branches;
  }

  /// Whether [commonDir] belongs to a working tree: it is a `.git` folder,
  /// or a git directory whose config says it is not bare.
  bool _hasMainWorktree() =>
      p.basename(commonDir) == '.git' || !_configSaysBare(commonDir);

  static bool _isGitDir(String dir) =>
      File(p.join(dir, 'HEAD')).existsSync() &&
      Directory(p.join(dir, 'objects')).existsSync() &&
      Directory(p.join(dir, 'refs')).existsSync();

  /// `core.bare` from [gitDir]'s config; a git directory with no config, or
  /// none saying otherwise, is bare.
  static bool _configSaysBare(String gitDir) {
    final config = File(p.join(gitDir, 'config'));
    if (!config.existsSync()) return true;
    final match = RegExp(
      r'^\s*bare\s*=\s*(\w+)',
      multiLine: true,
    ).firstMatch(config.readAsStringSync());
    return match == null || match.group(1)!.toLowerCase() != 'false';
  }

  static String _gitDirFromFile(File dotGit, String folder) {
    final text = dotGit.readAsStringSync().trim();
    if (!text.startsWith('gitdir:')) throw GitNotARepositoryException(folder);
    final target = text.substring('gitdir:'.length).trim();
    return p.normalize(p.isAbsolute(target) ? target : p.join(folder, target));
  }

  static String _commonDirOf(String gitDir) {
    final file = File(p.join(gitDir, 'commondir'));
    if (!file.existsSync()) return gitDir;
    final target = file.readAsStringSync().trim();
    return p.normalize(p.isAbsolute(target) ? target : p.join(gitDir, target));
  }

  static String? _branchOf(File head) {
    if (!head.existsSync()) return null;
    final text = head.readAsStringSync().trim();
    const prefix = 'ref: refs/heads/';
    return text.startsWith(prefix) ? text.substring(prefix.length) : null;
  }
}
