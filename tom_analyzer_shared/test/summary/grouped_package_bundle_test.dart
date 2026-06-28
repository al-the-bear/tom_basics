import 'dart:io';

import 'package:analyzer/src/summary2/package_bundle_format.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

void main() {
  group('readPackageRoots / mergePackageRootsForDirs', () {
    late Directory work;

    setUp(() {
      work = Directory(p.join(
        Directory.current.path,
        'ztmp',
        'grouped_cfg_${DateTime.now().microsecondsSinceEpoch}',
      ))
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (work.existsSync()) work.deleteSync(recursive: true);
    });

    test('resolves rootUri relative to the config file', () {
      Directory(p.join(work.path, 'foo', 'lib')).createSync(recursive: true);
      final consumerDartTool =
          Directory(p.join(work.path, 'consumer', '.dart_tool'))
            ..createSync(recursive: true);
      File(p.join(consumerDartTool.path, 'package_config.json'))
          .writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    { "name": "foo", "rootUri": "../../foo", "packageUri": "lib/" }
  ]
}
''');

      final roots = mergePackageRootsForDirs(
          [p.join(work.path, 'consumer')]);
      expect(roots.keys, contains('foo'));
      expect(p.normalize(roots['foo']!),
          p.normalize(p.join(work.path, 'foo')));
    });

    test('missing package_config.json throws SummaryConfigException', () {
      expect(
        () => mergePackageRootsForDirs([p.join(work.path, 'nope')]),
        throwsA(isA<SummaryConfigException>()),
      );
    });
  });

  group('GroupedPackageBundleBuilder.buildFromDirs', () {
    late Directory work;
    late String consumerDir;

    setUp(() {
      work = Directory(p.join(
        Directory.current.path,
        'ztmp',
        'grouped_bundle_${DateTime.now().microsecondsSinceEpoch}',
      ))
        ..createSync(recursive: true);

      // package foo: a public library plus an internal src/ library it exports.
      Directory(p.join(work.path, 'foo', 'lib', 'src'))
          .createSync(recursive: true);
      File(p.join(work.path, 'foo', 'lib', 'foo.dart')).writeAsStringSync('''
export 'src/internal.dart';

class Foo {
  String greet() => 'hello';
}
''');
      File(p.join(work.path, 'foo', 'lib', 'src', 'internal.dart'))
          .writeAsStringSync('''
class Internal {
  int answer() => 42;
}
''');

      // package bar: depends on foo via a package: import.
      Directory(p.join(work.path, 'bar', 'lib')).createSync(recursive: true);
      File(p.join(work.path, 'bar', 'lib', 'bar.dart')).writeAsStringSync('''
import 'package:foo/foo.dart';

class Bar {
  final Foo foo = Foo();
}
''');

      // consumer config naming both packages (the union to summarize).
      final dartTool = Directory(p.join(work.path, 'consumer', '.dart_tool'))
        ..createSync(recursive: true);
      File(p.join(dartTool.path, 'package_config.json')).writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    { "name": "foo", "rootUri": "../../foo", "packageUri": "lib/" },
    { "name": "bar", "rootUri": "../../bar", "packageUri": "lib/" }
  ]
}
''');
      consumerDir = p.join(work.path, 'consumer');
    });

    tearDown(() {
      if (work.existsSync()) work.deleteSync(recursive: true);
    });

    test('builds a non-empty bundle covering the union of both packages',
        () async {
      final builder = GroupedPackageBundleBuilder();
      final bundle = await builder.buildFromDirs([consumerDir]);

      expect(bundle.packageCount, 2);
      expect(bundle.libraryCount, 3); // foo.dart + src/internal.dart + bar.dart
      expect(bundle.bytes, isNotEmpty);
    });

    test('emits package: library URIs, never file: (resolver order)',
        () async {
      final builder = GroupedPackageBundleBuilder();
      final bundle = await builder.buildFromDirs([consumerDir]);

      final reader = PackageBundleReader(bundle.bytes);
      final uris = reader.libraries.map((l) => l.uriStr).toList();

      expect(uris, isNotEmpty);
      expect(uris.every((u) => u.startsWith('package:')), isTrue,
          reason: 'all library URIs must be package: not file:, got $uris');
      expect(uris.any((u) => u.startsWith('file:')), isFalse);
      expect(uris, contains('package:foo/foo.dart'));
      expect(uris, contains('package:foo/src/internal.dart'));
      expect(uris, contains('package:bar/bar.dart'));
    });
  });
}
