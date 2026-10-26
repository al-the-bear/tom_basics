/// A tiny document type the backlink index is exercised over: a document is
/// a map from note id to the references the note makes, each `#id` (in the
/// same document) or `other#id` (in the document open as `other`), with an
/// optional `|alias`. A leading `*` marks the reference embedded.
library;

import 'package:tom_query/tom_query.dart';

typedef Notes = Map<String, List<String>>;

class NoteRefs implements TomRefSource<Notes> {
  const NoteRefs();

  @override
  Iterable<String> recordIds(Notes document) => document.keys;

  @override
  bool holds(Notes document, String recordId) => document.containsKey(recordId);

  @override
  List<TomRefSlot> slotsOf(String locator, Notes document, String recordId) => [
    for (final (i, raw) in (document[recordId] ?? const <String>[]).indexed)
      _slot(locator, i, raw),
  ];

  static TomRefSlot _slot(String locator, int index, String raw) {
    final embedded = raw.startsWith('*');
    final body = embedded ? raw.substring(1) : raw;
    final [ref, ...alias] = body.split('|');
    final [target, id] = ref.split('#');
    return TomRefSlot(
      childIndex: index,
      embedded: embedded,
      alias: alias.isEmpty ? null : alias.single,
      targetLocator: target.isEmpty ? locator : target,
      targetId: id,
    );
  }
}

/// The backlink index over [Notes], answering one property: `kind`, the
/// first letter of the source note's id.
class NoteBacklinks extends TomBacklinkIndex<Notes> {
  NoteBacklinks._() : super(const NoteRefs());

  factory NoteBacklinks.build(Map<String, Notes> documents) {
    final index = NoteBacklinks._();
    for (final e in documents.entries) {
      index.openDocument(e.key, e.value);
    }
    return index;
  }

  int edgeChanges = 0;

  @override
  void edgesChanged() => edgeChanges++;

  @override
  Set<String> get properties => const {'kind'};

  @override
  Object? valueOf(TomIndexEntry<TomBackref> entry, String key) =>
      key == 'kind' ? entry.ownerId[0] : null;
}
