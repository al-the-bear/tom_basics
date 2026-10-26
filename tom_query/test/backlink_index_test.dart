/// The backlink index: edges indexed from their source, pending targets,
/// incremental refresh, and the index contract over edges.
library;

import 'package:test/test.dart';
import 'package:tom_query/tom_query.dart';

import 'support/notes.dart';

void main() {
  Notes a() => {
    'root': ['#note|the note', '*#plan', 'b#target', '#gone'],
    'note': [],
    'plan': ['#root'],
  };
  Notes b() => {
    'target': [],
    'tail': ['a#note'],
  };

  test('backrefsOf lists every slot pointing at a record, across documents, '
      'in source order', () {
    final index = NoteBacklinks.build({'a': a(), 'b': b()});
    final intoNote = index.backrefsOf('a', 'note');
    expect(
      [for (final e in intoNote) '${e.sourceLocator}#${e.sourceId}'],
      ['a#root', 'b#tail'],
    );
    expect(intoNote.first.alias, 'the note');
    expect(index.backrefsOf('a', 'plan').single.embedded, isTrue);
    expect(index.backrefsOf('b', 'target').single.sourceId, 'root');
    expect(index.backrefsOf('a', 'nothing'), isEmpty);
    expect(index.hasBackrefs('a', 'root'), isTrue);
    expect(index.hasBackrefs('b', 'tail'), isFalse);
  });

  test('forwardRefsOf keeps slot order, and a backref is a value', () {
    final index = NoteBacklinks.build({'a': a()});
    final out = index.forwardRefsOf('a', 'root');
    expect([for (final e in out) e.childIndex], [0, 1, 2, 3]);
    expect(out.first, index.backrefsOf('a', 'note').single);
    expect(out.first.hashCode, index.backrefsOf('a', 'note').single.hashCode);
    expect(out.first.toString(), contains('"the note"'));
  });

  test('an edge into a document that is not open, or a record that is not '
      'there, is pending — never dropped', () {
    final index = NoteBacklinks.build({'a': a()});
    final out = index.forwardRefsOf('a', 'root');
    expect(index.isPending(out[0]), isFalse);
    expect(index.isPending(out[2]), isTrue, reason: 'b is not open');
    expect(index.isPending(out[3]), isTrue, reason: 'no such record');
    index.openDocument('b', b());
    expect(index.isPending(out[2]), isFalse);
    index.closeDocument('b');
    expect(index.isPending(out[2]), isTrue);
    expect(
      index.backrefsOf('a', 'note'),
      hasLength(1),
      reason: "b's edge went",
    );
  });

  test('refreshRecord replaces one record\'s edges and says whether they '
      'changed', () async {
    final doc = a();
    final index = NoteBacklinks.build({'a': doc});
    var fired = 0;
    final sub = index.changes.listen((_) => fired++);
    final before = index.edgeChanges;

    expect(index.refreshRecord(doc, 'note'), isFalse, reason: 'unchanged');
    doc['note'] = ['#plan|again'];
    expect(index.refreshRecord(doc, 'note'), isTrue);
    expect(index.backrefsOf('a', 'plan'), hasLength(2));
    doc.remove('plan');
    expect(index.refreshRecord(doc, 'plan'), isTrue, reason: 'removed');
    expect(index.forwardRefsOf('a', 'plan'), isEmpty);
    expect(
      index.backrefsOf('a', 'plan'),
      hasLength(2),
      reason: 'incoming kept',
    );
    expect(
      index.refreshRecord(<String, List<String>>{}, 'x'),
      isFalse,
      reason: 'a document the index does not hold',
    );

    expect(fired, 2);
    expect(index.edgeChanges, before + 2);
    await sub.cancel();
    await index.dispose();
  });

  test('it is an instance of the index contract: an entry per edge, owned by '
      'its source, queried over the subclass properties', () {
    final index = NoteBacklinks.build({'a': a(), 'b': b()});
    expect(index, isA<TomIndex<TomBackref>>());
    expect(index.entries, hasLength(6));
    expect(index.entries.first.id, 'a#plan/0');
    expect(index.entries.map((e) => e.origin).toSet(), {null});
    final fromT = index.query(
      const TomPropertyQuery([
        TomQueryTerm('kind', TomAnyOf(['t'])),
      ]),
    );
    expect([for (final e in fromT) e.ownerId], ['tail']);
    expect(index.documents.keys, ['a', 'b']);
    expect(index.locatorOf(index.documents['b']!), 'b');
  });
}
