/// A deterministic sort by one property.
///
/// Two rules are load-bearing and MUST hold from the first release, because
/// retrofitting either one changes visible output:
///
/// * **unset sorts last regardless of direction** — reversing the comparator
///   for a descending sort would float unset values to the front, which is
///   never what "sort by due date, newest first" means;
/// * **ties break by the tie-break key ascending, in both directions** — the
///   tie-break exists to make the order total, so letting the direction flip
///   it would reintroduce exactly the nondeterminism it removes.
library;

/// Sorts values of [T] by one looked-up property, deterministically.
///
/// Facet-agnostic like the evaluator: [value] hands back whatever the property
/// is (a String, a num, a DateTime, an enum ordinal) and [tieBreak] hands back
/// the identity keys — for a card on a board, say, its section id then its
/// item id.
class TomPropertySorter<T> {
  /// The property to sort on. Null means "unset" and sorts last.
  final Object? Function(T item) value;

  /// Identity keys, compared left to right, always ascending.
  final List<String> Function(T item) tieBreak;

  final bool descending;

  /// Case-insensitive comparison for String values.
  final bool caseInsensitive;

  const TomPropertySorter({
    required this.value,
    required this.tieBreak,
    this.descending = false,
    this.caseInsensitive = false,
  });

  int compare(T a, T b) {
    final va = value(a);
    final vb = value(b);

    if (va == null || vb == null) {
      // Unset last — before the direction is applied, not after.
      if (va != null) return -1;
      if (vb != null) return 1;
      return _compareTieBreak(a, b);
    }

    final result = _compareValues(va, vb);
    if (result != 0) return descending ? -result : result;
    return _compareTieBreak(a, b);
  }

  /// [items] sorted by [compare], leaving the source untouched.
  List<T> sorted(Iterable<T> items) => List<T>.of(items)..sort(compare);

  int _compareValues(Object a, Object b) {
    if (caseInsensitive && a is String && b is String) {
      final result = a.toLowerCase().compareTo(b.toLowerCase());
      // Fold ties deterministically rather than leaving case to decide.
      return result;
    }
    if (a is Comparable && b is Comparable) {
      return Comparable.compare(a, b);
    }
    return a.toString().compareTo(b.toString());
  }

  int _compareTieBreak(T a, T b) {
    final ka = tieBreak(a);
    final kb = tieBreak(b);
    for (var i = 0; i < ka.length && i < kb.length; i++) {
      final result = ka[i].compareTo(kb[i]);
      if (result != 0) return result;
    }
    return ka.length.compareTo(kb.length);
  }
}
