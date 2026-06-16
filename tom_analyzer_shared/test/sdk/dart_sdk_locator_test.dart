import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/src/sdk/dart_sdk_locator.dart';

void main() {
  setUp(() {
    // Tests run under `dart`/`dart test`, so the locator should always find the
    // running SDK. Reset the process cache so each test resolves freshly.
    debugResetDartSdkLocatorCache(enableCache: false);
  });

  tearDown(() {
    debugResetDartSdkLocatorCache(enableCache: true);
  });

  group('looksLikeDartSdk', () {
    test('rejects null, empty, and non-SDK directories', () {
      expect(looksLikeDartSdk(null), isFalse);
      expect(looksLikeDartSdk(''), isFalse);
      expect(
        looksLikeDartSdk(Directory.systemTemp.path),
        isFalse,
        reason: 'A temp dir has no lib/_internal/allowed_experiments.json',
      );
    });

    test('accepts a directory that contains the SDK marker file', () {
      final tempDir =
          Directory.systemTemp.createTempSync('sdk_locator_marker_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final marker = File(
        p.join(tempDir.path, 'lib', '_internal', 'allowed_experiments.json'),
      );
      marker.parent.createSync(recursive: true);
      marker.writeAsStringSync('{}');

      expect(looksLikeDartSdk(tempDir.path), isTrue);
    });
  });

  group('resolveDartSdkPath', () {
    test('locates the running Dart SDK', () {
      final sdk = resolveDartSdkPath();

      expect(sdk, isNotNull,
          reason: 'Should resolve the SDK while running under `dart test`');
      expect(looksLikeDartSdk(sdk), isTrue,
          reason: 'Resolved path must contain the SDK marker file');
    });

    test('does not derive the SDK from a compiled-binary-style executable', () {
      // Regression guard for the AOT failure: the SDK must not be the
      // grandparent of an arbitrary executable. Whatever we resolve, it has to
      // be a real SDK (validated by the marker file), never a blind
      // dirname(dirname(exe)).
      final sdk = resolveDartSdkPath();
      expect(sdk, anyOf(isNull, predicate<String>(looksLikeDartSdk)));
    });

    test('caches the resolved path across calls when caching is enabled', () {
      debugResetDartSdkLocatorCache(enableCache: true);
      final first = resolveDartSdkPath();
      final second = resolveDartSdkPath();
      expect(second, equals(first));
    });
  });
}
