# Changelog

## 0.2.0

- `undoAsync` and `redoAsync` are serialised: one started while another is
  still applying waits for it, so two overlapping undos apply two entries,
  each once, newest first. `isApplying` says whether one is running.
- A synchronous `undo` or `redo` started while an asynchronous one applies
  throws `StateError` instead of applying the same entry a second time.
- An entry removed (by `clear`) while it is being applied is not put back
  onto the other stack.

## 0.1.0

- `TomUndoStack<E>`: bounded, a push clears redo, and an entry is applied
  first and moved second, so a failed undo leaves the history as it was;
  synchronous and asynchronous application, and `popNewest` for merging an
  act into the one before it. `tomApplyAll` and `tomApplyAllAsync` apply a
  composite step atomically, putting back what they applied when an item
  throws. Taken out of `tom_forge_core` (where it was `ForgeUndoStack`,
  `forgeApplyAll`, `forgeApplyAllAsync`) before its first release.
