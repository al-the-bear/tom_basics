@Tags(['integration'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

/// A package's own `analysis_options.yaml` excludes are about linting it, not
/// about what it contains. televerse excludes its `*.g.dart` / `*.freezed.dart`
/// parts, tom_d4rt_dcli its `*.b.dart` bridge LIBRARIES. Analysed with those
/// options, every excluded file had no analysis context: one "Failed to
/// analyze ...: Bad state: Unable to find the context to ..." warning per
/// file, and an excluded library was missing from the package's summary.
///
///   SAE-1 a package whose options exclude a library and a part is summarised
///         without a warning, and the excluded library is in the summary (the
///         part through its library)
/// The closure fingerprint every bundle of this file is cached under: one
/// fixed value, as the lookups default to it (`fingerprints[name] ?? ''`).
const _fp = '';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('summary_excludes_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'SAE-1: analyzer excludes of the package do not drop its files',
    () async {
      final pkg = Directory(p.join(tempDir.path, 'excl_pkg'))..createSync();
      void put(String rel, String text) => File(p.join(pkg.path, rel))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
      put('pubspec.yaml', 'name: excl_pkg\nenvironment:\n  sdk: ^3.6.0\n');
      put(
        'analysis_options.yaml',
        'analyzer:\n  exclude:\n    - "**/*.g.dart"\n    - "**/*.b.dart"\n',
      );
      put('lib/excl_pkg.dart', "part 'excl_pkg.g.dart';\n\nclass Model {}\n");
      put(
        'lib/excl_pkg.g.dart',
        "part of 'excl_pkg.dart';\n\nclass ModelGenerated {}\n",
      );
      put('lib/bridges.b.dart', 'library;\n\nclass Bridge {}\n');

      final project = Directory(p.join(tempDir.path, 'project'))..createSync();
      File(p.join(project.path, 'pubspec.lock')).writeAsStringSync('''
packages:
  excl_pkg:
    dependency: "direct main"
    description:
      name: excl_pkg
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
''');
      File(p.join(project.path, '.dart_tool', 'package_config.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '{"configVersion": 2, "packages": [{"name": "excl_pkg", '
          '"rootUri": "${pkg.uri}", "packageUri": "lib/"}]}',
        );

      final cacheManager = SummaryCacheManager(
        project.path,
        cacheDirectory: p.join(tempDir.path, '.tom', 'analyzer-cache'),
      );
      final resolver = DependencyResolver();
      final generator = SummaryGenerator(
        cacheManager: cacheManager,
        dependencyResolver: resolver,
      );
      final dep = (await resolver.resolveVersionedDependencies(
        project.path,
      )).singleWhere((d) => d.name == 'excl_pkg');

      final warnings = StringBuffer();
      final generated = await IOOverrides.runZoned(
        () => generator.generateSummary(dep, fingerprint: _fp),
        stderr: () => _CapturingStdout(warnings),
      );

      expect(generated, isTrue);
      expect(warnings.toString(), isNot(contains('Failed to analyze')));
      final bundle = await cacheManager.loadSummary(
        'excl_pkg',
        '1.0.0',
        fingerprint: _fp,
      );
      final libraries = bundle!.libraries.map((l) => l.uriStr).toSet();
      expect(
        libraries,
        containsAll(<String>[
          'package:excl_pkg/excl_pkg.dart',
          'package:excl_pkg/bridges.b.dart',
        ]),
      );
      final units = bundle.libraries
          .singleWhere((l) => l.uriStr == 'package:excl_pkg/excl_pkg.dart')
          .units
          .map((u) => u.uriStr);
      expect(
        units,
        contains('package:excl_pkg/excl_pkg.g.dart'),
        reason: 'the part is in the summary through its library',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// Collects what is written to stderr.
class _CapturingStdout implements Stdout {
  _CapturingStdout(this._buffer);

  final StringBuffer _buffer;

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
