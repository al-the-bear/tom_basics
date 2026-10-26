/// The evaluator: predicates over looked-up values, conjoined by a query.
library;

import 'package:test/test.dart';
import 'package:tom_query/tom_query.dart';

void main() {
  group('tomCoversPath', () {
    test('a path covers itself and its descendants, segment by segment', () {
      expect(tomCoversPath('docs', 'docs'), isTrue);
      expect(tomCoversPath('docs', 'docs/api'), isTrue);
      expect(tomCoversPath('docs', 'docs/api/v1'), isTrue);
      expect(tomCoversPath('docs', 'docsets'), isFalse);
      expect(tomCoversPath('docs/api', 'docs'), isFalse);
    });
  });

  group('TomAnyOf', () {
    test('a scalar matches when it equals one of the values', () {
      const p = TomAnyOf(['high', 'critical']);
      expect(p.test('high'), isTrue);
      expect(p.test('low'), isFalse);
    });

    test('a collection matches when any member does', () {
      const p = TomAnyOf(['b']);
      expect(p.test({'a', 'b'}), isTrue);
      expect(p.test(['a', 'c']), isFalse);
      expect(p.test(const <String>[]), isFalse);
    });

    test('values are compared as strings, so an enum or a number answers by '
        'its text', () {
      expect(const TomAnyOf(['3']).test(3), isTrue);
      expect(const TomAnyOf(['x']).test(_Wire('x')), isTrue);
    });

    test('hierarchical matching is segment-aware', () {
      const p = TomAnyOf(['docs'], hierarchical: true);
      expect(p.test({'docs/api'}), isTrue);
      expect(p.test({'docsets'}), isFalse);
      expect(const TomAnyOf(['docs']).test('docs/api'), isFalse);
    });

    test('an unset property fails', () {
      expect(const TomAnyOf(['a']).test(null), isFalse);
    });
  });

  group('TomDateWindow', () {
    final d = DateTime.utc(2026, 10, 21);

    test('is inclusive on both bounds and open where a bound is null', () {
      expect(TomDateWindow(from: d, to: d).test(d), isTrue);
      expect(
        TomDateWindow(from: d).test(d.add(const Duration(days: 9))),
        isTrue,
      );
      expect(
        TomDateWindow(to: d).test(d.add(const Duration(days: 1))),
        isFalse,
      );
      expect(const TomDateWindow().test(d), isTrue);
    });

    test('an unset or non-date value is never inside a window', () {
      expect(const TomDateWindow().test(null), isFalse);
      expect(const TomDateWindow().test('2026-10-21'), isFalse);
    });
  });

  group('TomUnset', () {
    test('matches only an unset property', () {
      expect(const TomUnset().test(null), isTrue);
      expect(const TomUnset().test(''), isFalse);
    });
  });

  group('TomPropertyQuery', () {
    final record = <String, Object?>{
      'status': 'open',
      'tags': {'ga', 'web'},
      'due': DateTime.utc(2026, 10, 1),
    };
    Object? lookup(String key) => record[key];

    test('the empty query matches everything', () {
      expect(const TomPropertyQuery([]).matches(lookup), isTrue);
      expect(const TomPropertyQuery([]).matches((_) => null), isTrue);
    });

    test('terms conjoin, and two terms may name one key', () {
      expect(
        TomPropertyQuery([
          const TomQueryTerm('status', TomAnyOf(['open'])),
          const TomQueryTerm('tags', TomAnyOf(['ga'])),
        ]).matches(lookup),
        isTrue,
      );
      expect(
        TomPropertyQuery([
          TomQueryTerm('due', TomDateWindow(from: DateTime.utc(2026, 9, 1))),
          TomQueryTerm('due', TomDateWindow(to: DateTime.utc(2026, 9, 30))),
        ]).matches(lookup),
        isFalse,
      );
    });

    test('a key the record does not carry is unset, so it matches nothing '
        'but TomUnset and does not throw', () {
      expect(
        const TomPropertyQuery([
          TomQueryTerm('priority', TomAnyOf(['high'])),
        ]).matches(lookup),
        isFalse,
      );
      expect(
        const TomPropertyQuery([
          TomQueryTerm('priority', TomUnset()),
        ]).matches(lookup),
        isTrue,
      );
    });

    test('an application predicate takes part like the shipped ones', () {
      expect(
        const TomPropertyQuery([
          TomQueryTerm('tags', _Size(2)),
        ]).matches(lookup),
        isTrue,
      );
    });
  });
}

class _Wire {
  final String wire;
  const _Wire(this.wire);
  @override
  String toString() => wire;
}

class _Size extends TomPropertyPredicate {
  final int size;
  const _Size(this.size);
  @override
  bool test(Object? value) => value is Iterable && value.length == size;
}
