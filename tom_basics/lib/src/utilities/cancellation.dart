/// Cooperative cancellation: a source that cancels, a token that is told.
///
/// The token is deliberately **not** the thing that cancels: work that could
/// cancel itself is work whose deadline is advisory. The source stays with
/// whatever imposed the stop; the token goes to the work, which checks
/// [TomCancellationToken.isCancelled] at its own safe points or races
/// [TomCancellationToken.whenCancelled] against what it is waiting for.
///
/// Cancellation is one-way and latching. Once cancelled, a token stays
/// cancelled and keeps the **first** reason, because the second cause of a
/// stop is not interesting and overwriting the first loses the one that
/// mattered. It is not a timer: compose a source with a `Timer` where a
/// deadline should cancel.
library;

import 'dart:async';

/// The read side of a cancellation.
abstract interface class TomCancellationToken {
  /// A token that is never cancelled — the right default for a caller with no
  /// deadline to impose, and cheaper than making every parameter nullable.
  static const TomCancellationToken none = _NeverCancelled();

  bool get isCancelled;

  /// The first reason given, or null while the token is live.
  String? get reason;

  /// Completes with the reason when cancellation happens. Never completes for
  /// [none].
  Future<String> get whenCancelled;
}

/// The write side of a cancellation.
final class TomCancellationSource {
  final _SourceToken _token = _SourceToken();

  /// The token to hand to the work being cancelled.
  TomCancellationToken get token => _token;

  bool get isCancelled => _token.isCancelled;

  /// Cancels. Idempotent, and the first [reason] wins.
  void cancel([String reason = 'cancelled']) => _token._cancel(reason);
}

/// Thrown by work that noticed its token was cancelled, naming what stopped.
final class TomOperationCancelled implements Exception {
  /// What was cancelled, when the thrower knows.
  final String? operation;

  /// Why, when the token said.
  final String? reason;

  const TomOperationCancelled([this.operation, this.reason]);

  @override
  String toString() {
    final what = operation == null ? '' : '($operation)';
    final why = reason == null ? '' : ': $reason';
    return 'TomOperationCancelled$what$why';
  }
}

final class _SourceToken implements TomCancellationToken {
  final Completer<String> _completer = Completer<String>();
  String? _reason;

  @override
  bool get isCancelled => _reason != null;

  @override
  String? get reason => _reason;

  @override
  Future<String> get whenCancelled => _completer.future;

  void _cancel(String reason) {
    if (_reason != null) return;
    _reason = reason;
    _completer.complete(reason);
  }
}

final class _NeverCancelled implements TomCancellationToken {
  const _NeverCancelled();

  @override
  bool get isCancelled => false;

  @override
  String? get reason => null;

  @override
  Future<String> get whenCancelled => _never;
}

// Cached so `TomCancellationToken.none` does not allocate per call.
final Future<String> _never = Completer<String>().future;
