/// The one undo/redo stack: applied first and moved second, bounded with the
/// newest kept, a push clearing redo, and composite steps that put back what
/// they applied when one item throws.
library;

import 'package:test/test.dart';
import 'package:tom_undo/tom_undo.dart';

void main() {
  group('UNDO-STACK the stack', () {
    test('UNDO-STACK-1: undo and redo move the entry after applying it, and '
        'hand it back', () {
      final stack = TomUndoStack<String>()
        ..push('a')
        ..push('b');
      final applied = <String>[];
      expect(stack.undo(applied.add), 'b');
      expect(applied, ['b']);
      expect((stack.undoCount, stack.redoCount), (1, 1));
      expect(stack.nextRedo, 'b');
      expect(stack.redo(applied.add), 'b');
      expect((stack.undoCount, stack.redoCount), (2, 0));
      expect(TomUndoStack<String>().undo(), isNull);
    });

    test('UNDO-STACK-2: an application that throws leaves both stacks as '
        'they were', () {
      final stack = TomUndoStack<String>()..push('a');
      expect(() => stack.undo((_) => throw StateError('no')), throwsStateError);
      expect((stack.undoCount, stack.redoCount), (1, 0));
      stack.undo();
      expect(() => stack.redo((_) => throw StateError('no')), throwsStateError);
      expect((stack.undoCount, stack.redoCount), (0, 1));
    });

    test('UNDO-STACK-3: a push clears redo and the oldest entries beyond the '
        'bound are dropped', () {
      final stack = TomUndoStack<int>(maxEntries: 2)
        ..push(1)
        ..push(2)
        ..push(3);
      expect(stack.undoCount, 2);
      stack.undo();
      stack.undo();
      expect(stack.undo(), isNull, reason: '1 was dropped');
      stack.redo();
      stack.push(4);
      expect(stack.canRedo, isFalse);
      expect(stack.nextUndo, 4);
    });

    test('UNDO-STACK-4: the async forms move only after the application '
        'completes, and not when it fails', () async {
      final stack = TomUndoStack<String>()..push('a');
      await expectLater(
        stack.undoAsync((_) async => throw StateError('no')),
        throwsStateError,
      );
      expect(stack.undoCount, 1);
      expect(await stack.undoAsync((_) async {}), 'a');
      expect(stack.redoCount, 1);
      expect(await stack.redoAsync((_) async {}), 'a');
      expect(stack.undoCount, 1);
    });

    test('UNDO-STACK-5: an entry pushed while an async undo runs stays; the '
        'undone one moves by identity', () async {
      final stack = TomUndoStack<String>()..push('a');
      final undone = await stack.undoAsync((_) async => stack.push('b'));
      expect(undone, 'a');
      expect(stack.nextUndo, 'b');
      expect(stack.nextRedo, 'a');
    });
  });

  group('UNDO-MERGE taking the newest entry back', () {
    test('UNDO-STACK-6: popNewest removes the newest entry without moving it '
        'to redo, and the entries are listed oldest first', () {
      final stack = TomUndoStack<String>()
        ..push('a')
        ..push('b');
      expect(stack.undoEntries, ['a', 'b']);
      expect(stack.popNewest(), 'b');
      expect(stack.canRedo, isFalse);
      stack.push('b+');
      expect(stack.undoEntries, ['a', 'b+']);
      expect(TomUndoStack<String>().popNewest(), isNull);
    });
  });

  group('UNDO-APPLY composite steps', () {
    test('UNDO-APPLY-1: every item is applied in order', () {
      final log = <String>[];
      tomApplyAll(
        [1, 2, 3],
        (i) => log.add('do $i'),
        (i) => log.add('undo $i'),
      );
      expect(log, ['do 1', 'do 2', 'do 3']);
    });

    test('UNDO-APPLY-2: a throw puts back what was applied, newest first, and '
        'rethrows', () {
      final log = <String>[];
      expect(
        () => tomApplyAll([1, 2, 3], (i) {
          if (i == 3) throw StateError('three');
          log.add('do $i');
        }, (i) => log.add('undo $i')),
        throwsStateError,
      );
      expect(log, ['do 1', 'do 2', 'undo 2', 'undo 1']);
    });

    test('UNDO-APPLY-3: the async form does the same', () async {
      final log = <String>[];
      await expectLater(
        tomApplyAllAsync([1, 2], (i) async {
          if (i == 2) throw StateError('two');
          log.add('do $i');
        }, (i) async => log.add('undo $i')),
        throwsStateError,
      );
      expect(log, ['do 1', 'undo 1']);
    });
  });
}
