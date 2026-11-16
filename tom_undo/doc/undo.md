# Tom Undo System

The Tom Undo System is one bounded undo/redo stack, `TomUndoStack<E>`, and two
helpers for composite steps, `tomApplyAll` and `tomApplyAllAsync`. It is plain
Dart with no dependency, so any package — a Flutter widget library, a document
model, a browser build — can take it.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Core Components](#core-components)
  - [TomUndoStack](#tomundostack)
  - [tomApplyAll and tomApplyAllAsync](#tomapplyall-and-tomapplyallasync)
- [Undo and Redo](#undo-and-redo)
- [Asynchronous Undo and Redo](#asynchronous-undo-and-redo)
- [Bounding and Merging](#bounding-and-merging)
- [Composite Steps](#composite-steps)
- [Error Handling](#error-handling)
- [Best Practices](#best-practices)

## Overview

| Type | Kind | Purpose |
| ---- | ---- | ------- |
| `TomUndoStack<E>` | class | A bounded undo/redo stack of entries of type `E` |
| `tomApplyAll` | function | Applies a list of steps; on a failure puts back the ones already applied, then rethrows |
| `tomApplyAllAsync` | function | `tomApplyAll` for steps that complete asynchronously |

The stack does not know what an entry is. It holds whatever the history needs —
a command object with its own undo and redo, a recorded transaction, or a
before/after snapshot — and the caller says what *applying* an entry means on
each call. That is why a synchronous history and an asynchronous one can share
the same stack type.

Three rules are the stack's own, so nobody built on it has to remember them:

- **Applied first, moved second.** An entry moves between the undo and the redo
  stack only after its application succeeded. An application that throws
  leaves the entry where it was, so the act is still undoable (or redoable),
  and the error reaches the caller.
- **Bounded, newest kept.** A push clears the redo stack — an edit after an
  undo makes the undone future unreachable — and drops the oldest entries
  beyond `maxEntries`.
- **One asynchronous move at a time.** Asynchronous undos and redos wait for
  the one in flight before choosing their entry, so two presses of Undo while
  an application is still running undo two entries, never one entry twice.

## Quick Start

```dart
import 'package:tom_undo/tom_undo.dart';

void main() {
  final history = TomUndoStack<String>(maxEntries: 50);
  history.push('typed "hello"');
  history.undo((entry) => print('undo $entry')); // undo typed "hello"
  history.redo((entry) => print('redo $entry')); // redo typed "hello"
}
```

## Core Components

### TomUndoStack

`TomUndoStack<E>({int maxEntries = 100})` creates an empty stack. `maxEntries`
must be at least 1.

| Member | What it does |
| ------ | ------------ |
| `push(entry)` | Adds `entry` as the newest undoable act, clears the redo stack and drops the oldest entries beyond `maxEntries`. |
| `undo([apply])` | Applies `apply` to the newest undoable entry, then moves it to the redo stack. Returns the entry, or null when there is nothing to undo. |
| `redo([apply])` | Applies `apply` to the newest undone entry, then moves it back to the undo stack. Returns the entry, or null. |
| `undoAsync(apply)` | `undo` for an application that completes later; returns a `Future` of the entry or null. |
| `redoAsync(apply)` | `redo` for an application that completes later. |
| `popNewest()` | Removes the newest undoable entry without undoing it and returns it, or null. |
| `clear()` | Empties both stacks. |
| `maxEntries` | The bound; settable on an open stack. |
| `canUndo` / `canRedo` | Whether there is an entry to undo / redo. |
| `undoCount` / `redoCount` | How many entries each stack holds. |
| `nextUndo` / `nextRedo` | The entry `undo` / `redo` would apply, or null. |
| `undoEntries` | The undoable entries, oldest first, as an unmodifiable list. |
| `isApplying` | Whether an asynchronous undo or redo is still applying its entry. |

### tomApplyAll and tomApplyAllAsync

`tomApplyAll(items, apply, putBack)` applies every item in order. If one
application throws, it calls `putBack` on the items already applied, newest
first, and rethrows. `tomApplyAllAsync` has the same shape with functions that
return a `Future`.

## Undo and Redo

`undo` and `redo` take the application as an optional argument:

```dart
final history = TomUndoStack<int>();
var value = 0;

history.push(5); // the caller already added 5
value += 5;

history.undo((delta) => value -= delta);
print(value); // 0
history.redo((delta) => value += delta);
print(value); // 5
```

Without an argument the entry only moves, and the call returns it — for a
history whose caller applies the entry it is handed back:

```dart
final entry = history.undo(); // moved to the redo stack, nothing applied
if (entry != null) value -= entry;
```

A push after an undo clears the redo stack:

```dart
history.undo((delta) => value -= delta);
history.push(2);
print(history.canRedo); // false
```

## Asynchronous Undo and Redo

`undoAsync` and `redoAsync` take an application that returns a `Future`. The
entry moves once that `Future` completes:

```dart
final history = TomUndoStack<String>()
  ..push('first')
  ..push('second');

Future<void> revert(String entry) async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
  print('reverted $entry');
}

// Two presses of Undo while the first is still running:
await Future.wait([history.undoAsync(revert), history.undoAsync(revert)]);
// reverted second
// reverted first
```

The second call waits for the first, then takes the entry that is newest at
that point. Behaviour around a running application:

- **A synchronous `undo` or `redo`** while one is applying throws a
  `StateError`; `isApplying` tells you in advance.
- **A push while an entry applies** does not disturb it: the entry moves by
  identity, not by position, once its application completes.
- **An entry that left the stack while it was applied** — removed by `clear`, or
  dropped beyond `maxEntries` — is not put back onto either stack.

## Bounding and Merging

`maxEntries` bounds the undo stack. Setting it lower on an open stack takes
effect at once: the oldest undoable entries are dropped, and the redo stack is
trimmed the same way from its far end. Setting it to 0 or less throws an
`ArgumentError`.

```dart
final history = TomUndoStack<String>(maxEntries: 3);
for (final word in ['a', 'b', 'c', 'd']) {
  history.push(word);
}
print(history.undoEntries); // [b, c, d]

history.maxEntries = 2;
print(history.undoEntries); // [c, d]
```

`popNewest` lets a history merge an act into the one before it, such as a burst
of typing recorded as one entry: take the newest back, then push the merged one.

```dart
final history = TomUndoStack<String>()..push('hel');
final previous = history.popNewest(); // 'hel'
history.push('${previous ?? ''}lo');
print(history.nextUndo); // hello
```

## Composite Steps

A grouped undo applies several steps as one. `tomApplyAll` makes the group
atomic: a group of N whose k-th application fails is put back as it was rather
than left half applied, so it can be tried again as a whole.

```dart
final applied = <String>[];
try {
  tomApplyAll<String>(
    ['rename', 'move', 'delete'],
    (step) {
      if (step == 'delete') throw StateError('read-only');
      applied.add(step);
    },
    (step) => applied.remove(step), // the inverse of the application
  );
} on StateError catch (e) {
  print('$e; applied: $applied'); // Bad state: read-only; applied: []
}
```

`putBack` must be the inverse of `apply`. It runs on the applied items newest
first.

## Error Handling

| Situation | What happens |
| --------- | ------------ |
| The application passed to `undo` / `redo` throws | The exception propagates; both stacks stay as they were. |
| The `Future` of `undoAsync` / `redoAsync` completes with an error | The returned `Future` completes with that error; the entry stays where it was, and the next asynchronous call proceeds. |
| `undo` / `redo` while an asynchronous one is applying | `StateError` ("an asynchronous undo or redo is still applying its entry"). |
| `maxEntries` set to 0 or less | `ArgumentError`. The constructor asserts the same in debug mode. |
| Nothing to undo or redo | `undo`, `redo`, `undoAsync`, `redoAsync` and `popNewest` return null. |
| A step of `tomApplyAll` throws | The applied steps are put back, newest first, and the original exception is rethrown. An exception thrown by `putBack` itself propagates instead. |

## Best Practices

- **Keep one stack per history** and build on `TomUndoStack` rather than on a
  hand-written list; `_bin/check_undo_stacks.py` at the workspace root finds
  hand-rolled ones.
- **Let the error reach the user.** A failing undo leaves the entry undoable; the
  caller is the one place that can say what happened.
- **Use `undoAsync` / `redoAsync` for anything that awaits**, such as a write to
  disk, rather than calling the synchronous form and ignoring the `Future`.
- **Make `putBack` the exact inverse of `apply`** when grouping steps with
  `tomApplyAll`.
