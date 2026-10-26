/// The wait for a network-backed action, as a policy.
///
/// Driven with fakes for the three primitives — time passing, a frame, the
/// screen — so what is pinned is the loop itself: the order of asking,
/// waiting and pumping, the deadline, and the report. The `WidgetTester`
/// binding is proven where it lives, in `tom_reusable_ui`'s suite.
library;

import 'package:test/test.dart';
import 'package:tom_test_support/pump_until.dart';

void main() {
  group('TSUP-WAIT tomPumpUntil', () {
    test('TSUP-WAIT-1: a condition that comes to hold ends the wait, with a '
        'frame pumped after every step of real time', () async {
      final events = <String>[];
      var asked = 0;
      await tomPumpUntil(
        what: 'the third ask',
        matches: () {
          asked++;
          events.add('ask $asked');
          return asked == 3;
        },
        pumpFrame: () async => events.add('frame'),
        passTime: (step) async => events.add('wait ${step.inMilliseconds}'),
        onScreen: () => fail('the screen is only rendered for a report'),
        step: const Duration(milliseconds: 40),
      );
      // Asked first; then time, then a frame, then asked again — never a
      // frame before time has passed, never an ask before a frame.
      expect(events, [
        'ask 1',
        'wait 40',
        'frame',
        'ask 2',
        'wait 40',
        'frame',
        'ask 3',
      ]);
    });

    test('TSUP-WAIT-2: a condition that already holds costs no time and no '
        'frame', () async {
      var waited = 0;
      var framed = 0;
      await tomPumpUntil(
        what: 'nothing',
        matches: () => true,
        pumpFrame: () async => framed++,
        passTime: (_) async => waited++,
        onScreen: () => '',
      );
      expect(waited, 0);
      expect(framed, 0);
    });

    test('TSUP-WAIT-3: the deadline reports what was waited for, how long, '
        'what the screen held, and the hint', () async {
      var renders = 0;
      final run = tomPumpUntil(
        what: "the model's answer",
        matches: () => false,
        pumpFrame: () async {},
        passTime: (step) => Future<void>.delayed(step),
        onScreen: () {
          renders++;
          return 'texts: [Loading…]';
        },
        timeout: const Duration(milliseconds: 60),
        step: const Duration(milliseconds: 10),
        hint: 'Check the far end before reading this as a defect here.',
      );
      await expectLater(
        run,
        throwsA(
          isA<TomPumpUntilTimeout>()
              .having((e) => e.what, 'what', "the model's answer")
              .having(
                (e) => e.waited,
                'waited',
                greaterThanOrEqualTo(const Duration(milliseconds: 60)),
              )
              .having(
                (e) => e.timeout,
                'timeout',
                const Duration(milliseconds: 60),
              )
              .having((e) => e.onScreen, 'onScreen', 'texts: [Loading…]')
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains("for the model's answer and it never arrived"),
                  contains('deadline 0.1 s'),
                  contains('On screen at the end: texts: [Loading…]'),
                  endsWith(
                    'Check the far end before reading this as a defect '
                    'here.',
                  ),
                ),
              ),
        ),
      );
      // The screen is rendered for the report and for nothing else: it can
      // be large, and a wait that passes should not have paid for it.
      expect(renders, 1);
    });

    test(
      'TSUP-WAIT-4: the defaults are a two-minute deadline at a quarter-second '
      'step — above the longest live load, below every live test\'s own '
      'bound',
      () {
        expect(tomDefaultPumpUntilTimeout, const Duration(minutes: 2));
        expect(tomDefaultPumpUntilStep, const Duration(milliseconds: 250));
        expect(
          tomDefaultPumpUntilTimeout,
          lessThan(const Duration(minutes: 5)),
        );
      },
    );
  });
}
