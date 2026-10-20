/// The structured diagnostics port of `package:tom_basics/diagnostics.dart`,
/// and the bridge that sends `TomLogger` lines into it.
library;

import 'package:test/test.dart';
import 'package:tom_basics/tom_basics.dart';

class _Refused implements TomStructuredFailure {
  @override
  Map<String, Object> get diagnosticFields => {'status': 403};

  @override
  String toString() => 'refused: the body quoted a secret';
}

void main() {
  group('DIAG-P the port', () {
    test('DIAG-P1: an event is UTC and its map carries the fields beside the '
        'level and operation', () {
      final event = TomDiagnosticEvent(
        operation: 'sync.commit',
        level: TomDiagnosticLevel.warn,
        fields: {'locator': 'a.doc'},
        at: DateTime.utc(2026, 10, 20, 12),
      );
      expect(event.at.isUtc, isTrue);
      expect(event.toMap(), {
        'at': '2026-10-20T12:00:00.000Z',
        'level': 'warn',
        'operation': 'sync.commit',
        'locator': 'a.doc',
      });
    });

    test('DIAG-P2: the ring keeps the newest events up to its capacity', () {
      final ring = TomInMemoryDiagnostics(capacity: 2);
      for (final name in ['a', 'b', 'c']) {
        ring.log(TomDiagnosticEvent(operation: name, fields: const {}));
      }
      expect(ring.events.map((e) => e.operation), ['b', 'c']);
      ring.clear();
      expect(ring.events, isEmpty);
    });

    test('DIAG-P3: a notice logs its fields, never its sentence', () {
      final notice = TomDiagnosticNotice(
        operation: 'store.both_present',
        fields: {'folder': 'docs'},
        message: 'Two collaboration files were found; the encrypted one wins.',
      );
      final ring = TomInMemoryDiagnostics()..log(notice.event);
      expect(ring.events.single.toMap().values,
          isNot(contains(notice.message)));
      expect(ring.events.single.level, TomDiagnosticLevel.warn);
    });

    test('DIAG-P4: a failure is logged by its type and its structure, never '
        'its text', () {
      expect(tomFailureFields(_Refused()), {'error': '_Refused', 'status': 403});
      expect(tomFailureFields(StateError('quoted text')),
          {'error': 'StateError'});
    });

    test('DIAG-P5: the null sink accepts and keeps nothing', () {
      const TomNullDiagnostics()
          .log(TomDiagnosticEvent(operation: 'x', fields: const {}));
    });
  });

  group('DIAG-L TomLogger into the sink', () {
    late TomLogOutput previous;
    setUp(() => previous = tomLog.logOutput);
    tearDown(() => tomLog.logOutput = previous);

    test('DIAG-L1: a logged line becomes an event at the mapped level, with '
        'the rendered message and the isolate', () {
      final ring = TomInMemoryDiagnostics();
      tomLog.logOutput = TomDiagnosticsLogOutput(ring);
      tomLog.warn('disk almost full');
      tomLog.error('write refused');

      expect(ring.events.map((e) => e.level),
          [TomDiagnosticLevel.warn, TomDiagnosticLevel.error]);
      expect(ring.events.first.operation, 'log');
      expect(ring.events.first.fields['message'], 'disk almost full');
      expect(ring.events.first.fields['isolate'], isA<String>());
    });

    test('DIAG-L2: a line the logger filters out is not written', () {
      final ring = TomInMemoryDiagnostics();
      tomLog.logOutput = TomDiagnosticsLogOutput(ring);
      tomLog.pushLogLevel(TomLogLevel.errors);
      addTearDown(tomLog.popLogLevel);
      tomLog.info('chatter');
      expect(ring.events, isEmpty);
    });

    test('DIAG-L3: every logger level maps onto one of the four', () {
      final map = {
        TomLogLevel.fatal: TomDiagnosticLevel.error,
        TomLogLevel.severe: TomDiagnosticLevel.error,
        TomLogLevel.error: TomDiagnosticLevel.error,
        TomLogLevel.warn: TomDiagnosticLevel.warn,
        TomLogLevel.status: TomDiagnosticLevel.info,
        TomLogLevel.info: TomDiagnosticLevel.info,
        TomLogLevel.traffic: TomDiagnosticLevel.debug,
        TomLogLevel.debug: TomDiagnosticLevel.debug,
        TomLogLevel.trace: TomDiagnosticLevel.debug,
      };
      map.forEach((from, to) {
        expect(TomDiagnosticsLogOutput.diagnosticLevelOf(from), to);
      });
    });
  });
}
