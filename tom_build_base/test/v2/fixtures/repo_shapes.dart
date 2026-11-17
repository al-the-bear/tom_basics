import 'dart:io';

import 'package:path/path.dart' as p;

/// The two shapes a workspace's nested repositories come in.
enum RepoShape {
  /// Submodule checkouts: the root repository has a `.git` directory, every
  /// nested repository a `.git` file naming `<root>/.git/modules/<rel>`.
  submodules,

  /// Independent clones: every repository has a `.git` directory, and the
  /// repository it lies in ignores it with an anchored `.gitignore` entry.
  clones,
}

/// Makes [rel] (relative to [root], `.` for the root itself) a git
/// repository of [shape]. Create a parent repository before the
/// repositories inside it: a clone's entry goes into the `.gitignore` of the
/// nearest repository above it.
void makeRepo(String root, String rel, RepoShape shape) {
  final dir = p.normalize(p.join(root, rel));
  Directory(dir).createSync(recursive: true);
  final isRoot = p.equals(dir, root);
  if (isRoot || shape == RepoShape.clones) {
    Directory(p.join(dir, '.git')).createSync();
  } else {
    final modules = p.join(root, '.git', 'modules', p.normalize(rel));
    Directory(modules).createSync(recursive: true);
    File(p.join(dir, '.git')).writeAsStringSync('gitdir: $modules\n');
  }
  if (isRoot || shape != RepoShape.clones) return;
  final parent = _enclosingRepo(p.dirname(dir), root);
  if (parent == null) return;
  final entry = '/${p.posix.joinAll(p.split(p.relative(dir, from: parent)))}/';
  File(
    p.join(parent, '.gitignore'),
  ).writeAsStringSync('$entry\n', mode: FileMode.append);
}

/// The nearest folder at or above [dir], not above [root], that holds `.git`.
String? _enclosingRepo(String dir, String root) {
  var current = dir;
  while (true) {
    final git = p.join(current, '.git');
    if (Directory(git).existsSync() || File(git).existsSync()) return current;
    if (p.equals(current, root) || !p.isWithin(root, current)) return null;
    current = p.dirname(current);
  }
}
