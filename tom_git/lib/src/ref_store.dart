/// Named pointers to commits.
library;

import 'object_id.dart';

/// A ref update that lost a race: the ref was not where the caller expected.
class GitRefConflict implements Exception {
  GitRefConflict(this.name, {required this.expected, required this.actual});

  final String name;
  final GitObjectId? expected;
  final GitObjectId? actual;

  @override
  String toString() =>
      'GitRefConflict($name: expected ${expected ?? 'absent'}, '
      'found ${actual ?? 'absent'})';
}

/// Where refs live: full names such as `refs/heads/main` mapped to ids.
abstract class GitRefStore {
  const GitRefStore();

  /// The id [name] points at, or null when there is no such ref.
  Future<GitObjectId?> read(String name);

  /// Points [name] at [id]. With [expected] (use [GitObjectId.zero] for
  /// "must not exist yet") the update is refused with a [GitRefConflict]
  /// unless the ref is there now.
  Future<void> write(String name, GitObjectId id, {GitObjectId? expected});

  /// Removes [name]; removing an absent ref changes nothing.
  Future<void> delete(String name);

  /// Every ref whose name starts with [prefix].
  Future<Map<String, GitObjectId>> list([String prefix = 'refs/']);
}

/// Refs held in memory.
class GitMemoryRefStore extends GitRefStore {
  final Map<String, GitObjectId> _refs = {};

  @override
  Future<GitObjectId?> read(String name) async => _refs[name];

  @override
  Future<void> write(
    String name,
    GitObjectId id, {
    GitObjectId? expected,
  }) async {
    if (expected != null) {
      final actual = _refs[name];
      final matches = expected.isZero ? actual == null : actual == expected;
      if (!matches) {
        throw GitRefConflict(name, expected: expected, actual: actual);
      }
    }
    _refs[name] = id;
  }

  @override
  Future<void> delete(String name) async => _refs.remove(name);

  @override
  Future<Map<String, GitObjectId>> list([String prefix = 'refs/']) async => {
    for (final e in _refs.entries)
      if (e.key.startsWith(prefix)) e.key: e.value,
  };
}
