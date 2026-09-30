/// The shape of a [TomConsoleLogOutput] line.
///
/// Nothing asserted it, which is how a line reading `main-main` in every log
/// the framework emits went unexamined until someone documented the method
/// behind it. The pair is deliberate -- the rendering isolate, then the
/// isolate the entry came from -- and these tests say so.
library;

import 'package:test/test.dart';
import 'package:tom_basics/tom_basics.dart';

/// A platform that names its isolate and keeps what it is asked to print.
class _CapturingPlatform extends TomFallbackPlatformUtils {
  _CapturingPlatform(this.isolate);

  final String isolate;
  final List<String> stdout = [];
  final List<String> stderr = [];

  @override
  String getIsolateName() => isolate;

  @override
  void out(String s) => stdout.add(s);

  @override
  void outError(String s) => stderr.add(s);
}

void main() {
  late TomPlatformUtils installed;
  late _CapturingPlatform platform;
  final at = DateTime(2026, 9, 30, 8, 15, 42, 123, 456);

  setUp(() {
    installed = TomPlatformUtils.current;
    platform = _CapturingPlatform('renderer');
    TomPlatformUtils.setCurrentPlatform(platform);
  });

  tearDown(() => TomPlatformUtils.setCurrentPlatform(installed));

  group('TomConsoleLogOutput line', () {
    test('CLL-1: timestamp, rendering-originating isolate, level, message', () {
      TomConsoleLogOutput().output(
        TomLogLevel.all,
        TomLogLevel.info,
        'INFO ',
        'hello',
        'worker-3',
        at,
      );
      expect(platform.stdout, [
        '2026-09-30 08:15:42.123456 renderer-worker-3 INFO  hello ',
      ]);
    });

    test('CLL-2: an origin is appended in brackets', () {
      TomConsoleLogOutput().output(
        TomLogLevel.all,
        TomLogLevel.info,
        'INFO ',
        'hello',
        'main',
        at,
        'MyClass.method',
      );
      expect(platform.stdout.single, endsWith('hello  [MyClass.method]'));
    });

    test(
      'CLL-3: an entry logged where it is printed names its isolate twice',
      () {
        // The ordinary case: TomLogger fills the originating isolate from the
        // same platform call the output reads, so the pair is one name repeated.
        final logger = TomLogger()
          ..logOutput = TomConsoleLogOutput()
          ..setLogLevel(TomLogLevel.all);
        logger.info('hello');
        expect(platform.stdout.single, contains(' renderer-renderer '));
      },
    );

    test('CLL-4: errors go to stderr, not stdout', () {
      TomConsoleLogOutput().output(
        TomLogLevel.all,
        TomLogLevel.error,
        'ERROR',
        'broken',
        'main',
        at,
      );
      expect(platform.stderr.single, contains(' renderer-main ERROR broken'));
      expect(platform.stdout, isEmpty);
    });
  });
}
