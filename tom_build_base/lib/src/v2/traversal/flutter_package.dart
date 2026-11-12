import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Whether a parsed `pubspec.yaml` [pubspec] declares the Flutter SDK as a
/// dependency:
///
/// ```yaml
/// dependencies:
///   flutter:
///     sdk: flutter
/// ```
///
/// That is the signal the Flutter tooling uses, and the one rule the nature
/// detector ([FlutterProjectFolder]), the CI runner and the tools share — a
/// Flutter package is tested with `flutter test`, built with `flutter`.
/// `flutter_test` in `dev_dependencies` alone, or `flutter` from pub.dev, does
/// not count. Accepts what `loadYaml` returns or a plain [Map].
bool pubspecDeclaresFlutterSdk(Object? pubspec) {
  if (pubspec is! Map) return false;
  final dependencies = pubspec['dependencies'];
  if (dependencies is! Map) return false;
  final flutter = dependencies['flutter'];
  return flutter is Map && flutter['sdk'] == 'flutter';
}

/// Whether the package in [directory] is a Flutter package
/// ([pubspecDeclaresFlutterSdk] on its `pubspec.yaml`). A missing or
/// unreadable pubspec is not one.
bool isFlutterPackage(String directory) {
  final file = File(p.join(directory, 'pubspec.yaml'));
  if (!file.existsSync()) return false;
  try {
    return pubspecDeclaresFlutterSdk(loadYaml(file.readAsStringSync()));
  } on YamlException {
    return false;
  } on FileSystemException {
    return false;
  }
}
