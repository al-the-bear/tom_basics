/// A facet-agnostic condition evaluator.
///
/// Nothing here knows what a `status` or a `due` date is. It knows *terms*: a
/// property key, and a predicate over whatever value a lookup function returns
/// for that key. An application's own condition vocabulary reaches it by
/// **lowering** — a derived form, never persisted — so a grammar can be
/// promoted to a query language over arbitrary typed properties without the
/// evaluator being rewritten.
library;

/// Whether [candidate] is [wanted] or a descendant of it under the
/// path-hierarchy rule: `docs` covers `docs/api`, but **not** `docsets`.
///
/// The rule is segment-aware, which is the whole of its content, and every
/// reader of a slash-separated hierarchy shares this one implementation.
bool tomCoversPath(String wanted, String candidate) =>
    candidate == wanted || candidate.startsWith('$wanted/');

/// Resolves a property by key for one candidate. Returns null when unset.
///
/// A collection-valued property (a category set, a tag list) is returned as an
/// [Iterable]; [TomAnyOf] tests membership over it.
typedef TomPropertyLookup = Object? Function(String key);

/// A predicate over a single property value.
abstract class TomPropertyPredicate {
  const TomPropertyPredicate();

  /// Whether [value] — the result of a [TomPropertyLookup] — satisfies
  /// this predicate. A null [value] means the property is unset.
  bool test(Object? value);
}

/// Disjunction over a closed value list — the `[a, b]` form of the grammar.
///
/// A scalar property matches when it equals one of [values]; a collection
/// property matches when **any** member does. Comparison is over
/// `toString()`, so callers may hand back an enum wire name, a String, or a
/// Set of Strings without the evaluator learning their types.
class TomAnyOf extends TomPropertyPredicate {
  final List<String> values;

  /// Path-hierarchy expansion: `docs` matches `docs/api`.
  ///
  /// Segment-aware — `docs` must not match `docsets`.
  final bool hierarchical;

  const TomAnyOf(this.values, {this.hierarchical = false});

  @override
  bool test(Object? value) {
    if (value == null) return false;
    final candidates = value is Iterable
        ? value.map((v) => v.toString())
        : [value.toString()];
    for (final candidate in candidates) {
      for (final wanted in values) {
        if (hierarchical
            ? tomCoversPath(wanted, candidate)
            : candidate == wanted) {
          return true;
        }
      }
    }
    return false;
  }
}

/// An inclusive date window. A null bound is open on that side.
///
/// An unset property is never inside a window — "has no date" is
/// [TomUnset], a different question.
class TomDateWindow extends TomPropertyPredicate {
  final DateTime? from;
  final DateTime? to;

  const TomDateWindow({this.from, this.to});

  @override
  bool test(Object? value) {
    if (value is! DateTime) return false;
    if (from != null && value.isBefore(from!)) return false;
    if (to != null && value.isAfter(to!)) return false;
    return true;
  }
}

/// The property is not set.
class TomUnset extends TomPropertyPredicate {
  const TomUnset();

  @override
  bool test(Object? value) => value == null;
}

/// One `key: predicate` pair of a query.
class TomQueryTerm {
  final String key;
  final TomPropertyPredicate predicate;

  const TomQueryTerm(this.key, this.predicate);
}

/// A conjunction of [TomQueryTerm]s.
///
/// A **list** rather than a map, because lowering may produce two terms on one
/// key — "overdue" can be a past-window term on a date *and* an open-status
/// term on a status, which is how a grammar says "not done" without owning a
/// negation operator.
class TomPropertyQuery {
  final List<TomQueryTerm> terms;

  const TomPropertyQuery(this.terms);

  /// An empty query matches everything — "no condition" is "every record in
  /// scope", not "nothing".
  bool matches(TomPropertyLookup lookup) {
    for (final term in terms) {
      if (!term.predicate.test(lookup(term.key))) return false;
    }
    return true;
  }
}
