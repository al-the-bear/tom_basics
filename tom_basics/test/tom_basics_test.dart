import 'dart:async';

import 'package:tom_basics/tom_basics.dart';
import 'package:test/test.dart';

void main() {
  group('TomBaseException', () {
    test('creates exception with key and message', () {
      final exception = TomBaseException(
        'test.error.key',
        'Test error message',
      );

      expect(exception.key, equals('test.error.key'));
      expect(exception.defaultUserMessage, equals('Test error message'));
      expect(exception.uuid, isNotEmpty);
      expect(exception.timeStamp, isA<DateTime>());
    });

    test('creates exception with parameters', () {
      final exception = TomBaseException(
        'users.validate.invalid_email',
        'Invalid input',
        parameters: {'field': 'email', 'value': 'invalid'},
      );

      expect(exception.parameters, isNotNull);
      expect(exception.parameters!['field'], equals('email'));
      expect(exception.parameters!['value'], equals('invalid'));
    });

    test('uses provided uuid when specified', () {
      final exception = TomBaseException(
        'test.error.key',
        'Test error',
        uuid: 'custom-uuid-123',
      );

      expect(exception.uuid, equals('custom-uuid-123'));
    });

    test('captures rootException', () {
      final rootError = Exception('Original error');
      final exception = TomBaseException(
        'test.wrap.rethrown',
        'Wrapped error message',
        rootException: rootError,
      );

      expect(exception.rootException, equals(rootError));
    });

    test('toString includes key information', () {
      final exception = TomBaseException('test.error.key', 'Error message');
      final str = exception.toString();

      expect(str, contains('test.error.key'));
      expect(str, contains('Error message'));
    });

    test('stackTrace is captured', () {
      final exception = TomBaseException('test.error.bare', 'Test');

      expect(exception.stackTrace, isNotEmpty);
    });
  });

  group('TomLogOutput.output', () {
    test('origin is optional, as the parameter documentation says', () {
      // Declared as a required positional, the word "optional" was true of the
      // value and false of the signature — and because an override may widen a
      // required positional to optional, both spellings compiled, so
      // implementations across the workspace split between them with nothing
      // to say which was intended.
      final recorder = _RecordingLogOutput();
      // Through the *base* type on purpose. Called on the concrete class this
      // would only prove that implementation widened the parameter, which any
      // override may do; six arguments type-check here only if the abstract
      // declaration itself makes `origin` optional.
      final TomLogOutput sink = recorder;

      sink.output(
        TomLogLevel.production,
        TomLogLevel.info,
        'INFO   ',
        'no origin given',
        'main',
        DateTime(2026, 1, 2),
      );

      expect(recorder.lastMessage, equals('no origin given'));
      expect(recorder.lastOrigin, isNull);
    });

    test('an origin still arrives when one is given', () {
      final recorder = _RecordingLogOutput();
      final TomLogOutput sink = recorder;

      sink.output(
        TomLogLevel.production,
        TomLogLevel.info,
        'INFO   ',
        'with origin',
        'main',
        DateTime(2026, 1, 2),
        'App.boot',
      );

      expect(recorder.lastOrigin, equals('App.boot'));
    });
  });

  group('the stack-trace renderer seam', () {
    // tom_basics sits at the bottom and has no view of what counts as noise in
    // the layers above it, so it ships a narrow default and lets a framework
    // that does have one override it. Without the seam the string this class
    // stores at construction and whatever the framework formats later are
    // produced by two algorithms that quietly disagree.

    test('the constructor fills stackTrace through renderStackTrace', () {
      final exception = _RecordingException('test.render.seam', 'Test');

      expect(exception.renderCalls, 1);
      expect(exception.stackTrace, 'RENDERED');
      expect(exception.lastDepth, -1);
    });

    test('an override receives the stack the constructor was given', () {
      final handed = StackTrace.fromString(
        '#0      failing (package:my_app/a.dart:1:1)\n',
      );

      final exception = _RecordingException(
        'test.render.given',
        'Test',
        stack: handed,
      );

      expect(exception.lastStack, same(handed));
    });

    test('the default renderer folds core frames and keeps the rest', () {
      final exception = TomBaseException(
        'test.render.default',
        'Test',
        stack: StackTrace.fromString(
          '#0      failing (package:my_app/a.dart:1:1)\n'
          '#1      calling (package:my_app/b.dart:2:2)\n',
        ),
      );

      final lines = exception.stackTrace.split('\n');
      expect(lines, hasLength(2));
      expect(lines.first, contains('failing'));
      expect(lines.last, contains('calling'));
    });

    test('a non-negative depth is a bound, counting from the throw site', () {
      final exception = TomBaseException('test.render.depth', 'Test');
      final trace = StackTrace.fromString(
        '#0      failing (package:my_app/a.dart:1:1)\n'
        '#1      calling (package:my_app/b.dart:2:2)\n'
        '#2      main (package:my_app/c.dart:3:3)\n',
      );

      expect(exception.renderStackTrace(trace, 2).split('\n'), hasLength(2));
      expect(exception.renderStackTrace(trace, 2), contains('failing'));
      expect(exception.renderStackTrace(trace, 2), isNot(contains('main')));
    });

    test('depth 0 asks for no frames and every negative means all', () {
      final exception = TomBaseException('test.render.zero', 'Test');
      final trace = StackTrace.fromString(
        '#0      failing (package:my_app/a.dart:1:1)\n'
        '#1      calling (package:my_app/b.dart:2:2)\n',
      );

      // Read as `depth > 0`, a computed 0 fell through to "all frames" — the
      // opposite of what it asks for.
      expect(exception.renderStackTrace(trace, 0), isEmpty);
      expect(exception.renderStackTrace(trace, -1).split('\n'), hasLength(2));
      expect(exception.renderStackTrace(trace, -2).split('\n'), hasLength(2));
      expect(exception.renderStackTrace(trace, 99).split('\n'), hasLength(2));
    });
  });

  group('TomBaseException.printStackTrace', () {
    final trace = StackTrace.fromString(
      '#0      failing (package:my_app/a.dart:1:1)\n'
      '#1      calling (package:my_app/b.dart:2:2)\n'
      '#2      main (package:my_app/c.dart:3:3)\n',
    );

    String printed(TomBaseException e, [int depth = -1]) {
      final lines = <String>[];
      runZoned(
        () => e.printStackTrace(depth),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => lines.add(line),
        ),
      );
      return lines.single;
    }

    test('bounds the frames it prints', () {
      final exception = TomBaseException(
        'test.print.depth',
        'Test',
        stack: trace,
      );

      final body = printed(exception, 2).split('\n').skip(1).toList();

      expect(body, hasLength(2));
      expect(body.first, contains('failing'));
      expect(body.last, contains('calling'));
    });

    test('prints every frame by default', () {
      final exception = TomBaseException(
        'test.print.all',
        'Test',
        stack: trace,
      );

      expect(printed(exception).split('\n').skip(1), hasLength(3));
    });

    test('depth 0 prints the identifying line and no frames', () {
      final exception = TomBaseException(
        'test.print.zero',
        'Test',
        stack: trace,
      );

      final lines = printed(exception, 0).split('\n');

      expect(lines, hasLength(2));
      expect(lines.first, contains('exception stacktrace:'));
      expect(lines.last, isEmpty);
    });

    test('bounds the trace captured at construction, never a fresh one', () {
      // Re-formatting here would have to decide what to do about a null
      // `stack`, and falling back to `StackTrace.current` would report the
      // call path of the report rather than of the failure.
      final exception = TomBaseException('test.print.stored', 'Test');
      exception.stack = null;

      final body = printed(exception).split('\n').skip(1).join('\n');

      expect(body, exception.stackTrace);
      expect(body, isNot(contains('printStackTrace')));
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

  group('TomRuntime.reset', () {
    // The environment/platform registries are process-global static state, so
    // each test resets first to isolate itself from the others.
    setUp(TomRuntime.reset);

    test('clears registered environments and drops the active selection', () {
      TomRuntime.addEnvironment(TomEnvironment('dev', isDevelopment: true));
      TomRuntime.setCurrentEnvironment('dev');
      expect(TomRuntime.getEnvironments(), isNotEmpty);
      expect(TomRuntime.getCurrentEnvironment().env, equals('dev'));

      TomRuntime.reset();

      expect(TomRuntime.getEnvironments(), isEmpty);
      expect(TomRuntime.getRoot(), same(defaultTomEnvironment));
      // No current environment after reset.
      expect(TomRuntime.getCurrentEnvironment, throwsA(isA<Exception>()));
    });

    test(
      'a fresh registration after reset resolves the correct environment',
      () {
        // A stale 'dev' registered before reset must not shadow the new one.
        TomRuntime.addEnvironment(TomEnvironment('dev'));
        TomRuntime.reset();

        var initialized = false;
        TomRuntime.addEnvironment(
          TomEnvironment(
            'dev',
            isDevelopment: true,
            initializer: (_) => initialized = true,
          ),
        );
        TomRuntime.setCurrentEnvironment('dev');
        TomRuntime.getCurrentEnvironment().initialize();

        expect(TomRuntime.getEnvironments(), hasLength(1));
        expect(initialized, isTrue);
      },
    );

    test('clears registered platforms', () {
      TomRuntime.addPlatform(const TomPlatform('custom'));
      expect(TomRuntime.getPlatforms(), isNotEmpty);

      TomRuntime.reset();

      expect(TomRuntime.getPlatforms(), isEmpty);
      expect(TomRuntime.getCurrentPlatform(), isNull);
    });
  });

  group('TomRuntime.setCurrentEnvironment fallback', () {
    setUp(TomRuntime.reset);

    test('resolves a registered environment by name', () {
      TomRuntime.addEnvironment(const TomEnvironment('dev'));
      TomRuntime.setCurrentEnvironment('dev');
      expect(TomRuntime.getCurrentEnvironment().env, equals('dev'));
    });

    test('unknown name with defaultRoot fallback resolves to the default', () {
      TomRuntime.setCurrentEnvironment('nonexistent', 'defaultRoot');
      expect(TomRuntime.getCurrentEnvironment(), same(defaultTomEnvironment));
    });

    test('unknown name with a named fallback resolves to that fallback', () {
      TomRuntime.addEnvironment(const TomEnvironment('development'));
      TomRuntime.setCurrentEnvironment('missing', 'development');
      expect(TomRuntime.getCurrentEnvironment().env, equals('development'));
    });

    test('fallback replaces an already-set current environment', () {
      // Regression: the setter must not silently keep a previously-set
      // environment when the requested name is absent — the fallback applies
      // regardless of prior state.
      TomRuntime.addEnvironment(const TomEnvironment('current'));
      TomRuntime.addEnvironment(const TomEnvironment('development'));
      TomRuntime.setCurrentEnvironment('current');
      expect(TomRuntime.getCurrentEnvironment().env, equals('current'));

      TomRuntime.setCurrentEnvironment('missing', 'development');
      expect(TomRuntime.getCurrentEnvironment().env, equals('development'));

      TomRuntime.setCurrentEnvironment('gone', 'defaultRoot');
      expect(TomRuntime.getCurrentEnvironment(), same(defaultTomEnvironment));
    });

    test('unknown name and unknown fallback fall through to the root', () {
      final root = TomRuntime.addEnvironment(const TomEnvironment('root'));
      TomRuntime.setRootEnvironment(root);
      TomRuntime.setCurrentEnvironment('missing', 'alsomissing');
      expect(TomRuntime.getCurrentEnvironment(), same(root));
    });
  });
}

/// Records what the constructor handed the renderer seam, and answers with a
/// fixed string so the call is visible in `stackTrace`.
class _RecordingException extends TomBaseException {
  _RecordingException(super.key, super.defaultUserMessage, {super.stack});

  int renderCalls = 0;
  StackTrace? lastStack;
  int? lastDepth;

  @override
  String renderStackTrace(StackTrace? stack, int depth) {
    renderCalls++;
    lastStack = stack;
    lastDepth = depth;
    return 'RENDERED';
  }
}

/// Minimal [TomLogOutput] used to check what the base signature permits.
class _RecordingLogOutput extends TomLogOutput {
  String? lastMessage;
  String? lastOrigin;

  @override
  void output(
    TomLogLevel loggerLevel,
    TomLogLevel logLevel,
    String level,
    Object message,
    String isolateName,
    DateTime timeStamp, [
    String? origin,
  ]) {
    lastMessage = convertToString(message);
    lastOrigin = origin;
  }
}
