# Tom Undo

Published on pub.dev as [`tom_undo` 0.3.0](https://pub.dev/packages/tom_undo).

> Tom Undo is part of the **Tom framework** by al-the-bear.
> Distributed under the terms in this package's license — see
> [LICENSE](LICENSE).

The undo/redo stack every undo history runs on: a bounded stack that applies an
entry before moving it, so a failing undo stays undoable, and composite steps
that put back what they applied when one part fails. No dependencies.

---

## Overview

`tom_undo` provides one undo/redo stack, `TomUndoStack<E>`, that every undo
history in the workspace runs on — Tom Forge's `DefaultUndoManager`, the text,
Markdown, YAML and Dart editors, the file tabs' `ForgeFileSession`, and Tom
Flutter UI's `TomUndoHistory`. It is plain Dart with no dependency, so it
reaches no `dart:io` and no Flutter, and a widget library, a document model or a
browser build can all take it.

The stack holds whatever the history needs — a command with its own undo and
redo, a recorded transaction, or a before/after snapshot. What *applying* an
entry means is handed in per call, so a synchronous history and an asynchronous
one share the same stack.

Forge's undo contract (`ForgeUndoManager`) and its default implementation stay
in `tom_forge_core`, built on this stack.

---

## Installation

```yaml
dependencies:
  tom_undo: ^0.3.0
```

or

```bash
dart pub add tom_undo
```

A package inside this workspace may name it by path instead, e.g. from a
package two folder levels below the workspace root:

```yaml
dependencies:
  tom_undo:
    path: ../../tom_ai/basics/tom_undo
```

**SDK requirement:** Dart `^3.10.8`. **Runtime dependencies:** none.

```dart
import 'package:tom_undo/tom_undo.dart';
```

---

## Features

| Feature | What it does |
| ------- | ------------ |
| **Applied first, moved second** | `undo` and `redo` apply an entry and only then move it between the stacks, so an application that throws leaves the entry where it was and the error reaches the caller. |
| **Asynchronous application, one at a time** | `undoAsync` and `redoAsync` do the same for an application that completes later. A second one started while the first applies waits for it, so two quick undos take back two entries rather than one twice. While one applies (`isApplying`), a synchronous `undo` or `redo` is refused with a `StateError`. |
| **Bounded** | A `push` clears the redo stack and drops the oldest entries beyond `maxEntries`, which can be changed on an open stack. |
| **Merging** | `popNewest` takes the newest entry back without undoing it, so a history can merge a burst of typing into one act. |
| **Atomic composite steps** | `tomApplyAll` (and `tomApplyAllAsync`) apply a list of steps in order and, when one throws, put back the ones already applied, newest first, before rethrowing. |

---

## Quick start

```dart
import 'package:tom_undo/tom_undo.dart';

void main() {
  final history = TomUndoStack<String>(maxEntries: 50);
  history.push('typed "hello"');
  history.undo((entry) => print('undo $entry')); // undo typed "hello"
  history.redo((entry) => print('redo $entry')); // redo typed "hello"
}
```

The same program is [`example/tom_undo_example.dart`](example/tom_undo_example.dart):

```bash
dart run example/tom_undo_example.dart
```

---

## One stack, kept one

`_bin/check_undo_stacks.py` at the workspace root finds an undo or redo history
written by hand anywhere else — a field or local named like `_undo` or
`_redoStack` that starts as an empty list or queue — and its fix is this
package, not a rename:

```bash
./_bin/check_undo_stacks.py --strict   # exit 1 on a hand-rolled stack
python3 _bin/test_check_undo_stacks.py # the check's own tests
```

It is started by hand, like every check in the workspace.

---

## Documentation

| Document | What it covers |
| -------- | -------------- |
| [`doc/undo.md`](doc/undo.md) | The user guide — the stack's rules, every operation with examples, asynchronous undo, composite steps, errors and limits. |
| [`example/`](example/) | The runnable quick start. |
| [`CHANGELOG.md`](CHANGELOG.md) | What changed in each version. |

---

## Status

- **Version:** 0.3.0, published on pub.dev.
- **SDK:** Dart `^3.10.8`; no runtime dependencies.
- **Tests:** a pure-Dart suite under `test/`, run with `testkit :test` (or
  `dart test`); it needs no network and no platform features.

---

## License

BSD-3-Clause — see [LICENSE](LICENSE) for details.
