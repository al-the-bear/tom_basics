/// The index contract: entries, a property lookup, and the one query.
library;

import 'package:test/test.dart';
import 'package:tom_query/tom_query.dart';

/// A minimal instance: tasks owned by projects.
class _Tasks with TomIndexQuery<String> {
  _Tasks(this._rows);

  factory _Tasks.build(Map<String, ({String owner, String state})> rows) =>
      _Tasks(rows);

  final Map<String, ({String owner, String state})> _rows;

  @override
  List<TomIndexEntry<String>> get entries => [
    for (final e in _rows.entries)
      TomIndexEntry(
        payload: e.key.toUpperCase(),
        id: e.key,
        ownerId: e.value.owner,
      ),
  ];

  @override
  Set<String> get properties => const {'state', 'owner'};

  @override
  Object? valueOf(TomIndexEntry<String> entry, String key) => switch (key) {
    'state' => _rows[entry.id]!.state,
    'owner' => entry.ownerId,
    _ => null,
  };
}

void main() {
  final index = _Tasks.build({
    't1': (owner: 'p1', state: 'open'),
    't2': (owner: 'p1', state: 'done'),
    't3': (owner: 'p2', state: 'open'),
  });
  List<String> ids(List<TomIndexEntry<String>> found) => [
    for (final e in found) e.id,
  ];

  test('query is evaluated over valueOf, in entries order', () {
    expect(
      ids(
        index.query(
          const TomPropertyQuery([
            TomQueryTerm('state', TomAnyOf(['open'])),
          ]),
        ),
      ),
      ['t1', 't3'],
    );
    expect(
      ids(
        index.query(
          const TomPropertyQuery([
            TomQueryTerm('state', TomAnyOf(['open'])),
            TomQueryTerm('owner', TomAnyOf(['p1'])),
          ]),
        ),
      ),
      ['t1'],
    );
  });

  test('the empty query answers every entry', () {
    expect(ids(index.query(const TomPropertyQuery([]))), ids(index.entries));
  });

  test('a property the instance does not carry matches nothing, and '
      'properties says so', () {
    expect(index.properties, isNot(contains('priority')));
    expect(
      index.query(
        const TomPropertyQuery([
          TomQueryTerm('priority', TomAnyOf(['high'])),
        ]),
      ),
      isEmpty,
    );
  });

  test('an entry is a value: payload, id, owner and origin', () {
    const a = TomIndexEntry(payload: 1, id: 'x', ownerId: 'o', origin: #body);
    const b = TomIndexEntry(payload: 1, id: 'x', ownerId: 'o', origin: #body);
    const c = TomIndexEntry(payload: 1, id: 'x', ownerId: 'o');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
    expect(c.origin, isNull);
    expect(a.toString(), contains('o x'));
  });
}
