# tom_undo

Published on pub.dev as [`tom_undo` 0.1.0](https://pub.dev/packages/tom_undo).

One undo/redo stack, `TomUndoStack<E>`, that every undo history in the
workspace runs on — Tom Forge's `DefaultUndoManager`, the text, Markdown, YAML
and Dart editors, the file tabs' `ForgeFileSession`, and `tom_flutter_ui`'s
`TomUndoHistory`. Plain Dart with no dependency, so it reaches no `dart:io`
and no Flutter.

```yaml
dependencies:
  tom_undo:
    path: ../../tom_ai/basics/tom_undo
```

- **Applied first, moved second.** `undo` and `redo` apply an entry and only
  then move it between the stacks, so an application that throws leaves the
  entry where it was and the error reaches the caller. `undoAsync` and
  `redoAsync` do the same for an application that completes later.
- **Bounded.** A push clears the redo stack and drops the oldest entries
  beyond `maxEntries`; `popNewest` takes the newest entry back so a history can
  merge a burst of typing into one act.
- **Atomic composite steps.** `tomApplyAll` (and `tomApplyAllAsync`) apply a
  list of steps in order and, when one throws, put back the ones already
  applied, newest first, before rethrowing.

```dart
import 'package:tom_undo/tom_undo.dart';

void main() {
  final history = TomUndoStack<String>(maxEntries: 50);
  history.push('typed "hello"');
  history.undo((entry) => print('undo $entry')); // applied, then moved to redo
  history.redo((entry) => print('redo $entry'));
}
```

Forge's undo contract (`ForgeUndoManager`) and its default implementation stay
in `tom_forge_core`, built on this stack.

## One stack, kept one

`_bin/check_undo_stacks.py` at the workspace root finds an undo or redo
history written by hand anywhere else — a field or local named like `_undo` or
`_redoStack` that starts as an empty list or queue — and its fix is this
package, not a rename:

```bash
./_bin/check_undo_stacks.py --strict   # exit 1 on a hand-rolled stack
python3 _bin/test_check_undo_stacks.py # the check's own tests
```

It is started by hand, like every check in the workspace.

## License

BSD-3-Clause — See [LICENSE](LICENSE) for details.
