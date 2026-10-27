import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_test_support/tom_test_support.dart';

void main() {
  group('TomBrowserSuite', () {
    late Directory package;

    setUp(() {
      package = Directory.systemTemp.createTempSync('browser_suite_');
    });
    tearDown(() => package.deleteSync(recursive: true));

    /// A fake SDK whose `bin/flutter` exists.
    String fakeFlutterRoot() {
      final root = Directory('${package.path}/sdk/bin')
        ..createSync(recursive: true);
      File(
        '${root.path}/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
      ).writeAsStringSync('');
      return '${package.path}/sdk';
    }

    test('BS-1: the skip variable wins and names itself', () {
      final suite = TomBrowserSuite(
        workingDirectory: package.path,
        environment: {'TOM_SKIP_BROWSER_TESTS': '1'},
      );
      expect(suite.skipReason, contains('TOM_SKIP_BROWSER_TESTS=1'));
    });

    test('BS-2: no FLUTTER_ROOT is a skip that says so', () {
      final suite = TomBrowserSuite(
        workingDirectory: package.path,
        environment: const {},
      );
      expect(suite.skipReason, contains('FLUTTER_ROOT'));
      expect(suite.skipReason, contains('unset'));
      expect(suite.run, throwsStateError);
    });

    test('BS-3: a package without the directory is a skip naming it', () {
      final suite = TomBrowserSuite(
        workingDirectory: package.path,
        environment: {'FLUTTER_ROOT': fakeFlutterRoot()},
      );
      expect(suite.skipReason, contains('test/browser'));
    });

    test('BS-4: an SDK and the directory run', () {
      Directory('${package.path}/test/browser').createSync(recursive: true);
      final suite = TomBrowserSuite(
        workingDirectory: package.path,
        environment: {'FLUTTER_ROOT': fakeFlutterRoot()},
      );
      expect(suite.skipReason, isNull);
      expect(suite.flutterExecutable, startsWith('${package.path}/sdk/bin/'));
    });

    test('BS-5: a failing exit is a failure carrying the output', () {
      final failure = TomBrowserSuite.failureOf(
        ProcessResult(1, 1, 'some test failed', 'boom'),
      );
      expect(failure, contains('exit 1'));
      expect(failure, contains('some test failed'));
      expect(failure, contains('boom'));
    });

    test(
      'BS-6: exit 0 without a passing summary is a failure (vacuous run)',
      () {
        expect(
          TomBrowserSuite.failureOf(ProcessResult(1, 0, 'No tests ran.', '')),
          contains('fully-skipped'),
        );
      },
    );

    test('BS-7: exit 0 with a passing summary is no failure', () {
      expect(
        TomBrowserSuite.failureOf(
          ProcessResult(1, 0, '00:03 +4: All tests passed!', ''),
        ),
        isNull,
      );
    });
  });
}
