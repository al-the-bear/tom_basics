import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';
import 'package:yaml/yaml.dart';

/// `analyzerMajorVersion` partitions the summary cache by the analyzer whose
/// bundle format wrote it. A constant behind the resolved analyzer lets this
/// build read bundles another major wrote, which fails while decoding them
/// (`_tagIndexes.length == _parentIndexes.length` in analyzer 14 reading
/// analyzer-10 bundles).
void main() {
  test('analyzerMajorVersion is the major of the resolved analyzer', () async {
    final libUri = await Isolate.resolvePackageUri(
      Uri.parse('package:analyzer/'),
    );
    expect(libUri, isNotNull, reason: 'package:analyzer does not resolve');
    final packageRoot = p.dirname(p.normalize(libUri!.toFilePath()));
    final pubspec =
        loadYaml(File(p.join(packageRoot, 'pubspec.yaml')).readAsStringSync())
            as YamlMap;
    final major = int.parse((pubspec['version'] as String).split('.').first);

    expect(analyzerMajorVersion, equals(major));
  });

  test('the pubspec constraint allows exactly that analyzer major', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final constraint =
        (pubspec['dependencies'] as YamlMap)['analyzer'] as String;

    expect(constraint, startsWith('^$analyzerMajorVersion.'));
  });

  test(
    'analyzerDataVersion is the resolved analyzer\'s DATA_VERSION, read '
    'the way analyzerDataVersionInPackageRoots reads another package\'s',
    () async {
      final libUri = await Isolate.resolvePackageUri(
        Uri.parse('package:analyzer/'),
      );
      final packageRoot = p.dirname(p.normalize(libUri!.toFilePath()));
      expect(
        analyzerDataVersionInPackageRoots({'analyzer': packageRoot}),
        equals(analyzerDataVersion),
      );
      expect(analyzerDataVersionInPackageRoots(const {}), isNull);
      expect(
        currentToolchainKey(dartSdkVersion: '3.13.7', dataVersion: 752),
        '3.13.7+d752',
      );
    },
  );
}
