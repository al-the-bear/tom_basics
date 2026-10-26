/// A repository without a working tree: objects, refs, and the operations a
/// storage backend needs — read a path at a commit, edit a tree, commit.
library;

import 'dart:typed_data';

import 'object_id.dart';
import 'object_store.dart';
import 'objects.dart';
import 'ref_store.dart';

/// An object a repository was asked for and does not have.
class GitMissingObjectException implements Exception {
  GitMissingObjectException(this.id, [this.wanted]);

  final GitObjectId id;
  final String? wanted;

  @override
  String toString() =>
      'GitMissingObjectException($id${wanted == null ? '' : ', a $wanted'})';
}

/// One file or folder found under a path.
class GitPathEntry {
  const GitPathEntry({
    required this.path,
    required this.mode,
    required this.id,
  });

  /// The path relative to where the listing started.
  final String path;
  final String mode;
  final GitObjectId id;

  bool get isTree => mode == GitTreeEntry.treeMode;

  @override
  String toString() => '$mode $path $id';
}

/// A bare repository: an object store and a ref store.
///
/// There is no index and no working tree. A change is made by [editTree] —
/// writing new blobs and rewriting only the trees on the changed paths — and
/// recorded by [commit]; nothing is checked out.
class GitRepository {
  GitRepository({required this.objects, required this.refs});

  /// A repository held entirely in memory.
  factory GitRepository.memory() =>
      GitRepository(objects: GitMemoryObjectStore(), refs: GitMemoryRefStore());

  final GitObjectStore objects;
  final GitRefStore refs;

  Future<GitObject> readObject(GitObjectId id, [GitObjectType? type]) async {
    final object = await objects.read(id);
    if (object == null) throw GitMissingObjectException(id, type?.typeName);
    if (type != null && object.type != type) {
      throw FormatException(
        '$id is a ${object.type.typeName}, not a '
        '${type.typeName}',
      );
    }
    return object;
  }

  Future<GitCommit> readCommit(GitObjectId id) async =>
      GitCommit.decode((await readObject(id, GitObjectType.commit)).content);

  Future<GitTree> readTree(GitObjectId id) async =>
      GitTree.decode((await readObject(id, GitObjectType.tree)).content);

  Future<Uint8List> readBlob(GitObjectId id) async =>
      (await readObject(id, GitObjectType.blob)).content;

  /// The entry at [path] (slash-separated, relative to the root) in the tree
  /// [root], or null when nothing is there. The empty path names the root.
  Future<GitTreeEntry?> entryAt(GitObjectId root, String path) async {
    final segments = _segments(path);
    if (segments.isEmpty) {
      return GitTreeEntry(mode: GitTreeEntry.treeMode, name: '', id: root);
    }
    var tree = await readTree(root);
    for (var i = 0; i < segments.length; i++) {
      final entry = tree[segments[i]];
      if (entry == null) return null;
      if (i == segments.length - 1) return entry;
      if (!entry.isTree) return null;
      tree = await readTree(entry.id);
    }
    return null;
  }

  /// Every file under the tree [root] at [path], recursively, with paths
  /// relative to [path]; folders are listed too when [includeTrees].
  Future<List<GitPathEntry>> listFiles(
    GitObjectId root,
    String path, {
    bool includeTrees = false,
  }) async {
    final start = await entryAt(root, path);
    if (start == null || !start.isTree) return const [];
    final out = <GitPathEntry>[];
    Future<void> walk(GitObjectId treeId, String prefix) async {
      for (final e in (await readTree(treeId)).entries) {
        final p = prefix.isEmpty ? e.name : '$prefix/${e.name}';
        if (e.isTree) {
          if (includeTrees) {
            out.add(GitPathEntry(path: p, mode: e.mode, id: e.id));
          }
          await walk(e.id, p);
        } else {
          out.add(GitPathEntry(path: p, mode: e.mode, id: e.id));
        }
      }
    }

    await walk(start.id, '');
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  /// A new root tree: [base] (or an empty tree) with every file of [writes]
  /// stored at its path and every path of [deletes] removed — a file, or a
  /// whole folder. Only the trees on the changed paths are rewritten; every
  /// other subtree keeps its id. Folders left empty disappear, as git has no
  /// empty trees.
  Future<GitObjectId> editTree(
    GitObjectId? base, {
    Map<String, List<int>> writes = const {},
    Set<String> deletes = const {},
  }) async {
    final root = _EditNode();
    for (final d in deletes) {
      final segments = _segments(d);
      if (segments.isEmpty) {
        root.clear = true;
        continue;
      }
      root
          .at(segments.sublist(0, segments.length - 1))
          .deletes
          .add(segments.last);
    }
    for (final w in writes.entries) {
      final segments = _segments(w.key);
      if (segments.isEmpty) {
        throw ArgumentError.value(w.key, 'writes', 'A file needs a path');
      }
      final blob = GitObject.blob(w.value);
      await objects.write(blob);
      root.at(segments.sublist(0, segments.length - 1)).files[segments.last] =
          blob.id;
    }
    final result = await _apply(base, root);
    return result ?? await objects.write(GitTree.empty.toObject());
  }

  Future<GitObjectId?> _apply(GitObjectId? treeId, _EditNode node) async {
    final entries = <String, GitTreeEntry>{};
    if (treeId != null && !node.clear) {
      for (final e in (await readTree(treeId)).entries) {
        entries[e.name] = e;
      }
    }
    for (final name in node.deletes) {
      entries.remove(name);
    }
    for (final file in node.files.entries) {
      final existing = entries[file.key];
      entries[file.key] = GitTreeEntry(
        // An executable stays executable when its content changes.
        mode: existing != null && existing.isBlob
            ? existing.mode
            : GitTreeEntry.fileMode,
        name: file.key,
        id: file.value,
      );
    }
    for (final child in node.children.entries) {
      final existing = entries[child.key];
      final childId = await _apply(
        existing != null && existing.isTree ? existing.id : null,
        child.value,
      );
      if (childId == null) {
        entries.remove(child.key);
      } else {
        entries[child.key] = GitTreeEntry(
          mode: GitTreeEntry.treeMode,
          name: child.key,
          id: childId,
        );
      }
    }
    if (entries.isEmpty) return null;
    return objects.write(GitTree(entries.values).toObject());
  }

  /// Stores a commit of [tree] on [parents] and returns its id. Moves no ref.
  Future<GitObjectId> commit({
    required GitObjectId tree,
    required List<GitObjectId> parents,
    required String message,
    required GitPerson author,
    GitPerson? committer,
  }) => objects.write(
    GitCommit(
      tree: tree,
      parents: parents,
      author: author,
      committer: committer ?? author,
      message: message.endsWith('\n') ? message : '$message\n',
    ).toObject(),
  );

  /// Every object reachable from [tips] that is not reachable from
  /// [excluded] — what a push of [tips] must send to a remote that has
  /// [excluded].
  ///
  /// Excluded trees are walked as well as excluded commits, so an unchanged
  /// subtree of a new commit is recognised as already present and not sent.
  Future<List<GitObject>> objectsToSend(
    Iterable<GitObjectId> tips, {
    Iterable<GitObjectId> excluded = const [],
  }) async {
    final known = <GitObjectId>{};
    Future<void> markTree(GitObjectId id) async {
      if (!known.add(id)) return;
      final object = await objects.read(id);
      if (object == null) return;
      for (final e in GitTree.decode(object.content).entries) {
        if (e.isTree) {
          await markTree(e.id);
        } else {
          known.add(e.id);
        }
      }
    }

    // The excluded side: each commit and its root tree. History behind an
    // excluded commit is the remote's already, so its parents need not be
    // walked.
    for (final id in excluded) {
      if (id.isZero) continue;
      final object = await objects.read(id);
      if (object == null || object.type != GitObjectType.commit) continue;
      known.add(id);
      await markTree(GitCommit.decode(object.content).tree);
    }

    final out = <GitObject>[];
    Future<void> sendTree(GitObjectId id) async {
      if (!known.add(id)) return;
      final tree = await readObject(id, GitObjectType.tree);
      out.add(tree);
      for (final e in GitTree.decode(tree.content).entries) {
        if (e.isTree) {
          await sendTree(e.id);
        } else if (e.mode != GitTreeEntry.gitlinkMode && known.add(e.id)) {
          out.add(await readObject(e.id));
        }
      }
    }

    final pending = [...tips];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (known.contains(id)) continue;
      known.add(id);
      final object = await readObject(id, GitObjectType.commit);
      out.add(object);
      final commit = GitCommit.decode(object.content);
      await sendTree(commit.tree);
      pending.addAll(commit.parents);
    }
    return out;
  }

  static List<String> _segments(String path) => [
    for (final s in path.split('/'))
      if (s.isNotEmpty) s,
  ];
}

class _EditNode {
  bool clear = false;
  final Map<String, GitObjectId> files = {};
  final Set<String> deletes = {};
  final Map<String, _EditNode> children = {};

  _EditNode at(List<String> segments) {
    var node = this;
    for (final s in segments) {
      node = node.children.putIfAbsent(s, _EditNode.new);
    }
    return node;
  }
}
