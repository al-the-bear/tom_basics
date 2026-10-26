/// What the package is, read from its source: a leaf that any Dart program can
/// link, with no I/O and no dependency.
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  final sources = {
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
  };

  test('the library imports nothing but dart:async and its own files, so a '
      'browser build links it', () {
    expect(sources, isNotEmpty);
    for (final entry in sources.entries) {
      final imports = RegExp(
        r"^(?:import|export) '([^']+)'",
        multiLine: true,
      ).allMatches(entry.value).map((m) => m.group(1)!);
      for (final uri in imports) {
        expect(
          uri == 'dart:async' || !uri.contains(':'),
          isTrue,
          reason: '${entry.key} imports $uri',
        );
      }
    }
  });

  test('the pubspec declares no runtime dependency', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final runtime = pubspec.split('\ndev_dependencies:').first;
    expect(runtime, isNot(contains('\ndependencies:')));
  });

  test('nothing in the library names a particular application', () {
    for (final entry in sources.entries) {
      expect(
        entry.value,
        isNot(contains(RegExp('webwork', caseSensitive: false))),
        reason: entry.key,
      );
    }
  });
}
