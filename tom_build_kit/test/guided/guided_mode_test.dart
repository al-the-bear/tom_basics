/// Unit tests for [GuidedMode] driven by a [ScriptedPromptDriver].
///
/// These tests exercise the *flow logic* of guided mode (menu → choice,
/// multi-select toggling, confirmation, validated input) without touching a
/// real terminal, by injecting a scripted driver that replays pre-seeded
/// answers.
///
/// Test IDs: BK-GUIDE-1 through BK-GUIDE-12
@TestOn('!browser')
library;

import 'package:tom_build_kit/src/guided/guided_mode.dart';
import 'package:tom_build_kit/src/guided/prompt_driver.dart';
import 'package:test/test.dart';

void main() {
  group('GuidedMode.menu', () {
    test(
        'BK-GUIDE-1: returns zero-based index of the chosen option '
        '[2026-07-05]', () {
      // Answer "2" → 1-based index 2 → "Blue" → returned index 1.
      final mode = GuidedMode(driver: ScriptedPromptDriver(['2']));
      final index = mode.menu('Pick a colour', ['Red', 'Blue', 'Green']);
      expect(index, 1);
    });

    test('BK-GUIDE-2: returns -1 when Cancel is selected [2026-07-05]', () {
      // Options become [Red, Blue, Green, Cancel]; answer "4" picks Cancel.
      final mode = GuidedMode(driver: ScriptedPromptDriver(['4']));
      final index = mode.menu('Pick a colour', ['Red', 'Blue', 'Green']);
      expect(index, -1);
    });

    test(
        'BK-GUIDE-3: with showCancel=false there is no Cancel row '
        '[2026-07-05]', () {
      final mode = GuidedMode(driver: ScriptedPromptDriver(['3']));
      final index = mode.menu(
        'Pick a colour',
        ['Red', 'Blue', 'Green'],
        showCancel: false,
      );
      expect(index, 2);
    });
  });

  group('GuidedMode.multiSelect', () {
    test(
        'BK-GUIDE-4: toggles two items then Done returns sorted indices '
        '[2026-07-05]', () {
      // Display rows: [item0, item1, item2, "── Done ──", "── Cancel ──"].
      // Toggle item2 (answer "3"), toggle item0 (answer "1"), then Done ("4").
      final mode = GuidedMode(
        driver: ScriptedPromptDriver(['3', '1', '4']),
      );
      final selected = mode.multiSelect(
        'Pick items',
        ['A', 'B', 'C'],
        showInstructions: false,
      );
      expect(selected, [0, 2]);
    });

    test(
        'BK-GUIDE-5: toggling the same item twice deselects it [2026-07-05]',
        () {
      // Toggle item1 on ("2"), toggle item1 off ("2"), then Done ("4").
      final mode = GuidedMode(
        driver: ScriptedPromptDriver(['2', '2', '4']),
      );
      final selected = mode.multiSelect(
        'Pick items',
        ['A', 'B', 'C'],
        showInstructions: false,
      );
      expect(selected, isEmpty);
    });

    test('BK-GUIDE-6: Cancel returns an empty list [2026-07-05]', () {
      // Cancel row is index 5 (1-based) for three items + Done + Cancel.
      final mode = GuidedMode(driver: ScriptedPromptDriver(['5']));
      final selected = mode.multiSelect(
        'Pick items',
        ['A', 'B', 'C'],
        showInstructions: false,
      );
      expect(selected, isEmpty);
    });

    test(
        'BK-GUIDE-7: honours defaults and returns them on immediate Done '
        '[2026-07-05]', () {
      // Defaults preselect item0 and item2; answer Done ("4") right away.
      final mode = GuidedMode(driver: ScriptedPromptDriver(['4']));
      final selected = mode.multiSelect(
        'Pick items',
        ['A', 'B', 'C'],
        defaults: [true, false, true],
        showInstructions: false,
      );
      expect(selected, [0, 2]);
    });
  });

  group('GuidedMode.confirm', () {
    test('BK-GUIDE-8: "y" yields true [2026-07-05]', () {
      final mode = GuidedMode(driver: ScriptedPromptDriver(['y']));
      expect(mode.confirm('Proceed?'), isTrue);
    });

    test('BK-GUIDE-9: "n" yields false [2026-07-05]', () {
      final mode = GuidedMode(driver: ScriptedPromptDriver(['n']));
      expect(mode.confirm('Proceed?'), isFalse);
    });

    test('BK-GUIDE-10: empty answer falls back to the default [2026-07-05]', () {
      final mode = GuidedMode(driver: ScriptedPromptDriver(['']));
      expect(mode.confirm('Proceed?', defaultYes: false), isFalse);
    });
  });

  group('GuidedMode.input', () {
    test('BK-GUIDE-11: returns the typed value verbatim [2026-07-05]', () {
      final mode = GuidedMode(driver: ScriptedPromptDriver(['hello']));
      expect(mode.input('Name?'), 'hello');
    });

    test(
        'BK-GUIDE-12: re-prompts until the validator accepts the input '
        '[2026-07-05]', () {
      // First answer fails the validator, second passes.
      final mode = GuidedMode(
        driver: ScriptedPromptDriver(['bad', 'good']),
      );
      final result = mode.input(
        'Name?',
        validator: (value) => value == 'good',
        validationError: 'nope',
      );
      expect(result, 'good');
    });
  });

  group('ScriptedPromptDriver', () {
    test(
        'BK-GUIDE-13: throws when it runs out of scripted answers '
        '[2026-07-05]', () {
      final mode = GuidedMode(driver: ScriptedPromptDriver([]));
      expect(() => mode.confirm('Proceed?'), throwsStateError);
    });
  });
}
