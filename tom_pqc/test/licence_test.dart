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

const _commit = 'd1b2fe782888bdb761a50336012923180be7f502';
const _vendored = 'native/mlkem-native';

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
    expect(linked.map((l) => l.name), contains('native_toolchain_c'));
    final audit = tomAuditLicences(linked, admitted: TomLicence.permissive);
    expect(audit.problems, isEmpty);
    expect(audit.granted['tom_pqc'], TomLicence.bsd3);
  });

  test('every vendored source file keeps the upstream licence', () {
    final sources = Directory(_vendored)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => const ['.c', '.h', '.inc'].contains(p.extension(f.path)))
        .toList();
    expect(sources, isNotEmpty);
    for (final file in sources) {
      expect(
        file.readAsStringSync(),
        contains('SPDX-License-Identifier: Apache-2.0 OR ISC OR MIT'),
        reason: file.path,
      );
    }
    final licence = File('$_vendored/LICENSE').readAsStringSync();
    expect(
      licence,
      contains('Apache-2.0 license OR the ISC license OR the MIT'),
    );
  });

  test('no assembly, no architecture back end and no upstream docs are '
      'vendored', () {
    final entries = Directory(_vendored)
        .listSync(recursive: true)
        .map((e) => p.relative(e.path, from: _vendored).replaceAll(r'\', '/'));
    expect(entries.where((e) => e.endsWith('.S') || e.endsWith('.s')), isEmpty);
    expect(entries.where((e) => e.split('/').contains('native')), isEmpty);
    expect(entries.where((e) => e.endsWith('.md')), isEmpty);
  });

  test('the package\'s own C files are BSD-3-Clause', () {
    for (final name in const [
      'tom_pqc.c',
      'tom_pqc.h',
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

  test('the pinned commit agrees in THIRD_PARTY.md, the backend and the '
      'CHANGELOG', () {
    expect(File('THIRD_PARTY.md').readAsStringSync(), contains(_commit));
    expect(File('native/tom_pqc.c').readAsStringSync(), contains(_commit));
    expect(File('CHANGELOG.md').readAsStringSync(), contains(_commit));
  });
}
