/// The wait a widget suite makes for a **network-backed** action: real time
/// passes, a frame is pumped, and the two alternate until a condition holds
/// or a deadline passes — and the failure says what was on screen.
///
/// **Why `pumpAndSettle` cannot do this.** `testWidgets` runs on a fake clock:
/// a settle pumps frames until none is scheduled, advancing that clock, and
/// gives up on its own timeout. A load against a real server finishes in
/// **real** time, which the fake clock does not advance, while the widget
/// shows an indeterminate progress indicator that schedules a frame for as
/// long as the load takes. So the settle never sees a quiet frame and times
/// out, on a widget that is doing exactly what it should. An in-memory load
/// never meets this, because it completes inside a single pump.
///
/// **What the wait does instead.** Let real time pass — in Flutter, inside
/// `runAsync` — then pump one frame **outside** it, and ask the condition;
/// repeat. The two halves must stay apart: a frame pumped inside `runAsync`
/// trips the binding's own zone assertion, and real time waited outside it
/// never reaches a future the fake zone owns.
///
/// **Why the policy is here and the `WidgetTester` binding is not.** This
/// package is pure Dart, so a pure-Dart package's suite can resolve it with
/// `dart pub get`; a `flutter_test` dependency would stop that, since
/// `flutter_test` pins `analyzer` and the test API to its own versions. What
/// both test frameworks can share is here and framework-free: the order of
/// the loop, the deadline, the step, the shape of the report. The binding to
/// a `WidgetTester` — `tester.pumpUntil(finder)` — is
/// `package:tom_reusable_ui/testing.dart`'s.
library;

/// How long a wait may take before it reports. Two minutes: above a slow
/// live load (a thread arriving from a real issue tracker, a model's
/// completion under a slow transport) and below a live test's usual
/// five-minute bound, so the report is this one and not the harness's.
const tomDefaultPumpUntilTimeout = Duration(minutes: 2);

/// Real time let pass between two frames. A quarter second: fine enough that
/// a fast round trip is not charged a slow one's budget, coarse enough that
/// a two-minute wait is 480 frames and not 120 000.
const tomDefaultPumpUntilStep = Duration(milliseconds: 250);

/// The deadline passed before the condition held.
///
/// Carries what was waited for, how long, and what the screen held at the
/// end — the datum that separates "the load never came" from "the load came
/// and the widget shows it under another key".
class TomPumpUntilTimeout implements Exception {
  /// What the wait was for, as the caller named it.
  final String what;

  /// Real time that passed before giving up.
  final Duration waited;

  /// The deadline that passed.
  final Duration timeout;

  /// The screen at the end, as the caller's `onScreen` rendered it.
  final String onScreen;

  /// Where to look first, when the caller knows.
  final String? hint;

  TomPumpUntilTimeout({
    required this.what,
    required this.waited,
    required this.timeout,
    required this.onScreen,
    this.hint,
  });

  /// The report, in one paragraph.
  String get message {
    final buffer = StringBuffer()
      ..write(
        'Waited ${_seconds(waited)} for $what and it never arrived '
        '(deadline ${_seconds(timeout)}). On screen at the end: $onScreen',
      );
    if (hint != null) buffer.write('\n$hint');
    return buffer.toString();
  }

  @override
  String toString() => 'TomPumpUntilTimeout: $message';

  static String _seconds(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
}

/// Alternates [passTime] and [pumpFrame] until [matches] holds, and throws
/// [TomPumpUntilTimeout] — naming [what], the time waited and [onScreen]'s
/// rendering — once [timeout] of real time has passed without it.
///
/// [matches] is asked **first**, before any time passes: a condition that
/// already holds costs nothing. It must therefore state a *result* ("the
/// comment is in the store", "the loading key is gone") and never the absence
/// of one ("nothing is pending"), which is true the instant an interaction
/// returns and before its handler has reached its first await — a wait for
/// "zero pending" passes on a store that has not started its write yet.
///
/// [passTime] receives [step] and lets that much real time pass; [pumpFrame]
/// renders one frame afterwards. The Flutter binding supplies
/// `runAsync(() => Future.delayed(step))` and `pump()` respectively.
Future<void> tomPumpUntil({
  required String what,
  required bool Function() matches,
  required Future<void> Function() pumpFrame,
  required Future<void> Function(Duration step) passTime,
  required String Function() onScreen,
  Duration timeout = tomDefaultPumpUntilTimeout,
  Duration step = tomDefaultPumpUntilStep,
  String? hint,
}) async {
  final clock = Stopwatch()..start();
  while (!matches()) {
    if (clock.elapsed >= timeout) {
      throw TomPumpUntilTimeout(
        what: what,
        waited: clock.elapsed,
        timeout: timeout,
        onScreen: onScreen(),
        hint: hint,
      );
    }
    await passTime(step);
    await pumpFrame();
  }
}
