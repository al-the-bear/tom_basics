/// The undo/redo stack every undo history in the workspace runs on:
/// [TomUndoStack], with [tomApplyAll] and [tomApplyAllAsync] for composite
/// steps. Plain Dart with no dependency, so any package — a Flutter widget
/// library, a document model, a browser build — can take it.
library;

export 'src/undo_stack.dart';
