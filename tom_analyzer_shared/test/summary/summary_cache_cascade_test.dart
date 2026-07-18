import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

/// Tests for the closure-complete stale-set cascade that makes the
/// summary-cache stage converge in a single pass.
///
/// The failure it guards against (RCL5): when a `.sum` is invalidated because
/// its dependency-closure fingerprint no longer matches, deleting *only* that
/// bundle leaves every bundle that depends on it still on disk, still linked
/// against the deleted bundle's old layout. Feeding such a dependent to the
/// analyzer (as a `librarySummaryPath` while generating a third package, or
/// loading it directly) throws "Missing library". The generator's executor
/// swallows that throw and falls back to a source scan — correct output, but
/// the stale bundle is only deleted, never regenerated-and-relinked, so it took
/// several runs before the stage completed cleanly.
///
/// [SummaryGenerator.dependentsClosure] expands the initial stale set to the
/// full set of transitive dependents, so the stage deletes and regenerates the
/// whole affected subgraph atomically in one pass.
void main() {
  group('SummaryGenerator.dependentsClosure', () {
    test('a stale package with no dependents returns just itself', () {
      final graph = {
        'a': <String>{'b'},
        'b': <String>{},
      };
      // Nothing depends on `a`, so invalidating it stays local to `a`.
      expect(
        SummaryGenerator.dependentsClosure(graph, {'a'}),
        equals({'a'}),
      );
    });

    test('a direct dependent of a stale package is included', () {
      // a depends on b. b is stale, so a (linked against b) must go too.
      final graph = {
        'a': <String>{'b'},
        'b': <String>{},
      };
      expect(
        SummaryGenerator.dependentsClosure(graph, {'b'}),
        equals({'a', 'b'}),
      );
    });

    test('transitive dependents are included', () {
      // a -> b -> c. Invalidating the leaf c must cascade up to a.
      final graph = {
        'a': <String>{'b'},
        'b': <String>{'c'},
        'c': <String>{},
      };
      expect(
        SummaryGenerator.dependentsClosure(graph, {'c'}),
        equals({'a', 'b', 'c'}),
      );
    });

    test('diamond dependents are all included exactly once', () {
      // a -> {b, c}; b -> d; c -> d. Invalidating d cascades to b, c, and a.
      final graph = {
        'a': <String>{'b', 'c'},
        'b': <String>{'d'},
        'c': <String>{'d'},
        'd': <String>{},
      };
      expect(
        SummaryGenerator.dependentsClosure(graph, {'d'}),
        equals({'a', 'b', 'c', 'd'}),
      );
    });

    test('unrelated packages are not pulled in', () {
      // Two disjoint chains. Invalidating b must not touch x/y.
      final graph = {
        'a': <String>{'b'},
        'b': <String>{},
        'x': <String>{'y'},
        'y': <String>{},
      };
      expect(
        SummaryGenerator.dependentsClosure(graph, {'b'}),
        equals({'a', 'b'}),
      );
    });

    test('a seed absent from the graph still returns itself', () {
      final graph = {
        'a': <String>{'b'},
        'b': <String>{},
      };
      expect(
        SummaryGenerator.dependentsClosure(graph, {'ghost'}),
        equals({'ghost'}),
      );
    });

    test('cycles are tolerated', () {
      // a <-> b mutual dependency; invalidating either invalidates both once.
      final graph = {
        'a': <String>{'b'},
        'b': <String>{'a'},
      };
      expect(
        SummaryGenerator.dependentsClosure(graph, {'a'}),
        equals({'a', 'b'}),
      );
    });

    test('multiple seeds union their dependent closures', () {
      // a -> b, c -> d; seed {b, d} → {a, b, c, d}.
      final graph = {
        'a': <String>{'b'},
        'b': <String>{},
        'c': <String>{'d'},
        'd': <String>{},
      };
      expect(
        SummaryGenerator.dependentsClosure(graph, {'b', 'd'}),
        equals({'a', 'b', 'c', 'd'}),
      );
    });

    test('an empty seed set invalidates nothing', () {
      final graph = {
        'a': <String>{'b'},
        'b': <String>{},
      };
      expect(
        SummaryGenerator.dependentsClosure(graph, <String>{}),
        isEmpty,
      );
    });
  });
}
