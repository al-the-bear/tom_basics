# Tom Query — User Guide

> **Attribution.** The Tom Framework is developed by Peter Nicolai Alexis Kyaw.
> These packages are BSD-3-Clause licensed and published on pub.dev.

This guide describes how the parts of Tom Query behave and how an application
plugs its own data into them: conditions and predicates, sorting, the index
contract, and the backlink index. The [README](../README.md) gives the overview
and a complete example; this page is the reference for the rules each part
follows.

Everything is imported from the single library:

```dart
import 'package:tom_query/tom_query.dart';
```

The package has no dependencies and imports nothing but `dart:async`, so it
runs on every Dart platform, the browser included.

---

## 1. Concepts

| Concept | Type | Meaning |
| ------- | ---- | ------- |
| **Property lookup** | `TomPropertyLookup` | `Object? Function(String key)`: the value of one property of one record, `null` when unset. |
| **Predicate** | `TomPropertyPredicate` | A test over one property value. |
| **Term** | `TomQueryTerm` | A property key and a predicate. |
| **Query** | `TomPropertyQuery` | A list of terms that must all hold. |
| **Sorter** | `TomPropertySorter<T>` | A total order of items by one property, with a tie-break. |
| **Index** | `TomIndex<T>` | Entries, a property lookup per entry, and a query over them. |
| **Entry** | `TomIndexEntry<T>` | A payload with its id, its owning record and an origin. |
| **Backlink index** | `TomBacklinkIndex<D>` | Which reference points where, across open documents of type `D`. |

Tom Query knows no property names and no value types of its own. The
application decides what a property is and returns its value from a lookup;
Tom Query decides only how a condition and a sort treat that value.

---

## 2. Conditions

### 2.1 Evaluating a query

`TomPropertyQuery(terms).matches(lookup)` calls `lookup(term.key)` for each
term, in order, and answers `false` at the first predicate that fails. A query
without terms matches every record.

The lookup is any function, so a query runs over a map, an object, or a
database row alike:

```dart
const query = TomPropertyQuery([
  TomQueryTerm('status', TomAnyOf(['open', 'blocked'])),
]);
final row = {'status': 'blocked'};
print(query.matches((key) => row[key])); // true
```

Terms are a list, not a map, so two terms may name the same key. Both must
hold. This is how a condition such as "due this week and not done" is written
without a negation operator: one term on the date, one on the status listing
every status except `done`.

A condition language of the application's own is **lowered** into a
`TomPropertyQuery` when it is parsed: the query is a derived form, built when
needed and not stored.

### 2.2 The predicates

| Predicate | Matches | An unset value (`null`) |
| --------- | ------- | ----------------------- |
| `TomAnyOf(values)` | The value's `toString()` equals one of `values`; for an `Iterable` value, when any member does. | never matches |
| `TomAnyOf(values, hierarchical: true)` | As above, but a wanted value also covers its descendants under `tomCoversPath`. | never matches |
| `TomDateWindow(from:, to:)` | The value is a `DateTime` within `from` … `to`, both ends inclusive; a `null` bound is open. | never matches |
| `TomUnset()` | The value is `null`. | matches |

Details that follow from the code:

- `TomAnyOf` compares **text**: `TomAnyOf(['2'])` matches the int `2`, and an
  enum matches by its `toString()` (for example `Status.open`), so a lookup
  that wants to match enum names returns `value.name`.
- `TomAnyOf([])` matches nothing.
- `TomDateWindow` compares instants with `isBefore` / `isAfter`, so a UTC and a
  local `DateTime` for the same moment compare equal. A value that is not a
  `DateTime` (a date string, an int) never matches; the lookup converts it.
- "Has no date" is `TomUnset()`, not an empty window: an unset value is never
  inside a window.

### 2.3 The path rule

`tomCoversPath(wanted, candidate)` answers whether `candidate` is `wanted` or
lies below it in a slash-separated hierarchy:

```dart
print(tomCoversPath('docs', 'docs')); // true
print(tomCoversPath('docs', 'docs/api')); // true
print(tomCoversPath('docs', 'docsets')); // false
print(tomCoversPath('docs/api', 'docs')); // false
```

It is the one implementation of that rule; hierarchical `TomAnyOf` uses it,
and an application that compares paths elsewhere calls it rather than
re-deriving it.

### 2.4 Writing a predicate

Extend `TomPropertyPredicate` and implement `test`. Keep the convention that
`null` means unset, and give the class a `const` constructor so queries can be
constants:

```dart
class TomAtLeast extends TomPropertyPredicate {
  final num min;
  const TomAtLeast(this.min);

  @override
  bool test(Object? value) => value is num && value >= min;
}

const urgent = TomPropertyQuery([TomQueryTerm('priority', TomAtLeast(3))]);
print(urgent.matches((key) => {'priority': 4}[key])); // true
```

---

## 3. Sorting

`TomPropertySorter<T>({value, tieBreak, descending, caseInsensitive})` orders
items by `value(item)`:

1. Items whose value is `null` come **last**, in both directions.
2. Other values are compared — strings without regard to case when
   `caseInsensitive` is set, `Comparable` values with `Comparable.compare`, and
   anything else by `toString()` — and the result is reversed when `descending`
   is set.
3. Equal values, and two unset values, are ordered by `tieBreak(item)`: a list
   of strings compared element by element, **always ascending**; a shorter list
   that is a prefix of a longer one comes first.

`compare(a, b)` is the comparator; `sorted(items)` returns a new sorted list and
leaves `items` as it was.

```dart
final sorter = TomPropertySorter<String>(
  value: (s) => s,
  tieBreak: (s) => [s],
  caseInsensitive: true,
);
print(sorter.sorted(['b', 'B', 'a', 'A'])); // [A, a, B, b]
```

Because the tie-break never flips, reversing the direction changes only the
order of different values; items with equal values stay in tie-break order,
and unset items stay at the end. Give `tieBreak` the item's identity keys (for
example a section id, then an item id) so that no two items compare equal and
the order is total.

**Limit.** Values of one property should be of one type. Two `Comparable`
values of different types (a `String` and an `int`) are handed to
`Comparable.compare`, which throws a `TypeError`. A lookup that may return
mixed types normalises them first.

---

## 4. The index contract

### 4.1 What an index answers

`TomIndex<T>` is an interface with four members:

| Member | Answers |
| ------ | ------- |
| `entries` | Everything the index holds, in the index's own order. |
| `valueOf(entry, key)` | The value of one property of one entry; `null` when unset **and** for a key the index does not carry. A collection is returned as an `Iterable`. |
| `properties` | The keys `valueOf` answers. |
| `query(condition)` | The entries `condition` accepts, in `entries` order. |

`properties` exists because `valueOf` answers `null` for an unknown key and for
an unset property alike. A condition on a key outside `properties` matches no
entry (every predicate but `TomUnset` fails on `null`), and a caller can check
`properties` to tell that apart from a condition that simply found nothing.

### 4.2 Implementing an index

Mix in `TomIndexQuery<T>`. It implements `query` once, by evaluating the
condition over `valueOf` for every entry, so an index supplies only `entries`,
`valueOf` and `properties`:

```dart
class TagIndex with TomIndexQuery<String> {
  TagIndex._(this._tags);

  factory TagIndex.build(Map<String, Set<String>> tagsById) =>
      TagIndex._(tagsById);

  final Map<String, Set<String>> _tags;

  @override
  List<TomIndexEntry<String>> get entries => [
    for (final id in _tags.keys.toList()..sort())
      TomIndexEntry(payload: id, id: id, ownerId: id),
  ];

  @override
  Set<String> get properties => const {'tags'};

  @override
  Object? valueOf(TomIndexEntry<String> entry, String key) =>
      key == 'tags' ? _tags[entry.id] : null;
}
```

Conventions an index follows:

- It is created by a `build` factory over whatever it aggregates. A
  constructor is not part of an interface, so this is a convention, not
  something the compiler checks.
- It states its order: `query` answers in `entries` order, so a stable
  `entries` gives stable results.
- An index that holds entries a reader must not see answers `null` for them
  from `valueOf`, or leaves them out of `entries`; `query` reads values through
  `valueOf` only.

Several aggregations written against this contract can later be replaced by one
index without changing the code that queries them.

### 4.3 Entries

`TomIndexEntry<T>` carries:

| Field | Meaning |
| ----- | ------- |
| `payload` | What the index holds. |
| `id` | The payload's own id, so an entry is addressable without knowing the payload type. |
| `ownerId` | The record the payload belongs to; owner-level properties are read from it. |
| `origin` | Where the entry came from, in the index's own terms; `null` when there is one origin. |

Entries are values: `==` and `hashCode` cover all four fields.

---

## 5. The backlink index

### 5.1 What it records

`TomBacklinkIndex<D>` keeps, for every open document, the references each of
its records makes, and answers them in both directions. It reads documents only
through a `TomRefSource<D>` that the application supplies, so `D` can be any
document type.

| Term | Meaning |
| ---- | ------- |
| **Locator** | The string a document is opened under (a path, a URI). |
| **Record** | Something in a document with an id; records are keyed by `(locator, recordId)`, so two documents may use the same id. |
| **Slot** | One reference a record makes (`TomRefSlot`): its position, whether it is embedded, an optional alias, and the target's locator and id. |
| **Edge** | A slot seen from either end (`TomBackref`): the source locator and record plus the slot's fields. |
| **Pending** | An edge whose target document is not open, or does not hold the target record. |

### 5.2 Reading documents: `TomRefSource`

| Method | Answers |
| ------ | ------- |
| `recordIds(document)` | Every record id of the document. |
| `slotsOf(locator, document, recordId)` | The record's slots in order; empty when the record is not there. |
| `holds(document, recordId)` | Whether the document has that record. |

`slotsOf` must return an **absolute** target locator: the referencing
document's own locator for a reference inside the same document, and a
resolved locator for one into another document. Two documents that reach one
target by different relative paths then meet on one key.

### 5.3 Subclassing

`TomBacklinkIndex` is abstract: it is an index (section 4) whose entries are
edges, and the properties a query can ask of an edge belong to the
application. A subclass supplies:

| Member | Purpose |
| ------ | ------- |
| constructor | Passes the `TomRefSource` to `super`. |
| `properties`, `valueOf` | What a query can ask of an edge (typically properties of its source record). |
| `entryOrigin` (optional) | The `origin` every entry carries; `null` by default. |
| `edgesChanged()` (optional) | Called whenever edges or documents changed, before `changes` fires — the place to drop anything the subclass derived from the documents. It may be called more than once for one change. |

A `build` factory that opens the initial documents completes it, as in the
[README example](../README.md#example).

### 5.4 Keeping it current

| Call | Effect | `changes` fires |
| ---- | ------ | --------------- |
| `openDocument(locator, document)` | Indexes the document, or re-reads it when the locator is open already. | always |
| `closeDocument(locator)` | Removes the document and its outgoing edges; edges into it from other documents become pending. | when the locator was open |
| `refreshRecord(document, recordId)` | Re-reads one record's slots and answers whether its edges changed. | when they changed |

`refreshRecord` covers every edit to a record — a slot added, removed, moved or
re-aliased, the record added or deleted — and an undo or a merge the same way.
It finds the document's locator with `locatorOf`, which compares by
**identity**: it works for a document object that is edited in place. An
application whose edits produce a new document object calls `openDocument`
again with the new object; `refreshRecord` with an object the index does not
hold changes nothing and answers `false`.

When a record is deleted, its outgoing edges go and edges into it stay; they
now point at a missing record, and `isPending` reports them.

`changes` is a synchronous broadcast stream with no payload: a view listens to
it and re-reads what it shows. `dispose()` closes it.

The index is derived from the documents and is not stored. A workspace that is
opened again rebuilds it by opening its documents.

### 5.5 Asking it

| Call | Answers |
| ---- | ------- |
| `backrefsOf(locator, recordId)` | Every edge pointing at the record, sorted by source locator, source record, slot position. Empty when nothing points at it. |
| `hasBackrefs(locator, recordId)` | Whether anything points at it, without building the list. |
| `forwardRefsOf(locator, recordId)` | The record's own edges, in slot order (an unmodifiable list). |
| `isPending(edge)` | Whether the edge's target document is not open or lacks the record. |
| `documents` | The open documents by locator (an unmodifiable view). |
| `locatorOf(document)` | The locator a document object is open under, or `null`. |
| `entries` | One entry per edge, ordered by source locator and record, then slot; `id` is `<locator>#<recordId>/<childIndex>`, `ownerId` the source record id. |

A pending edge is never dropped: it stays an edge of its source, appears in
`backrefsOf` for its target key, and stops being pending as soon as the target
document is opened with that record.

```dart
final links = NoteBacklinks()
  ..openDocument('a', {
    'home': ['#ideas', 'b#plan'],
    'ideas': ['#home'],
  });
final toPlan = links.forwardRefsOf('a', 'home').last;
print(links.isPending(toPlan)); // true
links.openDocument('b', {'plan': []});
print(links.isPending(toPlan)); // false
print(links.backrefsOf('b', 'plan').single.sourceId); // home
```

(`NoteBacklinks` is the subclass from the README example.)

### 5.6 Cost

The index holds edges keyed by their source. `forwardRefsOf` is a lookup;
`backrefsOf`, `hasBackrefs` and `entries` walk every edge. `locatorOf`, and so
`refreshRecord`, walks the open documents. That is the right shape for the
documents a user has open in an editor; it is not a store for a large corpus.

---

## 6. See also

- [README](../README.md) — overview, installation, quick start and the full
  example.
- [`example/readme_example.dart`](../example/readme_example.dart) — the README
  example as a program; `test/readme_example_test.dart` checks its output.
- [CHANGELOG](../CHANGELOG.md).
