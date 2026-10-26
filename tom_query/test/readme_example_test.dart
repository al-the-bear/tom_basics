/// What the README example prints, asserted — the expectations are written
/// here, so the test states a claim of its own rather than agreeing with the
/// example's comments by construction.
library;

import 'dart:async';

import 'package:test/test.dart';

import '../example/readme_example.dart' as example;

List<String> _printed(void Function() body) {
  final lines = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

void main() {
  test('the example queries, sorts with unset last, and finds backlinks and '
      'a pending edge that resolves when its document opens', () {
    expect(_printed(example.main), [
      '[Write spec]',
      '[t3]',
      '[t2, t1, t3]',
      '[home]',
      'b#plan pending=true',
      'pending=false',
    ]);
  });
}
