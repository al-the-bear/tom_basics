/// The display metrics measured for one package (spec §4.2.2).
///
/// All three are **static** counts — the scanner runs no `dart test` and makes
/// no process calls (see [PackageScanner]). They are display-only and never feed
/// status, except [loc], which also drives the >200-line "works" rule (§4.2.1).
class PackageMetrics {
  const PackageMetrics({this.loc = 0, this.tests = 0, this.testLoc = 0});

  /// Lines of code in `lib/`: non-blank, non-full-line-comment Dart lines,
  /// excluding generated files (`*.g.dart`, `*.freezed.dart`, `*.options.dart`).
  /// This is the exact count the >200-rule uses, so the report and the rule
  /// never disagree.
  final int loc;

  /// Number of test cases: a static count of `test(` / `testWidgets(`
  /// invocations across `test/` (lines that are full-line comments are ignored).
  final int tests;

  /// Lines of test code in `test/`, counted the same way as [loc] (non-blank,
  /// non-comment, generated files excluded) for a like-for-like comparison.
  final int testLoc;

  @override
  String toString() => 'PackageMetrics(loc: $loc, tests: $tests, '
      'testLoc: $testLoc)';
}
