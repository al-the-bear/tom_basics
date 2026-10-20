/// Protected-value copying with auto-clear: a copied password, token or key
/// stays on the system clipboard for a bounded time and no longer.
///
/// The service is here and the clipboard is not. Placing text and reading it
/// back are platform facts (Flutter's `Clipboard`, a runner channel, a browser
/// API), so this library names a port, [TomClipboardPort], which an
/// application binds. What it owns is the part that has to be the same
/// everywhere:
///
/// - **When.** [TomProtectedClipboard.copy] arms one timer; the delay is asked
///   for at copy time (`clearAfter`, default **30 s**), so a changed setting
///   affects the next copy and never one already on the clipboard.
/// - **Only if it is still ours.** The clear runs through
///   [TomClipboardPort.clearIfHolding], which clears only while the clipboard
///   still holds what this copy placed. Something the user copied since — from
///   this app or any other — is theirs and survives.
/// - **One at a time.** A second protected copy supersedes the first: the
///   first value is no longer on the clipboard, so its timer is dropped and
///   the new value's runs.
///
/// Transient/concealed marking ("do not record in clipboard history") is the
/// port's business, because only the platform knows its flag.
library;

import 'dart:async';

import 'package:meta/meta.dart';

/// What a binding placed: enough to recognise it later.
class TomClipboardReceipt {
  /// The text placed — compared with the clipboard's text by a binding that
  /// has no better way to tell.
  final String text;

  /// The platform's own generation counter after the write, when it has one
  /// (macOS `NSPasteboard.changeCount`). A binding that has one compares it
  /// instead of the text, which also notices the user copying the same text
  /// again from elsewhere.
  final int? generation;

  const TomClipboardReceipt(this.text, {this.generation});
}

/// The platform clipboard as the protected-copy service needs it.
abstract interface class TomClipboardPort {
  /// Places [text] on the system clipboard, marked transient/concealed where
  /// the platform offers such a flag. Null when the platform refused.
  Future<TomClipboardReceipt?> placeConcealed(String text);

  /// Clears the clipboard **only** while it still holds what [receipt]
  /// placed. True when it cleared.
  Future<bool> clearIfHolding(TomClipboardReceipt receipt);
}

/// Arms a timer. A parameter so a test can run the clock itself.
typedef TomTimerFactory = Timer Function(
  Duration delay,
  void Function() callback,
);

/// What the clipboard service holds right now — what a countdown chip shows.
///
/// [armed] with its [clearAfter] while a copied value waits to be cleared;
/// [cleared] once the clear ran, the user's own copy superseded it, or the
/// service was told to let go. The state carries the delay the copy was armed
/// with and nothing of the value: a chip counts down from it.
class TomProtectedClipboardState {
  /// Whether a copied value is still waiting to be cleared.
  final bool armed;

  /// The delay the pending clear was armed with; zero when nothing is.
  final Duration clearAfter;

  const TomProtectedClipboardState.armed(this.clearAfter) : armed = true;

  const TomProtectedClipboardState.cleared()
      : armed = false,
        clearAfter = Duration.zero;

  @override
  String toString() => armed
      ? 'TomProtectedClipboardState.armed(${clearAfter.inSeconds}s)'
      : 'TomProtectedClipboardState.cleared';
}

/// What [TomProtectedClipboard.copy] did.
class TomProtectedCopy {
  /// Whether the value reached the clipboard.
  final bool placed;

  /// How long it stays there unless the user replaces it first.
  final Duration clearAfter;

  const TomProtectedCopy({required this.placed, required this.clearAfter});
}

/// Copies protected values and clears them again.
///
/// Every copy of a protected value goes through this — never through the
/// platform clipboard directly. A copy that bypassed it would stay on the
/// clipboard until something else replaced it.
class TomProtectedClipboard {
  /// The default delay.
  static const _defaultClearAfter = Duration(seconds: 30);

  final TomClipboardPort port;
  final Duration Function() _clearAfter;
  final TomTimerFactory _timer;

  Timer? _pending;
  TomClipboardReceipt? _held;
  final StreamController<TomProtectedClipboardState> _states =
      StreamController<TomProtectedClipboardState>.broadcast(sync: true);
  TomProtectedClipboardState _state =
      const TomProtectedClipboardState.cleared();

  /// [clearAfter] is asked on every copy, so an application can bind it to a
  /// setting the user may change.
  TomProtectedClipboard({
    required this.port,
    Duration Function()? clearAfter,
    TomTimerFactory? timer,
  })  : _clearAfter = clearAfter ?? (() => _defaultClearAfter),
        _timer = timer ?? Timer.new;

  /// Whether a copied value is still waiting to be cleared.
  @visibleForTesting
  bool get isArmed => _pending != null;

  /// The current state — armed with its delay, or cleared.
  TomProtectedClipboardState get state => _state;

  /// Every change of [state], synchronously as it happens: the copy that
  /// arms, the clear that runs, the supersession, the disposal.
  Stream<TomProtectedClipboardState> get states => _states.stream;

  /// Places [value] and arms the clear.
  Future<TomProtectedCopy> copy(String value) async {
    final delay = _clearAfter();
    _disarm();
    final receipt = await port.placeConcealed(value);
    if (receipt == null) {
      return TomProtectedCopy(placed: false, clearAfter: delay);
    }
    _held = receipt;
    _pending = _timer(delay, () => unawaited(_expire(receipt)));
    _emit(TomProtectedClipboardState.armed(delay));
    return TomProtectedCopy(placed: true, clearAfter: delay);
  }

  /// Clears now what the last copy placed, if the clipboard still holds it —
  /// for a lock, a sign-out or the app closing. True when it cleared.
  Future<bool> clearNow() async {
    final held = _held;
    _disarm();
    if (held == null) return false;
    return port.clearIfHolding(held);
  }

  /// Drops the pending clear without running it, and closes [states].
  void dispose() {
    _disarm();
    unawaited(_states.close());
  }

  Future<void> _expire(TomClipboardReceipt receipt) async {
    // A later copy replaced this one; its own timer owns the clipboard now.
    if (!identical(_held, receipt)) return;
    _pending = null;
    _held = null;
    _emit(const TomProtectedClipboardState.cleared());
    await port.clearIfHolding(receipt);
  }

  void _disarm() {
    _pending?.cancel();
    _pending = null;
    _held = null;
    _emit(const TomProtectedClipboardState.cleared());
  }

  void _emit(TomProtectedClipboardState next) {
    if (next.armed == _state.armed && next.clearAfter == _state.clearAfter) {
      return;
    }
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }
}
