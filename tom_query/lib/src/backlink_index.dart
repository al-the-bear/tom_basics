/// A reverse index of references, across open documents.
library;

import 'dart:async';

import 'index.dart';

/// One reference slot of a record, as a [TomRefSource] reads it.
class TomRefSlot {
  /// The slot's position among the record's references.
  final int childIndex;

  /// Whether the referenced record is shown inside the referencing one.
  final bool embedded;

  /// The label the slot gives its target, when it gives one.
  final String? alias;

  /// What the slot points at: the target document's **absolute** locator —
  /// the referencing document's own for an internal reference — and the
  /// target record's id. Absolute, so two documents referencing one target by
  /// different relative paths meet on one key.
  final String targetLocator;
  final String targetId;

  const TomRefSlot({
    required this.childIndex,
    required this.embedded,
    required this.alias,
    required this.targetLocator,
    required this.targetId,
  });
}

/// How a [TomBacklinkIndex] reads a document of type [D]: its records, the
/// reference slots of one record, and whether a record is there.
abstract interface class TomRefSource<D> {
  /// Every record id of [document].
  Iterable<String> recordIds(D document);

  /// The reference slots of record [recordId] of [document], open under
  /// [locator], in order — empty when the record is not there.
  List<TomRefSlot> slotsOf(String locator, D document, String recordId);

  /// Whether [document] holds record [recordId].
  bool holds(D document, String recordId);
}

/// One reference slot, seen from the record it points at.
///
/// The slot's own metadata travels with it — [childIndex], [embedded],
/// [alias] — because the same target is routinely referenced from several
/// places under different labels, and a backlinks view shows each place.
class TomBackref {
  /// The document holding the slot, as the workspace opened it.
  final String sourceLocator;

  /// The record holding the slot.
  final String sourceId;

  final int childIndex;
  final bool embedded;
  final String? alias;
  final String targetLocator;
  final String targetId;

  const TomBackref({
    required this.sourceLocator,
    required this.sourceId,
    required this.childIndex,
    required this.embedded,
    required this.alias,
    required this.targetLocator,
    required this.targetId,
  });

  @override
  bool operator ==(Object other) =>
      other is TomBackref &&
      other.sourceLocator == sourceLocator &&
      other.sourceId == sourceId &&
      other.childIndex == childIndex &&
      other.embedded == embedded &&
      other.alias == alias &&
      other.targetLocator == targetLocator &&
      other.targetId == targetId;

  @override
  int get hashCode => Object.hash(
    sourceLocator,
    sourceId,
    childIndex,
    embedded,
    alias,
    targetLocator,
    targetId,
  );

  @override
  String toString() =>
      'TomBackref($sourceLocator#$sourceId[$childIndex] '
      '→ $targetLocator#$targetId${alias == null ? '' : ' "$alias"'})';
}

/// Which reference points where, for every open document.
///
/// **Derived, never persisted.** Everything it holds is read off the
/// documents' reference slots through [refs], so a reopened workspace rebuilds
/// it.
///
/// **Workspace-scoped, keyed by `(locator, recordId)`**: a backlink is
/// cross-document by nature, and two documents may hold the same id. An edge
/// is indexed from its *source*: it exists while the document holding the slot
/// is open, whether or not its target's document is. An edge whose target is
/// not open, or not there, is **pending** ([isPending]) — never dropped, since
/// the slot still carries the reference. Closing a document removes its
/// outgoing edges; edges *into* it from documents still open become pending
/// again.
///
/// **Incremental**: it keeps each record's outgoing edges and [refreshRecord]
/// replaces them from the record's current slots, so add, remove, move and an
/// alias edit are one code path, and an undo or a merge converges it the same
/// way as an edit. A removed record drops its outgoing edges and keeps its
/// incoming ones, which now point at a broken target.
///
/// It is an instance of the [TomIndex] contract: an entry is one edge, its
/// `ownerId` the record holding the slot. What a query can ask of an edge —
/// the properties of its source record — is the application's, so a subclass
/// supplies [valueOf] and [properties], and a `build` factory.
abstract class TomBacklinkIndex<D> with TomIndexQuery<TomBackref> {
  TomBacklinkIndex(this.refs);

  /// How documents are read.
  final TomRefSource<D> refs;

  final Map<String, D> _documents = {};

  /// Outgoing edges per source, keyed `(locator, recordId)`.
  final Map<(String, String), List<TomBackref>> _outgoing = {};

  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );

  /// Fires after any change to the edge set, so a view refreshes without
  /// polling.
  Stream<void> get changes => _changes.stream;

  /// The documents currently indexed, keyed by locator.
  Map<String, D> get documents => Map.unmodifiable(_documents);

  /// The origin every entry carries, for an application whose other indexes
  /// distinguish origins; null by default.
  Object? get entryOrigin => null;

  /// Called whenever the edge set or the document set changed, before
  /// [changes] fires — where a subclass forgets what it derived from the
  /// documents.
  void edgesChanged() {}

  /// Adds — or re-reads — the document at [locator].
  void openDocument(String locator, D document) {
    _forget(locator);
    _index(locator, document);
    _changes.add(null);
  }

  /// Removes the document at [locator]: its outgoing edges go, and edges into
  /// it from other documents become pending.
  void closeDocument(String locator) {
    if (_forget(locator)) _changes.add(null);
  }

  /// Re-reads the slots of record [recordId] of [document] — after it was
  /// added, removed, or its references changed — and answers whether the edge
  /// set changed. A document this index does not hold changes nothing.
  bool refreshRecord(D document, String recordId) {
    final locator = locatorOf(document);
    if (locator == null) return false;
    final next = _edgesOf(locator, document, recordId);
    final key = (locator, recordId);
    final previous = _outgoing[key] ?? const <TomBackref>[];
    if (_sameEdges(previous, next)) return false;
    if (next.isEmpty) {
      _outgoing.remove(key);
    } else {
      _outgoing[key] = next;
    }
    edgesChanged();
    _changes.add(null);
    return true;
  }

  /// The locator [document] is indexed under, or null.
  String? locatorOf(D document) {
    for (final entry in _documents.entries) {
      if (identical(entry.value, document)) return entry.key;
    }
    return null;
  }

  /// Every slot pointing at [recordId] of the document at [locator], ordered
  /// by source locator, then source record, then slot position. Empty — never
  /// null — for a record nothing references.
  List<TomBackref> backrefsOf(String locator, String recordId) => [
    for (final edges in _outgoing.values)
      for (final edge in edges)
        if (edge.targetLocator == locator && edge.targetId == recordId) edge,
  ]..sort(_order);

  /// Whether anything references [recordId] of [locator] — a badge's
  /// question, answered without building the list.
  bool hasBackrefs(String locator, String recordId) => _outgoing.values.any(
    (edges) =>
        edges.any((e) => e.targetLocator == locator && e.targetId == recordId),
  );

  /// The slots of [recordId] in the document at [locator], in order — a
  /// graph's one adjacency source.
  List<TomBackref> forwardRefsOf(String locator, String recordId) =>
      List.unmodifiable(_outgoing[(locator, recordId)] ?? const []);

  /// Whether [edge]'s target is not, or not yet, reachable: its document is
  /// not open, or holds no such record.
  bool isPending(TomBackref edge) {
    final document = _documents[edge.targetLocator];
    return document == null || !refs.holds(document, edge.targetId);
  }

  @override
  List<TomIndexEntry<TomBackref>> get entries => [
    for (final key in _outgoing.keys.toList()..sort(_keyOrder))
      for (final edge in _outgoing[key]!)
        TomIndexEntry(
          payload: edge,
          id: '${edge.sourceLocator}#${edge.sourceId}/${edge.childIndex}',
          ownerId: edge.sourceId,
          origin: entryOrigin,
        ),
  ];

  /// Releases the [changes] stream.
  Future<void> dispose() => _changes.close();

  // ── internals ──────────────────────────────────────────────────────────

  void _index(String locator, D document) {
    _documents[locator] = document;
    for (final id in refs.recordIds(document)) {
      final edges = _edgesOf(locator, document, id);
      if (edges.isNotEmpty) _outgoing[(locator, id)] = edges;
    }
    edgesChanged();
  }

  bool _forget(String locator) {
    final had = _documents.remove(locator) != null;
    _outgoing.removeWhere((key, _) => key.$1 == locator);
    edgesChanged();
    return had;
  }

  List<TomBackref> _edgesOf(String locator, D document, String recordId) => [
    for (final slot in refs.slotsOf(locator, document, recordId))
      TomBackref(
        sourceLocator: locator,
        sourceId: recordId,
        childIndex: slot.childIndex,
        embedded: slot.embedded,
        alias: slot.alias,
        targetLocator: slot.targetLocator,
        targetId: slot.targetId,
      ),
  ];

  static bool _sameEdges(List<TomBackref> a, List<TomBackref> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int _keyOrder((String, String) a, (String, String) b) {
    final byLocator = a.$1.compareTo(b.$1);
    return byLocator != 0 ? byLocator : a.$2.compareTo(b.$2);
  }

  static int _order(TomBackref a, TomBackref b) {
    final byKey = _keyOrder(
      (a.sourceLocator, a.sourceId),
      (b.sourceLocator, b.sourceId),
    );
    return byKey != 0 ? byKey : a.childIndex.compareTo(b.childIndex);
  }
}
