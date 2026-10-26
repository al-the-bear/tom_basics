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
///
/// The stack holds whatever the history needs — a command with its own undo
/// and redo, a recorded transaction, or a before/after snapshot the caller
/// applies itself. What applying means is handed in per call, so a
/// synchronous history and an asynchronous one share the same stack.
library;

/// A bounded undo/redo stack of [E].
class TomUndoStack<E> {
  TomUndoStack({this.maxEntries = 100})
    : assert(maxEntries > 0, 'a stack must keep at least one entry');

  /// How many entries the undo stack keeps; the oldest beyond it are dropped.
  final int maxEntries;

  final List<E> _undo = [];
  final List<E> _redo = [];

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
    while (_undo.length > maxEntries) {
      _undo.removeAt(0);
    }
  }

  /// Applies [apply] to the newest entry and then moves it to the redo stack.
  ///
  /// Returns the entry, or null when there is nothing to undo. Without
  /// [apply] the entry only moves — for a history whose caller applies the
  /// entry it is handed back. A throw from [apply] leaves both stacks as they
  /// were.
  E? undo([void Function(E entry)? apply]) {
    final entry = nextUndo;
    if (entry == null) return null;
    apply?.call(entry);
    _move(entry, from: _undo, to: _redo);
    return entry;
  }

  /// Applies [apply] to the newest undone entry and then moves it back to the
  /// undo stack. As [undo], in the other direction.
  E? redo([void Function(E entry)? apply]) {
    final entry = nextRedo;
    if (entry == null) return null;
    apply?.call(entry);
    _move(entry, from: _redo, to: _undo);
    return entry;
  }

  /// [undo] for an application that completes asynchronously.
  ///
  /// The entry moves once [apply] has completed. If something pushed while it
  /// ran, the entry still moves — by identity, not by position — and the push
  /// has already cleared the redo stack it lands on beside.
  Future<E?> undoAsync(Future<void> Function(E entry) apply) async {
    final entry = nextUndo;
    if (entry == null) return null;
    await apply(entry);
    _move(entry, from: _undo, to: _redo);
    return entry;
  }

  /// [redo] for an application that completes asynchronously.
  Future<E?> redoAsync(Future<void> Function(E entry) apply) async {
    final entry = nextRedo;
    if (entry == null) return null;
    await apply(entry);
    _move(entry, from: _redo, to: _undo);
    return entry;
  }

  /// Empties both stacks.
  void clear() {
    _undo.clear();
    _redo.clear();
  }

  void _move(E entry, {required List<E> from, required List<E> to}) {
    final at = from.lastIndexWhere((e) => identical(e, entry));
    if (at >= 0) from.removeAt(at);
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
