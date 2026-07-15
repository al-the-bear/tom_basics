import 'package:tom_basics/tom_basics.dart';
import 'package:test/test.dart';

void main() {
  group('TomBaseException', () {
    test('creates exception with key and message', () {
      final exception = TomBaseException('TEST_ERROR', 'Test error message');

      expect(exception.key, equals('TEST_ERROR'));
      expect(exception.defaultUserMessage, equals('Test error message'));
      expect(exception.uuid, isNotEmpty);
      expect(exception.timeStamp, isA<DateTime>());
    });

    test('creates exception with parameters', () {
      final exception = TomBaseException(
        'VALIDATION_ERROR',
        'Invalid input',
        parameters: {'field': 'email', 'value': 'invalid'},
      );

      expect(exception.parameters, isNotNull);
      expect(exception.parameters!['field'], equals('email'));
      expect(exception.parameters!['value'], equals('invalid'));
    });

    test('uses provided uuid when specified', () {
      final exception = TomBaseException(
        'TEST_ERROR',
        'Test error',
        uuid: 'custom-uuid-123',
      );

      expect(exception.uuid, equals('custom-uuid-123'));
    });

    test('captures rootException', () {
      final rootError = Exception('Original error');
      final exception = TomBaseException(
        'WRAPPED_ERROR',
        'Wrapped error message',
        rootException: rootError,
      );

      expect(exception.rootException, equals(rootError));
    });

    test('toString includes key information', () {
      final exception = TomBaseException('ERROR_KEY', 'Error message');
      final str = exception.toString();

      expect(str, contains('ERROR_KEY'));
      expect(str, contains('Error message'));
    });

    test('stackTrace is captured', () {
      final exception = TomBaseException('ERROR', 'Test');

      expect(exception.stackTrace, isNotEmpty);
    });
  });

  group('TomLogger log-level stack', () {
    test('setLogLevel replaces the current effective level', () {
      final logger = TomLogger();
      logger.setLogLevel(TomLogLevel.info);
      expect(
        logger.logLevel.levelPattern,
        equals(TomLogLevel.info.levelPattern),
      );
    });

    test('pushLogLevel sets the level, popLogLevel restores the level '
        'that was active before the push', () {
      final logger = TomLogger();
      logger.setLogLevelByName('info');
      logger.pushLogLevel(TomLogLevel.trace);
      expect(
        logger.logLevel.levelPattern,
        equals(TomLogLevel.trace.levelPattern),
      );

      logger.popLogLevel();
      // The pre-push level (info) must be restored, not left at trace.
      expect(
        logger.logLevel.levelPattern,
        equals(TomLogLevel.info.levelPattern),
      );
    });

    test('nested pushes pop back in LIFO order', () {
      final logger = TomLogger();
      logger.setLogLevel(TomLogLevel.warn);

      logger.pushLogLevel(TomLogLevel.info);
      logger.pushLogLevel(TomLogLevel.debug);
      logger.pushLogLevel(TomLogLevel.trace);
      expect(
        logger.logLevel.levelPattern,
        equals(TomLogLevel.trace.levelPattern),
      );

      logger.popLogLevel();
      expect(
        logger.logLevel.levelPattern,
        equals(TomLogLevel.debug.levelPattern),
      );

      logger.popLogLevel();
      expect(
        logger.logLevel.levelPattern,
        equals(TomLogLevel.info.levelPattern),
      );

      logger.popLogLevel();
      expect(
        logger.logLevel.levelPattern,
        equals(TomLogLevel.warn.levelPattern),
      );
    });

    test('popLogLevel on the base level is a no-op', () {
      final logger = TomLogger();
      logger.setLogLevel(TomLogLevel.production);
      logger.popLogLevel();
      expect(
        logger.logLevel.levelPattern,
        equals(TomLogLevel.production.levelPattern),
      );
    });
  });
}
