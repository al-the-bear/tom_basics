// BK-SORT: the :buildsorter command and dev dependencies.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/tom_build_kit.dart';

/// Runs `:buildsorter --names <extra>` over [root] and returns the printed
/// package names in order.
Future<List<String>> _sort(String root, List<String> extra) async {
  final args = CliArgParser(
    toolDefinition: buildkitTool,
  ).parse(['-R', root, '-s', root, '-r', ':buildsorter', '--names', ...extra]);
  final lines = <String>[];
  await runZoned(
    () =>
        createBuildkitExecutors()['buildsorter']!.executeWithoutTraversal(args),
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, line) => lines.add(line),
    ),
  );
  return [
    for (final line in lines)
      if (RegExp(r'^\s+\d+\.\s').hasMatch(line))
        line.trim().replaceFirst(RegExp(r'^\d+\.\s+'), ''),
  ];
}

void main() {
  late Directory root;

  setUp(() {
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync(recursive: true);
    root = base.createTempSync('buildsorter_test_');
    File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
    // lib_a's tests use lib_b; nothing at runtime.
    Directory(p.join(root.path, 'lib_a')).createSync();
    File(p.join(root.path, 'lib_a', 'pubspec.yaml')).writeAsStringSync(
      'name: lib_a\ndev_dependencies:\n  lib_b:\n    path: ../lib_b\n',
    );
    Directory(p.join(root.path, 'lib_b')).createSync();
    File(
      p.join(root.path, 'lib_b', 'pubspec.yaml'),
    ).writeAsStringSync('name: lib_b\n');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test(
    'BK-SORT-1: dev dependencies do not order by default [2026-11-12]',
    () async {
      expect(await _sort(root.path, []), equals(['lib_a', 'lib_b']));
    },
  );

  test('BK-SORT-2: --include-dev after the command orders by dev '
      'dependencies too [2026-11-12]', () async {
    expect(
      await _sort(root.path, ['--include-dev']),
      equals(['lib_b', 'lib_a']),
    );
  });
}
