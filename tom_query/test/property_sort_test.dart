/// The sorter: one property, unset last in both directions, a total order.
library;

import 'package:test/test.dart';
import 'package:tom_query/tom_query.dart';

typedef _Row = ({String id, Object? value});

void main() {
  final rows = <_Row>[
    (id: 'c', value: 2),
    (id: 'a', value: null),
    (id: 'b', value: 1),
    (id: 'd', value: 2),
  ];
  List<String> ids(Iterable<_Row> sorted) => [for (final r in sorted) r.id];
  TomPropertySorter<_Row> sorter({bool descending = false}) =>
      TomPropertySorter<_Row>(
        value: (r) => r.value,
        tieBreak: (r) => [r.id],
        descending: descending,
      );

  test('ascending: by value, ties by the tie-break, unset last', () {
    expect(ids(sorter().sorted(rows)), ['b', 'c', 'd', 'a']);
  });

  test('descending reverses the values only: unset stays last and ties stay '
      'ascending', () {
    expect(ids(sorter(descending: true).sorted(rows)), ['c', 'd', 'b', 'a']);
  });

  test('sorted leaves the source untouched', () {
    final before = ids(rows);
    sorter().sorted(rows);
    expect(ids(rows), before);
  });

  test('case-insensitive strings fold case, and the tie-break decides the '
      'rest', () {
    final words = <_Row>[
      (id: '2', value: 'beta'),
      (id: '1', value: 'Beta'),
      (id: '3', value: 'alpha'),
    ];
    final s = TomPropertySorter<_Row>(
      value: (r) => r.value,
      tieBreak: (r) => [r.id],
      caseInsensitive: true,
    );
    expect(ids(s.sorted(words)), ['3', '1', '2']);
  });

  test('a value that is not Comparable is ordered by its text', () {
    final mixed = <_Row>[
      (id: 'x', value: const _Opaque('b')),
      (id: 'y', value: const _Opaque('a')),
    ];
    expect(ids(sorter().sorted(mixed)), ['y', 'x']);
  });

  test('a shorter tie-break key sorts first when it is a prefix', () {
    final s = TomPropertySorter<List<String>>(
      value: (_) => 0,
      tieBreak: (k) => k,
    );
    expect(
      s.sorted([
        ['a', 'b'],
        ['a'],
      ]),
      [
        ['a'],
        ['a', 'b'],
      ],
    );
  });
}

class _Opaque {
  final String text;
  const _Opaque(this.text);
  @override
  String toString() => text;
}
