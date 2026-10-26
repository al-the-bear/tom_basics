import 'package:tom_undo/tom_undo.dart';

void main() {
  final history = TomUndoStack<String>(maxEntries: 50);
  history.push('typed "hello"');
  history.undo((entry) => print('undo $entry')); // applied, then moved to redo
  history.redo((entry) => print('redo $entry'));
}
