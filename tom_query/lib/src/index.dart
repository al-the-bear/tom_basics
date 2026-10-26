/// The one index contract.
///
/// An index answers the same three questions whatever it holds: what is there
/// ([TomIndex.entries]), what is the value of a property of one entry
/// ([TomIndex.valueOf]), and which entries satisfy a condition
/// ([TomIndex.query]). Several aggregations that are **instances** of this
/// contract, rather than classes that resemble each other, can later be
/// dissolved into one index by swapping an implementation under the call
/// sites; without a contract that is a rewrite of every consumer at once.
///
/// ## The three operations
///
/// * **How an instance comes to exist** is its own: a `build` factory over
///   whatever it aggregates. A constructor is not inherited, so it is part of
///   the contract by rule, which an application can check.
/// * **[TomIndex.valueOf]** is the property lookup the evaluator of
///   `property_query.dart` runs over. It answers **null** for a property an
///   entry has not set and for a key the instance does not carry, alike. Unset
///   fails every predicate, so a condition over a property an index does not
///   have matches nothing rather than throwing.
/// * **[TomIndex.query]** takes a [TomPropertyQuery] — an application's own
///   condition vocabulary, lowered — and is implemented once, in
///   [TomIndexQuery], so there is one way a condition is decided.
///
/// An instance that holds records some readers must not see answers nothing
/// for them from [TomIndex.valueOf]: an index is a projection, and a query is
/// a way to read a value back one predicate at a time.
library;

import 'property_query.dart';

/// One thing an index holds: a payload, and where it belongs.
class TomIndexEntry<T> {
  final T payload;

  /// The payload's own id. Carried here, because an entry has to be
  /// addressable without the index knowing what a payload is.
  final String id;

  /// The record the payload belongs to — the one whose properties the
  /// owner-level facets of [TomIndex.valueOf] are read from.
  final String ownerId;

  /// Where the entry came from, in the instance's own terms (for example,
  /// stored in a record's body or anchored on it from elsewhere); null when an
  /// instance has one origin only.
  final Object? origin;

  const TomIndexEntry({
    required this.payload,
    required this.id,
    required this.ownerId,
    this.origin,
  });

  @override
  bool operator ==(Object other) =>
      other is TomIndexEntry<T> &&
      other.payload == payload &&
      other.id == id &&
      other.ownerId == ownerId &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(payload, id, ownerId, origin);

  @override
  String toString() => 'TomIndexEntry<$T>($origin $ownerId $id)';
}

/// The contract. Implemented through [TomIndexQuery], which supplies [query]
/// so that there is one implementation of it.
abstract interface class TomIndex<T> {
  /// Everything the index holds, in the instance's own stated order.
  List<TomIndexEntry<T>> get entries;

  /// The value of property [key] for [entry], or null when it is unset or the
  /// instance carries no such property.
  ///
  /// A collection-valued property is returned as an [Iterable]. The keys an
  /// instance answers are listed by [properties].
  Object? valueOf(TomIndexEntry<T> entry, String key);

  /// The property keys [valueOf] answers for this instance.
  ///
  /// Stated, because an unknown key and an unset property are both null: this
  /// is what lets a caller tell a condition that cannot match from one that
  /// merely did not.
  Set<String> get properties;

  /// The entries [condition] accepts, in [entries] order.
  List<TomIndexEntry<T>> query(TomPropertyQuery condition);
}

/// [TomIndex.query], once, for every instance: the condition is evaluated over
/// [valueOf], so an instance contributes what its entries' properties are and
/// nothing about how a condition is decided.
mixin TomIndexQuery<T> implements TomIndex<T> {
  @override
  List<TomIndexEntry<T>> query(TomPropertyQuery condition) => [
    for (final entry in entries)
      if (condition.matches((key) => valueOf(entry, key))) entry,
  ];
}
