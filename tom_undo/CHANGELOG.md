# Changelog

## 0.1.0

- `TomUndoStack<E>`: bounded, a push clears redo, and an entry is applied
  first and moved second, so a failed undo leaves the history as it was;
  synchronous and asynchronous application, and `popNewest` for merging an
  act into the one before it. `tomApplyAll` and `tomApplyAllAsync` apply a
  composite step atomically, putting back what they applied when an item
  throws. Taken out of `tom_forge_core` (where it was `ForgeUndoStack`,
  `forgeApplyAll`, `forgeApplyAllAsync`) before its first release.
