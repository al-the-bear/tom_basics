// sce39: the coverage doc must not silently fall behind the suite again.
//
// `doc/test_coverage.md` had drifted 141 tests and seven test files behind
// before anyone measured it, and it drifted the same way afterwards: four
// files added since carried no row at all. The failure is quiet by
// construction — a doc that is merely out of date still reads as current, and
// the number in it is the one people quote.
//
// These checks cover the two rot modes that can be decided WITHOUT running the
// suite, which is why they are cheap enough to keep:
//
//   * a test file with no row (what actually happened, four times), and
//   * a total that disagrees with the rows above it (what happens when
//     somebody updates one row and not the footer).
//
// The third mode — a row whose count disagrees with the number of tests that
// file really runs — needs a live run to decide, and is left to the
// instruction the doc itself carries: measure with
// `dart test --reporter json -j 1`. Parsing test counts statically would mean
// reimplementing the test runner's notion of what a test is, which would rot
// faster than the document it guards.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Test files the doc deliberately does not carry a row for.
///
/// Empty, and meant to stay that way: a file that runs tests is a file whose
/// tests someone should be able to look up. An entry here needs a reason.
/// This file is not exempt from itself — §37 documents it.
const _exempt = <String>{};

void main() {
  final root = Directory.current.path;
  final doc = File(p.join(root, 'doc', 'test_coverage.md'));

  group('BB-COVDOC: the coverage doc tracks the suite', () {
    test('BB-COVDOC-1: every test file has a row in the overview '
        '[2026-09-18] (PASS)', () {
      expect(doc.existsSync(), isTrue, reason: '${doc.path} is missing');
      final text = doc.readAsStringSync();

      final onDisk =
          Directory(p.join(root, 'test'))
              .listSync(recursive: true)
              .whereType<File>()
              .map((f) => p.relative(f.path, from: root))
              .where((f) => f.endsWith('_test.dart'))
              .map((f) => f.replaceAll(r'\', '/'))
              .where((f) => !_exempt.contains(f))
              .toList()
            ..sort();

      expect(
        onDisk,
        isNotEmpty,
        reason: 'found no test files at all, so this check proved nothing',
      );

      // A row names its file in backticks, relative to `test/`.
      final documented = RegExp(
        r'\|\s*`([^`]+_test\.dart)`\s*\|',
      ).allMatches(text).map((m) => 'test/${m.group(1)}').toSet();

      final missing = onDisk.where((f) => !documented.contains(f)).toList();
      expect(
        missing,
        isEmpty,
        reason:
            'these test files have no row in doc/test_coverage.md.\n'
            'Add a row and a detail section, and re-measure the counts with\n'
            '  dart test --reporter json -j 1\n'
            'Missing:\n  ${missing.join('\n  ')}',
      );
    });

    test('BB-COVDOC-2: the stated total equals the sum of the rows '
        '[2026-09-18] (PASS)', () {
      final text = doc.readAsStringSync();

      final rowCounts = RegExp(
        r'^\|\s*\d+\s*\|.*?\|\s*(\d+)\s*\|\s*\d+✅\s*\|',
        multiLine: true,
      ).allMatches(text).map((m) => int.parse(m.group(1)!)).toList();

      expect(
        rowCounts,
        isNotEmpty,
        reason: 'parsed no rows, so a passing total would prove nothing',
      );

      final total = RegExp(
        r'\*\*Total\*\*\s*\|\s*\*\*(\d+)\*\*',
      ).firstMatch(text);
      expect(total, isNotNull, reason: 'no Total row found');

      expect(
        rowCounts.reduce((a, b) => a + b),
        int.parse(total!.group(1)!),
        reason:
            'the Total row disagrees with the rows above it — one was '
            'updated without the other',
      );
    });
  });
}
