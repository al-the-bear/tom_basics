import 'dart:async';

import 'package:tom_basics/utilities.dart';
import 'package:test/test.dart';

void main() {
  group('TomCancellationSource', () {
    test('token starts uncancelled', () {
      final cts = TomCancellationSource();
      expect(cts.isCancelled, isFalse);
      expect(cts.token.isCancelled, isFalse);
    });

    test('cancel signals the token and resolves whenCancelled', () async {
      final cts = TomCancellationSource();
      final done = cts.token.whenCancelled;
      cts.cancel();
      expect(cts.isCancelled, isTrue);
      expect(cts.token.isCancelled, isTrue);
      await done; // resolves, does not throw
    });

    test('cancel is idempotent', () {
      final cts = TomCancellationSource()..cancel();
      expect(cts.cancel, returnsNormally);
      expect(cts.isCancelled, isTrue);
    });

    test('awaiting an already-cancelled token returns immediately', () async {
      final cts = TomCancellationSource()..cancel();
      await cts.token.whenCancelled.timeout(const Duration(seconds: 1));
    });
  });

  group('TomCancellationToken.none', () {
    test('is never cancelled', () {
      expect(TomCancellationToken.none.isCancelled, isFalse);
    });

    test('whenCancelled never resolves', () {
      var resolved = false;
      unawaited(
        TomCancellationToken.none.whenCancelled.then((_) {
          resolved = true;
        }),
      );
      expect(resolved, isFalse);
    });
  });

  group('TomOperationCancelled', () {
    test('toString reflects the optional operation label', () {
      expect(const TomOperationCancelled().toString(), 'TomOperationCancelled');
      expect(
        const TomOperationCancelled('embedBatch').toString(),
        'TomOperationCancelled(embedBatch)',
      );
    });
  });
}
