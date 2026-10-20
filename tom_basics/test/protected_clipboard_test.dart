/// `TomProtectedClipboard`: a copied protected value is cleared after the
/// configured delay, only while the clipboard still holds it, and a later
/// copy supersedes an earlier one. Run with a fake clock and a fake clipboard.
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tom_basics/utilities.dart';

/// A clipboard that can be written by "another app" behind the service's back.
class FakeClipboard implements TomClipboardPort {
  String? text;
  int generation = 0;
  final placed = <String>[];
  bool refuse = false;

  void userCopies(String value) {
    text = value;
    generation++;
  }

  @override
  Future<TomClipboardReceipt?> placeConcealed(String value) async {
    if (refuse) return null;
    placed.add(value);
    userCopies(value);
    return TomClipboardReceipt(value, generation: generation);
  }

  @override
  Future<bool> clearIfHolding(TomClipboardReceipt receipt) async {
    if (generation != receipt.generation) return false;
    text = null;
    generation++;
    return true;
  }
}

/// A clock the test advances by hand.
class FakeClock {
  Duration now = Duration.zero;
  final _timers = <_FakeTimer>[];

  Timer create(Duration delay, void Function() callback) {
    final timer = _FakeTimer(now + delay, callback);
    _timers.add(timer);
    return timer;
  }

  Future<void> advance(Duration by) async {
    now += by;
    for (final timer in List.of(_timers)) {
      if (timer.isActive && timer.due <= now) timer.fire();
    }
    // Let the clear the timer started run to completion.
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeTimer implements Timer {
  final Duration due;
  final void Function() _callback;
  bool _active = true;

  _FakeTimer(this.due, this._callback);

  void fire() {
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

void main() {
  late FakeClipboard clipboard;
  late FakeClock clock;
  var delay = const Duration(seconds: 30);

  TomProtectedClipboard service({bool defaultDelay = false}) =>
      TomProtectedClipboard(
        port: clipboard,
        clearAfter: defaultDelay ? null : () => delay,
        timer: clock.create,
      );

  setUp(() {
    clipboard = FakeClipboard();
    clock = FakeClock();
    delay = const Duration(seconds: 30);
  });

  group('TOMCLIP clearing', () {
    test('TOMCLIP-1: a copied value is cleared after the default 30 s and not '
        'a moment before', () async {
      final copy = await service(defaultDelay: true).copy('hunter2');
      expect(copy.placed, isTrue);
      expect(copy.clearAfter, const Duration(seconds: 30));
      expect(clipboard.placed, ['hunter2']);

      await clock.advance(const Duration(seconds: 29));
      expect(clipboard.text, 'hunter2');
      await clock.advance(const Duration(seconds: 1));
      expect(clipboard.text, isNull);
    });

    test('TOMCLIP-2: what the user copied since is left alone — the clear '
        'runs only while the clipboard still holds the copied value', () async {
      final clip = service();
      await clip.copy('hunter2');
      await clock.advance(const Duration(seconds: 10));
      clipboard.userCopies('a shopping list');
      await clock.advance(const Duration(seconds: 30));
      expect(clipboard.text, 'a shopping list');
      expect(clip.isArmed, isFalse);
    });

    test('TOMCLIP-3: the delay is read at copy time; a second copy supersedes '
        'the first', () async {
      delay = const Duration(seconds: 10);
      final clip = service();
      await clip.copy('first');
      await clock.advance(const Duration(seconds: 5));
      delay = const Duration(seconds: 20);
      final second = await clip.copy('second');
      expect(second.clearAfter, const Duration(seconds: 20));

      // The first copy's 10 s pass: its clear must not take the second value.
      await clock.advance(const Duration(seconds: 6));
      expect(clipboard.text, 'second');
      await clock.advance(const Duration(seconds: 14));
      expect(clipboard.text, isNull);
    });

    test('TOMCLIP-4: clearNow clears a held value at once; a refused copy arms '
        'nothing', () async {
      final clip = service();
      await clip.copy('token');
      expect(await clip.clearNow(), isTrue);
      expect(clipboard.text, isNull);
      expect(clip.isArmed, isFalse);

      clipboard
        ..refuse = true
        ..userCopies('mine');
      final refused = await clip.copy('never placed');
      expect(refused.placed, isFalse);
      expect(clip.isArmed, isFalse);
      await clock.advance(const Duration(minutes: 1));
      expect(clipboard.text, 'mine');
    });
  });

  group('TOMCLIP the service reports its state', () {
    test('TOMCLIP-5: a copy arms with its delay; the expiry clears; the state '
        'names nothing of the value', () async {
      final clip = service();
      final seen = <TomProtectedClipboardState>[];
      clip.states.listen(seen.add);
      expect(clip.state.armed, isFalse);
      await clip.copy('hunter2');
      expect(clip.state.armed, isTrue);
      expect(clip.state.clearAfter, const Duration(seconds: 30));
      expect(seen.last.armed, isTrue);
      expect('${seen.last}', isNot(contains('hunter2')));
      await clock.advance(const Duration(seconds: 30));
      expect(clip.state.armed, isFalse);
      expect(seen.last.armed, isFalse);
    });

    test('TOMCLIP-6: a second copy supersedes — cleared then armed again — and '
        'clearNow and dispose both end in cleared', () async {
      final clip = service();
      final seen = <TomProtectedClipboardState>[];
      clip.states.listen(seen.add);
      await clip.copy('one');
      await clip.copy('two');
      expect(seen.map((s) => s.armed).toList(), [true, false, true]);
      await clip.clearNow();
      expect(clip.state.armed, isFalse);
      await clip.copy('three');
      clip.dispose();
      expect(clip.state.armed, isFalse);
    });
  });
}
