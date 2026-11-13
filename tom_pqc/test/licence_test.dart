/// tom_pqc's licence boundary: every package its closure links is
/// permissive, every vendored C file keeps its upstream licence, and the
/// pinned commit is the same in THIRD_PARTY.md, the C backend and the
/// CHANGELOG.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_test_support/licence_audit.dart';

/// Each vendored library: its folder, its pinned commit and the C file of
/// tom_pqc that names it.
const _vendored = {
  'native/mlkem-native': (
    commit: 'd1b2fe782888bdb761a50336012923180be7f502',
    backend: 'native/tom_pqc.c',
  ),
  'native/mldsa-native': (
    commit: '834a90d5e846ffa1e1611bd24e160bb2e9b86d35',
    backend: 'native/tom_pqc_mldsa.c',
  ),
};

void main() {
  test('every package the closure links is permissive', () {
    final config = File('.dart_tool/package_config.json');
    final decoded = jsonDecode(config.readAsStringSync()) as Map;
    final packages = {
      for (final e in (decoded['packages'] as List).cast<Map>())
        e['name'] as String: Directory.fromUri(
          config.absolute.uri.resolve(e['rootUri'] as String),
        ),
    };
    final linked = tomLinkedPackages('tom_pqc', packages);
    expect(
      linked.map((l) => l.name),
      containsAll(['native_toolchain_c', 'cryptography', 'crypto']),
    );
    final audit = tomAuditLicences(linked, admitted: TomLicence.permissive);
    expect(audit.problems, isEmpty);
    expect(audit.granted['tom_pqc'], TomLicence.bsd3);
  });

  for (final dir in _vendored.keys) {
    test('every vendored source file of $dir keeps the upstream licence', () {
      final sources = Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) => const ['.c', '.h', '.inc'].contains(p.extension(f.path)),
          )
          .toList();
      expect(sources, isNotEmpty);
      for (final file in sources) {
        expect(
          file.readAsStringSync(),
          contains('SPDX-License-Identifier: Apache-2.0 OR ISC OR MIT'),
          reason: file.path,
        );
      }
      final licence = File('$dir/LICENSE').readAsStringSync();
      expect(licence, contains('Apache-2.0'));
      expect(licence, contains('ISC'));
      expect(licence, contains('MIT'));
    });

    test('no assembly, no architecture back end and no upstream docs are '
        'vendored in $dir', () {
      final entries = Directory(dir)
          .listSync(recursive: true)
          .map((e) => p.relative(e.path, from: dir).replaceAll(r'\', '/'));
      expect(
        entries.where((e) => e.endsWith('.S') || e.endsWith('.s')),
        isEmpty,
      );
      expect(entries.where((e) => e.split('/').contains('native')), isEmpty);
      expect(entries.where((e) => e.endsWith('.md')), isEmpty);
    });
  }

  test('the package\'s own C files are BSD-3-Clause', () {
    for (final name in const [
      'tom_pqc.c',
      'tom_pqc.h',
      'tom_pqc_mldsa.c',
      'tom_pqc_mldsa_config.h',
      'tom_pqc_random.c',
      'tom_pqc_random.h',
      'tom_pqc_mlkem_config.h',
    ]) {
      expect(
        File('native/$name').readAsStringSync(),
        contains('SPDX-License-Identifier: BSD-3-Clause'),
        reason: name,
      );
    }
  });

  test('each pinned commit agrees in THIRD_PARTY.md, its backend and the '
      'CHANGELOG', () {
    final thirdParty = File('THIRD_PARTY.md').readAsStringSync();
    final changelog = File('CHANGELOG.md').readAsStringSync();
    for (final (:commit, :backend) in _vendored.values) {
      expect(thirdParty, contains(commit));
      expect(File(backend).readAsStringSync(), contains(commit));
      expect(changelog, contains(commit));
    }
  });

  test('every vector folder names its source, commit and licence, and its '
      'files are unchanged', () {
    for (final dir in const ['wycheproof', 'xwing', 'rfc10073', 'age']) {
      final source =
          jsonDecode(File('test/vectors/$dir/SOURCE.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(source['source'], isNotEmpty, reason: dir);
      expect(source['commit'], matches(RegExp(r'^[0-9a-f]{40}$')), reason: dir);
      expect(source['licence'], isNotEmpty, reason: dir);
      expect(
        File('THIRD_PARTY.md').readAsStringSync(),
        contains(source['commit'] as String),
        reason: '$dir commit in THIRD_PARTY.md',
      );
    }
  });
}
