# tom_query

Published on pub.dev as [`tom_query` 0.1.0](https://pub.dev/packages/tom_query).

> **Attribution.** The Tom Framework is developed by Peter Nicolai Alexis Kyaw.
> These packages are BSD-3-Clause licensed and published on pub.dev.

Querying records that an application indexes: a facet-agnostic condition
evaluator over a property lookup, a deterministic sorter, one index contract
every aggregation implements, and a reverse index of references across open
documents. Nothing here knows what a status, a due date or a document is — an
application supplies how a property is looked up and how a reference is read,
and gets one way of deciding a condition everywhere it asks.

## Overview

- **A condition** (`TomPropertyQuery`) is a list of terms, each a property key
  and a predicate over whatever a `TomPropertyLookup` returns for that key. The
  terms conjoin; two may name one key, which is how a grammar says "past due
  and not done" without a negation operator. An empty query matches every
  record. An application's own condition vocabulary reaches it by **lowering**:
  the vocabulary is parsed once into a query, and the query is never stored.
- **The predicates** answer `false` for an unset property, except `TomUnset`,
  which asks exactly that. `TomAnyOf` compares by text and matches a collection
  when any member does; its hierarchical form is segment-aware, so `docs`
  covers `docs/api` and not `docsets` (`tomCoversPath`, the one implementation
  of that rule). `TomDateWindow` is inclusive and open on a null bound. An
  application adds a predicate by extending `TomPropertyPredicate`.
- **A sort** (`TomPropertySorter`) is by one property. Unset sorts last in both
  directions, and ties break by the identity keys ascending in both directions,
  so the order is total and reversing it never floats empty values to the top.
- **An index** (`TomIndex`) answers three questions whatever it holds: its
  `entries`, the value of one property of one entry (`valueOf`, null for an
  unset property and for a key the instance does not carry), and which entries
  a condition accepts (`query`). `query` is implemented once, in
  `TomIndexQuery`, so an instance contributes what its entries' properties are
  and nothing about how a condition is decided. An entry (`TomIndexEntry`)
  carries a payload, its id, the record it belongs to (`ownerId`) and an
  application-defined `origin`. Aggregations that are instances of one contract
  can later be replaced by one index under unchanged call sites.
- **Backlinks** (`TomBacklinkIndex`) record which reference points where, for
  every open document, read through a `TomRefSource` the application supplies.
  An edge is indexed from its source and keyed by `(locator, recordId)` with an
  absolute target locator, so two documents referencing one target by
  different relative paths meet on one key. An edge whose target document is
  not open, or holds no such record, is **pending** — never dropped. The index
  is derived and never persisted, and incremental: `refreshRecord` re-reads one
  record's references after any change, so an edit, an undo and a merge
  converge it alike. It is an instance of the index contract, one entry per
  edge, and a subclass states what a query can ask of an edge.

## Installation

Add it from pub.dev:

```yaml
dependencies:
  tom_query: ^0.1.0
```

Dart SDK `^3.10.8`. No dependencies, no Flutter, no `dart:io`: it links into a
browser build.

## Features

| Type | What it does |
| ---- | ------------ |
| `TomPropertyQuery`, `TomQueryTerm`, `TomPropertyLookup` | A condition, its terms, and the lookup it is evaluated over. |
| `TomPropertyPredicate`, `TomAnyOf`, `TomDateWindow`, `TomUnset` | The predicates, and the base an application's own extend. |
| `tomCoversPath` | The segment-aware path-hierarchy rule. |
| `TomPropertySorter` | A total, deterministic sort by one property. |
| `TomIndex`, `TomIndexEntry`, `TomIndexQuery` | The index contract and its one `query`. |
| `TomBacklinkIndex`, `TomRefSource`, `TomRefSlot`, `TomBackref` | The reverse index of references and how a document is read. |

## Example

```dart
import 'package:tom_query/tom_query.dart';

/// Tasks, keyed by id, each owned by a project.
class TaskIndex with TomIndexQuery<String> {
  TaskIndex._(this._tasks);

  factory TaskIndex.build(Map<String, Map<String, Object?>> tasks) =>
      TaskIndex._(tasks);

  final Map<String, Map<String, Object?>> _tasks;

  @override
  List<TomIndexEntry<String>> get entries => [
    for (final MapEntry(:key, :value) in _tasks.entries)
      TomIndexEntry(
        payload: value['title']! as String,
        id: key,
        ownerId: value['project']! as String,
      ),
  ];

  @override
  Set<String> get properties => const {'status', 'due', 'tags'};

  @override
  Object? valueOf(TomIndexEntry<String> entry, String key) =>
      _tasks[entry.id]![key];
}

/// Notes: each note lists the notes it links to, `#id` or `other#id`.
class NoteLinks implements TomRefSource<Map<String, List<String>>> {
  const NoteLinks();

  @override
  Iterable<String> recordIds(Map<String, List<String>> document) =>
      document.keys;

  @override
  bool holds(Map<String, List<String>> document, String recordId) =>
      document.containsKey(recordId);

  @override
  List<TomRefSlot> slotsOf(
    String locator,
    Map<String, List<String>> document,
    String recordId,
  ) => [
    for (final (i, link) in (document[recordId] ?? const <String>[]).indexed)
      TomRefSlot(
        childIndex: i,
        embedded: false,
        alias: null,
        targetLocator: link.startsWith('#') ? locator : link.split('#').first,
        targetId: link.split('#').last,
      ),
  ];
}

class NoteBacklinks extends TomBacklinkIndex<Map<String, List<String>>> {
  NoteBacklinks() : super(const NoteLinks());

  @override
  Set<String> get properties => const {};

  @override
  Object? valueOf(TomIndexEntry<TomBackref> entry, String key) => null;
}

void main() {
  final tasks = TaskIndex.build({
    't1': {
      'title': 'Write spec',
      'project': 'p1',
      'status': 'open',
      'due': DateTime.utc(2026, 10, 20),
      'tags': {'docs/api'},
    },
    't2': {
      'title': 'Ship',
      'project': 'p1',
      'status': 'done',
      'due': DateTime.utc(2026, 10, 25),
    },
    't3': {'title': 'Review', 'project': 'p2', 'status': 'open'},
  });

  // Open, and tagged under docs/ (which covers docs/api).
  final openDocs = tasks.query(
    const TomPropertyQuery([
      TomQueryTerm('status', TomAnyOf(['open'])),
      TomQueryTerm('tags', TomAnyOf(['docs'], hierarchical: true)),
    ]),
  );
  print([for (final e in openDocs) e.payload]);

  final undated = tasks.query(
    const TomPropertyQuery([TomQueryTerm('due', TomUnset())]),
  );
  print([for (final e in undated) e.id]);

  final byDue = TomPropertySorter<TomIndexEntry<String>>(
    value: (e) => tasks.valueOf(e, 'due'),
    tieBreak: (e) => [e.id],
    descending: true,
  );
  print([for (final e in byDue.sorted(tasks.entries)) e.id]);

  final links = NoteBacklinks()
    ..openDocument('a', {
      'home': ['#ideas', 'b#plan'],
      'ideas': ['#home'],
    });
  print(links.backrefsOf('a', 'ideas').map((e) => e.sourceId).toList());
  final toPlan = links.forwardRefsOf('a', 'home').last;
  print(
    '${toPlan.targetLocator}#${toPlan.targetId} '
    'pending=${links.isPending(toPlan)}',
  );
  links.openDocument('b', {'plan': []});
  print('pending=${links.isPending(toPlan)}');
}
```

The compiled form of this section is
[`example/readme_example.dart`](example/readme_example.dart), and
`test/readme_example_test.dart` asserts what it prints.

## Dependencies

| Dependency | Kind | For |
| ---------- | ---- | --- |
| `test`, `lints` | dev | the suite |

## Status

Version **0.1.0**. `dart test` runs the suite: the predicates and the query,
the sorter, the index contract, the backlink index over a fake document type,
the package's shape, and the example.
