/// Unit tests for [ProjectGroupPicker] and [pickProjectScopes] driven by a
/// [ScriptedPromptDriver].
///
/// These exercise the *selection logic* (scope choice, per-project multi-select,
/// scope multi-select, cancellation) without touching a real terminal, by
/// injecting a scripted driver that replays pre-seeded answers. Before the
/// PromptDriver migration this logic called `dcli` directly and was untestable.
///
/// Test IDs: BK-PGP-1 through BK-PGP-7
@TestOn('!browser')
library;

import 'package:tom_build_kit/src/guided/project_group_picker.dart';
import 'package:tom_build_kit/src/guided/prompt_driver.dart';
import 'package:test/test.dart';

void main() {
  const root = '/ws';
  const projA = '/ws/proj_a';
  const projB = '/ws/proj_b';

  group('ProjectGroupPicker.pick', () {
    test('BK-PGP-1: cancelling the top-level menu returns null [2026-07-06]',
        () {
      // scopeOptions = [complete, per-scope, specific, Cancel]; "4" → Cancel.
      final picker = ProjectGroupPicker(
        workspaceRoot: root,
        changedProjects: const [projA, projB],
        driver: ScriptedPromptDriver(['4']),
      );
      expect(picker.pick(), isNull);
    });

    test(
        'BK-PGP-2: "all changed projects (complete)" selects every changed '
        'project with complete scope [2026-07-06]', () {
      // "1" → first option (all changed, complete). No further prompts.
      final picker = ProjectGroupPicker(
        workspaceRoot: root,
        changedProjects: const [projA, projB],
        driver: ScriptedPromptDriver(['1']),
      );

      final selection = picker.pick();
      expect(selection, isNotNull);
      expect(selection!.projects, [projA, projB]);
      expect(selection.scopes[projA], [ProjectScope.complete]);
      expect(selection.scopes[projB], [ProjectScope.complete]);
    });

    test(
        'BK-PGP-3: "select specific projects" + common complete scope keeps '
        'all defaults [2026-07-06]', () {
      // top "3" → specific; project multi-select "3" (Done, both still checked);
      // confirm "n" (common scope, not per-project); scope multi-select "5"
      // (Done, only Complete checked).
      final picker = ProjectGroupPicker(
        workspaceRoot: root,
        changedProjects: const [projA, projB],
        driver: ScriptedPromptDriver(['3', '3', 'n', '5']),
      );

      final selection = picker.pick();
      expect(selection, isNotNull);
      expect(selection!.projects, [projA, projB]);
      expect(selection.scopes[projA], [ProjectScope.complete]);
      expect(selection.scopes[projB], [ProjectScope.complete]);
    });

    test(
        'BK-PGP-4: "select specific projects" with no changed projects returns '
        'null [2026-07-06]', () {
      final picker = ProjectGroupPicker(
        workspaceRoot: root,
        changedProjects: const [],
        driver: ScriptedPromptDriver(['3']),
      );
      expect(picker.pick(), isNull);
    });

    test(
        'BK-PGP-5: deselecting a project in the multi-select drops it from the '
        'result [2026-07-06]', () {
      // top "3"; project multi-select "1" toggles proj_a OFF, then "3" (Done)
      // → only proj_b remains; confirm "n"; scope multi-select "5" (Done).
      final picker = ProjectGroupPicker(
        workspaceRoot: root,
        changedProjects: const [projA, projB],
        driver: ScriptedPromptDriver(['3', '1', '3', 'n', '5']),
      );

      final selection = picker.pick();
      expect(selection, isNotNull);
      expect(selection!.projects, [projB]);
      expect(selection.scopes[projB], [ProjectScope.complete]);
    });
  });

  group('pickProjectScopes', () {
    test(
        'BK-PGP-6: multi-select accepts the default Complete scope '
        '[2026-07-06]', () {
      // options = [Complete, Code, Examples, Tests] (+Done); "5" → Done with
      // only Complete checked by default.
      final scopes = pickProjectScopes(
        driver: ScriptedPromptDriver(['5']),
      );
      expect(scopes, [ProjectScope.complete]);
    });

    test('BK-PGP-7: single-select Cancel returns null [2026-07-06]', () {
      // options = [Complete, Code, Examples, Tests, Cancel]; "5" → Cancel.
      final scopes = pickProjectScopes(
        allowMultiple: false,
        driver: ScriptedPromptDriver(['5']),
      );
      expect(scopes, isNull);
    });
  });
}
