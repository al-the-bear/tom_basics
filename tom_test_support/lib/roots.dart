/// The two directories above a package that its tests need, found by
/// **landmark** rather than by counting `..` segments.
///
/// What a suite reaches for up there is scratch space (`ztmp`) and the sibling
/// packages of its repository. A root derived by appending `..` to
/// `Directory.current` encodes an unwritten assumption: that the package sits
/// exactly where it sits today. Move the repository one level deeper and the
/// count silently addresses a different directory — and because what is looked
/// for up there is usually *optional* (a standalone checkout genuinely has no
/// workspace above it), the failure is not an error but a **skip for a reason
/// that is not true**, which reads exactly like a pass.
///
/// A walk upward for a landmark has neither problem: it is correct from any
/// depth, and "no landmark anywhere above" is exactly the condition a skip
/// claims to be reporting.
///
/// ## The two landmarks
///
/// `tom_repository.yaml` marks the root of a code repository and the
/// **directory** `.tom_metadata/` marks the workspace root. Neither appears at
/// another level, so the nearest match walking up is the right one. The
/// directory's existence is the signpost, not the generated manifest inside
/// it: the walk reads nothing and regenerates nothing, the same use a `.git`
/// directory gets.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// The file that marks the root of a code repository.
const tomRepositoryMarker = 'tom_repository.yaml';

/// The directory that marks the workspace root.
const tomWorkspaceMarker = '.tom_metadata';

/// The workspace root — the directory holding `.tom_metadata/` — or null when
/// the run is not inside one.
///
/// Null is a real answer and not a failure: a repository can be cloned on its
/// own, and a suite that reaches for the workspace has to be able to say
/// "there is no workspace here" rather than guess.
Directory? tomFindWorkspaceRoot({Directory? from}) => tomFindUp(
  from ?? Directory.current,
  (dir) => Directory(p.join(dir.path, tomWorkspaceMarker)).existsSync(),
);

/// The root of the repository the run is in — the nearest directory holding
/// `tom_repository.yaml`.
///
/// Throws rather than returning null, because a package that asks has one
/// above it: absence means the marker moved, and answering a question about
/// the repository from outside it is not something to continue past quietly.
Directory tomFindRepositoryRoot({Directory? from}) {
  final start = from ?? Directory.current;
  final found = tomFindUp(
    start,
    (dir) => File(p.join(dir.path, tomRepositoryMarker)).existsSync(),
  );
  if (found == null) {
    throw StateError(
      'No $tomRepositoryMarker above ${start.path} — the repository-root '
      'marker moved, so this suite can no longer find the packages it is '
      'about.',
    );
  }
  return found;
}

/// The workspace's `ztmp`, created on demand.
///
/// Temporary files belong there and never in `/tmp`, and suites that share one
/// (a lock, a report) need a path they agree on without either knowing where
/// the run was started from.
Directory tomWorkspaceZtmp({Directory? from}) {
  final root = tomFindWorkspaceRoot(from: from);
  if (root == null) {
    throw StateError(
      'No $tomWorkspaceMarker above ${(from ?? Directory.current).path}, so '
      'the workspace ztmp cannot be located.',
    );
  }
  return Directory(p.join(root.path, 'ztmp'))..createSync(recursive: true);
}

/// The nearest directory at or above [start] satisfying [holdsLandmark], or
/// null when the filesystem root is reached without one.
Directory? tomFindUp(Directory start, bool Function(Directory) holdsLandmark) {
  var dir = start.absolute;
  while (true) {
    if (holdsLandmark(dir)) return dir;
    final parent = dir.parent;
    // The filesystem root is its own parent: the only termination condition
    // there is, and the reason this is a loop rather than a recursion with a
    // depth cap — a cap would be another count to get wrong.
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}
