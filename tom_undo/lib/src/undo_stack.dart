/// The undo/redo stack every undo history in the workspace runs on.
///
/// Two rules are this class's, and nobody built on it has to remember them:
///
/// * **Applied first, moved second.** [undo] and [redo] apply an entry and only
///   then move it between the stacks, so an application that throws leaves the
///   entry where it was — the act is still undoable (or redoable), and the
///   error reaches the caller, the one place that can say what happened.
/// * **Bounded, newest kept.** [push] clears the redo stack, because an edit
///   after an undo makes the undone future unreachable, and drops the oldest
///   entries beyond [maxEntries].
/// * **One asynchronous move at a time.** [undoAsync] and [redoAsync] wait for
///   the one in flight before choosing their entry, so two presses of Undo
///   while an application is still running undo two entries, never one entry
///   twice; a synchronous [undo] or [redo] meanwhile is refused.
///
/// The stack holds whatever the history needs — a command with its own undo
/// and redo, a recorded transaction, or a before/after snapshot the caller
/// applies itself. What applying means is handed in per call, so a
/// synchronous history and an asynchronous one share the same stack.
library;

/// A bounded undo/redo stack of [E].
class TomUndoStack<E> {
  TomUndoStack({int maxEntries = 100})
    : assert(maxEntries > 0, 'a stack must keep at least one entry'),
      _maxEntries = maxEntries;

  int _maxEntries;

  /// How many entries the undo stack keeps; the oldest beyond it are dropped.
  int get maxEntries => _maxEntries;

  /// Sets the bound. A lower bound drops the oldest undoable entries at once;
  /// the redo stack, which only an undo fills, is never longer than the undo
  /// stack was, and is trimmed the same way from its far end.
  set maxEntries(int value) {
    if (value <= 0) {
      throw ArgumentError.value(value, 'maxEntries', 'must be at least 1');
    }
    _maxEntries = value;
    while (_undo.length > value) {
      _undo.removeAt(0);
    }
    while (_redo.length > value) {
      _redo.removeAt(0);
    }
  }

  final List<E> _undo = [];
  final List<E> _redo = [];

  /// The asynchronous undo or redo in flight, if any.
  Future<void>? _inFlight;

  /// Whether an asynchronous undo or redo is still applying its entry.
  bool get isApplying => _inFlight != null;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoCount => _undo.length;
  int get redoCount => _redo.length;

  /// The entry [undo] would apply, or null when there is none.
  E? get nextUndo => _undo.isEmpty ? null : _undo.last;

  /// The entry [redo] would apply, or null when there is none.
  E? get nextRedo => _redo.isEmpty ? null : _redo.last;

  /// The undoable entries, oldest first.
  List<E> get undoEntries => List.unmodifiable(_undo);

  /// Removes the newest undoable entry without undoing it, and returns it —
  /// or null when there is none.
  ///
  /// For a history that merges an act into the one before it (a burst of
  /// typing as one entry): take the newest back, then [push] the merged one.
  E? popNewest() => _undo.isEmpty ? null : _undo.removeLast();

  /// Adds [entry] as the newest undoable act, clearing the redo stack.
  void push(E entry) {
    _undo.add(entry);
    _redo.clear();
    while (_undo.length > _maxEntries) {
      _undo.removeAt(0);
    }
  }

  /// Applies [apply] to the newest entry and then moves it to the redo stack.
  ///
  /// Returns the entry, or null when there is nothing to undo. Without
  /// [apply] the entry only moves — for a history whose caller applies the
  /// entry it is handed back. A throw from [apply] leaves both stacks as they
  /// were.
  ///
  /// Throws a [StateError] while an asynchronous undo or redo is in flight.
  E? undo([void Function(E entry)? apply]) {
    _refuseWhileApplying();
    final entry = nextUndo;
    if (entry == null) return null;
    apply?.call(entry);
    _move(entry, from: _undo, to: _redo);
    return entry;
  }

  /// Applies [apply] to the newest undone entry and then moves it back to the
  /// undo stack. As [undo], in the other direction.
  E? redo([void Function(E entry)? apply]) {
    _refuseWhileApplying();
    final entry = nextRedo;
    if (entry == null) return null;
    apply?.call(entry);
    _move(entry, from: _redo, to: _undo);
    return entry;
  }

  /// [undo] for an application that completes asynchronously.
  ///
  /// Waits for an undo or redo already in flight, then takes the newest entry
  /// and moves it once [apply] has completed. If something pushed while it
  /// ran, the entry still moves — by identity, not by position — and the push
  /// has already cleared the redo stack it lands on beside. An entry that left
  /// the stack while it was applied ([clear], or dropped beyond [maxEntries])
  /// is not put back anywhere.
  Future<E?> undoAsync(Future<void> Function(E entry) apply) =>
      _serialised(() async {
        final entry = nextUndo;
        if (entry == null) return null;
        await apply(entry);
        _move(entry, from: _undo, to: _redo);
        return entry;
      });

  /// [redo] for an application that completes asynchronously.
  Future<E?> redoAsync(Future<void> Function(E entry) apply) =>
      _serialised(() async {
        final entry = nextRedo;
        if (entry == null) return null;
        await apply(entry);
        _move(entry, from: _redo, to: _undo);
        return entry;
      });

  Future<E?> _serialised(Future<E?> Function() step) async {
    for (var running = _inFlight; running != null; running = _inFlight) {
      await running;
    }
    final result = step();
    final done = result.then((_) {}, onError: (Object _) {});
    _inFlight = done;
    try {
      return await result;
    } finally {
      if (identical(_inFlight, done)) _inFlight = null;
    }
  }

  void _refuseWhileApplying() {
    if (_inFlight != null) {
      throw StateError(
        'an asynchronous undo or redo is still applying its entry',
      );
    }
  }

  /// Empties both stacks.
  void clear() {
    _undo.clear();
    _redo.clear();
  }

  /// Moves [entry] from [from] to [to]; an entry [from] no longer holds is
  /// not added to [to] — it left the history while it was being applied.
  void _move(E entry, {required List<E> from, required List<E> to}) {
    final at = from.lastIndexWhere((e) => identical(e, entry));
    if (at < 0) return;
    from.removeAt(at);
    to.add(entry);
  }
}

/// Applies every item of [items] in order with [apply]; if one throws, puts
/// back the ones already applied — newest first, with [putBack] — and
/// rethrows.
///
/// The composite step every grouped undo is made of: a step of N whose k-th
/// application fails is left as it was rather than half applied, so the step
/// can be tried again as a whole. [putBack] must be [apply]'s inverse.
void tomApplyAll<T>(
  Iterable<T> items,
  void Function(T item) apply,
  void Function(T item) putBack,
) {
  final applied = <T>[];
  for (final item in items) {
    try {
      apply(item);
    } catch (_) {
      for (final done in applied.reversed) {
        putBack(done);
      }
      rethrow;
    }
    applied.add(item);
  }
}

/// [tomApplyAll] for applications that complete asynchronously.
Future<void> tomApplyAllAsync<T>(
  Iterable<T> items,
  Future<void> Function(T item) apply,
  Future<void> Function(T item) putBack,
) async {
  final applied = <T>[];
  for (final item in items) {
    try {
      await apply(item);
    } catch (_) {
      for (final done in applied.reversed) {
        await putBack(done);
      }
      rethrow;
    }
    applied.add(item);
  }
}
