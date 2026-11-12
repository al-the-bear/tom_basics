// BB-FLP: one answer to "is this a Flutter package?", shared by the nature
// detector, the CI runner and the tools (testkit picks `flutter test` by it).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/ci.dart';
import 'package:tom_build_base/tom_build_base.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('pubspecDeclaresFlutterSdk', () {
    bool declares(String yaml) => pubspecDeclaresFlutterSdk(loadYaml(yaml));

    test('BB-FLP-1: a Flutter SDK dependency counts', () {
      expect(declares('dependencies:\n  flutter:\n    sdk: flutter\n'), isTrue);
    });

    test('BB-FLP-2: a plain Dart package does not', () {
      expect(declares('dependencies:\n  path: ^1.9.0\n'), isFalse);
      expect(declares('name: x\n'), isFalse);
    });

    test('BB-FLP-3: flutter_test in dev_dependencies alone does not', () {
      expect(
        declares('dev_dependencies:\n  flutter_test:\n    sdk: flutter\n'),
        isFalse,
      );
    });

    test('BB-FLP-4: flutter from pub.dev (not the SDK) does not', () {
      expect(declares('dependencies:\n  flutter: ^1.0.0\n'), isFalse);
    });

    test('BB-FLP-5: a parsed Map works as well as a YamlMap', () {
      expect(
        pubspecDeclaresFlutterSdk(<String, dynamic>{
          'dependencies': {
            'flutter': {'sdk': 'flutter'},
          },
        }),
        isTrue,
      );
      expect(pubspecDeclaresFlutterSdk(null), isFalse);
      expect(pubspecDeclaresFlutterSdk('text'), isFalse);
    });
  });

  group('isFlutterPackage', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('bb_flp_'));
    tearDown(() => dir.deleteSync(recursive: true));

    void pubspec(String text) =>
        File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(text);

    test('BB-FLP-6: reads the pubspec from disk', () {
      pubspec('name: app\ndependencies:\n  flutter:\n    sdk: flutter\n');
      expect(isFlutterPackage(dir.path), isTrue);
      pubspec('name: lib\n');
      expect(isFlutterPackage(dir.path), isFalse);
    });

    test('BB-FLP-7: a missing or unreadable pubspec is not Flutter', () {
      expect(isFlutterPackage(dir.path), isFalse);
      pubspec('dependencies: [unclosed');
      expect(isFlutterPackage(dir.path), isFalse);
    });

    test('BB-FLP-8: the nature detector and the CI runner agree', () {
      pubspec('name: app\ndependencies:\n  flutter:\n    sdk: flutter\n');
      expect(ciIsFlutterPackage(dir.path), isTrue);
      final nature = NatureDetector().detectNatures(FsFolder(path: dir.path));
      expect(nature.whereType<FlutterProjectFolder>(), isNotEmpty);
    });
  });
}
