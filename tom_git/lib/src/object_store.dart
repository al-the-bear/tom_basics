/// Where objects live.
library;

import 'dart:typed_data';

import 'object_id.dart';
import 'objects.dart';
import 'pack.dart';

/// A place objects are read from and written to.
abstract class GitObjectStore {
  const GitObjectStore();

  /// The object with [id], or null when this store does not have it.
  Future<GitObject?> read(GitObjectId id);

  /// Whether this store has [id].
  Future<bool> contains(GitObjectId id) async => await read(id) != null;

  /// Stores [object] and returns its id. Storing an object already present
  /// changes nothing.
  Future<GitObjectId> write(GitObject object);

  /// Stores every object of [objects]. A store may write them as one unit —
  /// a directory store writes one pack — so prefer this for many objects.
  Future<void> writeAll(Iterable<GitObject> objects) async {
    for (final object in objects) {
      await write(object);
    }
  }

  /// Stores every object of a received [pack]. A delta whose base is not in
  /// the pack is resolved against this store.
  ///
  /// A directory store keeps the pack as it arrived, with an index beside it;
  /// this default stores the objects one by one.
  Future<void> writePack(Uint8List pack) async {
    final parsed = await gitReadPack(pack, external: read);
    await writeAll(parsed.objects.map((o) => o.object));
  }
}

/// Objects held in memory.
class GitMemoryObjectStore extends GitObjectStore {
  final Map<GitObjectId, GitObject> _objects = {};

  int get length => _objects.length;

  @override
  Future<GitObject?> read(GitObjectId id) async => _objects[id];

  @override
  Future<bool> contains(GitObjectId id) async => _objects.containsKey(id);

  @override
  Future<GitObjectId> write(GitObject object) async {
    final id = object.id;
    _objects.putIfAbsent(id, () => object);
    return id;
  }
}
