/// The pubspec version and the changelog's top entry are one number.
///
/// Every consumer in the workspace takes this package by path, so nothing
/// resolves the declared version and nothing notices when the two part. They
/// did: the changelog stopped at 1.0.0 while the pubspec went to 1.3.0.
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final changelog = File('CHANGELOG.md').readAsStringSync();
  final declared =
      RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)![1]!;
  final entries = RegExp(r'^## (\d+\.\d+\.\d+)\s*$', multiLine: true)
      .allMatches(changelog)
      .map((m) => m[1]!)
      .toList();

  test('CHANGELOG-1: the top entry is the version the pubspec declares', () {
    expect(entries, isNotEmpty);
    expect(entries.first, declared);
  });

  test('CHANGELOG-2: entries run newest first and none is repeated', () {
    int rank(String v) {
      final p = v.split('.').map(int.parse).toList();
      return p[0] * 1000000 + p[1] * 1000 + p[2];
    }

    final ranks = entries.map(rank).toList();
    final sorted = ranks.toSet().toList()..sort((a, b) => b.compareTo(a));
    expect(ranks, sorted);
  });

  test('CHANGELOG-3: every minor the pubspec has carried has an entry', () {
    final parts = declared.split('.').map(int.parse).toList();
    for (var minor = 0; minor <= parts[1]; minor++) {
      expect(entries, contains('${parts[0]}.$minor.0'),
          reason: 'a version whose contents nobody recorded');
    }
  });
}
