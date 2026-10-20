/// The ordering primitives of canonical YAML (rule 1 of `yaml_emit.dart`):
/// known keys first, the rest sorted; list items sorted by an id.
///
/// One implementation, because a model that writes its own map and the codec
/// that canonicalizes a body holding it must agree byte for byte: two orderings
/// of one mapping is a spurious edit on every save that passes through both.
library;

/// [known] keys first in their listed order, then the rest sorted by code
/// point; [nested] rewrites a named key's value. Keys that are not strings are
/// dropped — a fragment's keys are strings, and a mapping that is not
/// string-keyed has no canonical form to give.
Map<String, Object?> tomOrderedMapping(
  Map<Object?, Object?> mapping,
  List<String> known, {
  Map<String, Object? Function(Object?)> nested = const {},
}) {
  final map = <String, Object?>{
    for (final entry in mapping.entries)
      if (entry.key case final String key) key: entry.value,
  };
  Object? valueOf(String key) =>
      nested[key] == null ? map[key] : nested[key]!(map[key]);
  return {
    for (final key in known)
      if (map.containsKey(key)) key: valueOf(key),
    for (final key in tomSortedRemainder(map.keys, known))
      key: valueOf(key),
  };
}

/// The keys of [all] that [known] does not name, sorted by code point — the
/// rule for an open key set.
List<String> tomSortedRemainder(Iterable<String> all, List<String> known) =>
    [
      for (final key in all)
        if (!known.contains(key)) key,
    ]..sort();

/// [items] ordered by the string under [key], code point order; an item
/// without one keeps its relative position after every item that has one.
///
/// Stable by construction (Dart's `List.sort` is not), so a list with two
/// equal or missing keys still encodes to one byte sequence.
List<Object?> tomSortedById(List<Object?> items, {String key = 'id'}) {
  String? idOf(Object? item) =>
      item is Map<Object?, Object?> && item[key] is String
          ? item[key] as String
          : null;
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final idA = idOf(a.$2);
    final idB = idOf(b.$2);
    if (idA == null && idB == null) return a.$1.compareTo(b.$1);
    if (idA == null) return 1;
    if (idB == null) return -1;
    final byId = idA.compareTo(idB);
    return byId != 0 ? byId : a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}
