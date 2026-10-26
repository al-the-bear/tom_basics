/// The Dart CLI resolver (`dart_cli.dart`).
///
/// **Deadline.** `tomDartCli` may ask the PATH, which spawns `which`, so this
/// file states its own harness bound.
@Timeout(Duration(seconds: 30))
library;

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_test_support/dart_cli.dart';

void main() {
  group('TSUP-CLI the Dart CLI is located, not assumed', () {
    test('TSUP-CLI-1: under `dart test` the runner is the CLI, and '
        'nothing is spawned', () {
      var asked = false;
      expect(
        tomDartFrom('/sdk/bin/dart', () {
          asked = true;
          return '/elsewhere/dart';
        }),
        '/sdk/bin/dart',
      );
      expect(
        asked,
        isFalse,
        reason:
            'the PATH was consulted although the runner was already the '
            'Dart CLI',
      );
    });

    test('TSUP-CLI-2: under another runner the PATH answers', () {
      expect(
        tomDartFrom(
          '/flutter/cache/artifacts/engine/x/flutter_tester',
          () => '/sdk/bin/dart',
        ),
        '/sdk/bin/dart',
      );
    });

    test('TSUP-CLI-3: with no Dart CLI anywhere the answer is null, not '
        'the runner', () {
      expect(tomDartFrom('/flutter/x/flutter_tester', () => null), isNull);
      expect(
        tomDartFrom('/flutter/x/flutter_tester', () => ''),
        isNull,
        reason: 'an empty `which` result is a miss, not a path',
      );
    });

    test('TSUP-CLI-4: this machine resolves one', () {
      final dart = tomDartCli();
      expect(dart, isNotNull);
      expect(p.basenameWithoutExtension(dart!), 'dart');
    });

    test(
      'TSUP-CLI-5: a missing CLI fails naming the runner and the remedy',
      () {
        final reason = tomMissingDartReason('stand in for Node');
        expect(
          reason,
          contains('stand in for Node'),
          reason: 'which test needed it',
        );
        expect(reason, contains('dart test'), reason: 'the remedy');
        expect(
          reason,
          contains('flutter_tester'),
          reason: 'the runner that is not a Dart CLI, named',
        );
      },
    );
  });
}
