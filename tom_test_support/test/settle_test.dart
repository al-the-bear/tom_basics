/// The settle a live suite makes between a write and the read that depends
/// on it.
library;

import 'package:test/test.dart';
import 'package:tom_test_support/settle.dart';

void main() {
  group('tomSettleUntil', () {
    test('SETTLE-1: returns the first value the condition accepts', () async {
      var reads = 0;
      final value = await tomSettleUntil<int>(
        what: 'the counter',
        read: () async => ++reads,
        done: (v) => v >= 3,
        timeout: const Duration(seconds: 5),
      );
      expect(value, 3);
      expect(reads, 3);
    });

    test(
      'SETTLE-2: a value accepted at once costs one read and no report',
      () async {
        final reports = <String>[];
        var reads = 0;
        await tomSettleUntil<bool>(
          what: 'the flag',
          read: () async {
            reads++;
            return true;
          },
          done: (v) => v,
          report: reports.add,
        );
        expect(reads, 1);
        expect(reports, isEmpty);
      },
    );

    test('SETTLE-3: at the deadline it throws, naming what was waited for, '
        'the last value and the cost', () async {
      final settle = tomSettleUntil<String>(
        what: 'the container to be retired',
        read: () async => 'present',
        done: (v) => v == 'gone',
        timeout: const Duration(milliseconds: 600),
      );
      await expectLater(
        settle,
        throwsA(
          isA<TomSettleTimeout>()
              .having((e) => e.what, 'what', 'the container to be retired')
              .having((e) => e.last, 'last', 'present')
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains('the container to be retired'),
                  contains('present'),
                  contains('reads over'),
                ),
              ),
        ),
      );
    });

    test(
      'SETTLE-4: a settle slower than slowAfter reports what it cost',
      () async {
        final reports = <String>[];
        var reads = 0;
        await tomSettleUntil<int>(
          what: 'the slow value',
          read: () async => ++reads,
          done: (v) => v >= 4,
          slowAfter: Duration.zero,
          report: reports.add,
        );
        expect(reports, hasLength(1));
        expect(
          reports.single,
          startsWith(
            'live settle: the slow value became '
            'visible after 4 reads over',
          ),
        );
      },
    );
  });
}
