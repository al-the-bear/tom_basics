/// Which projects a `--minor` / `--major` selector actually selects.
///
/// THE DEFECT (SCE10). A selector that matches NO project was not reported.
/// The project simply took the default patch bump, and every downstream signal
/// agreed with it: the pubspec said a version, `--versioner` stamped the same
/// version from it, the CHANGELOG section was written beside them. The release
/// was internally consistent and numbered wrong — the one shape a release
/// checklist cannot catch by eye, because nothing disagrees.
///
/// Measured on `tom_d4rt_generator` with buildkit 1.7.1, before the fix:
///
///     --minor=.                   1.26.2 -> 1.27.0  (minor)
///     --minor=tom_d4rt_generator  1.26.2 -> 1.26.3  (PATCH, silently)
///     --minor=d4rt_generator      1.26.2 -> 1.26.3  (PATCH, silently)
///
/// Only the printed path worked. The pubspec name — the obvious thing to type,
/// and the one a release checklist names — did not.
///
/// WHY THE EXISTING SUITE DID NOT CATCH IT: `versionbump_test.dart` passes
/// `--minor _build`, and `_build` is both the pubspec name AND the directory,
/// so it matches on the path and the name branch is never exercised. A fixture
/// whose two names agree cannot tell the two mechanisms apart.
///
/// THESE ARE UNIT TESTS, following `compiler_exe_guard_test.dart`: they
/// exercise the two pure functions directly, so they run on every host
/// regardless of workspace cleanliness. The integration harness refuses to
/// start when anything under the workspace root is uncommitted, which on a
/// shared machine is most of the time and is not a property of this defect.
///
/// Test IDs: VBM_SEL01–VBM_SEL03
@TestOn('!browser')
@Timeout(Duration(seconds: 30))
library;

import 'package:test/test.dart';
import 'package:tom_build_kit/src/v2/executors/bumpversion_executor.dart';

void main() {
  group('SCE10: a selector that matches nothing is reported', () {
    test('VBM_SEL01: an unmatched selector produces a failure naming it '
        '[2026-09-18] (PASS)', () {
      final message = unmatchedSelectorFailure(
        selectors: {'no_such_project_here', 'tom_build_kit'},
        matched: {'tom_build_kit'},
        processed: {'tom_build_kit', 'tom_build_base'},
      );

      expect(message, isNotNull);
      expect(message, contains('no_such_project_here'));
      expect(
        message,
        contains('tom_build_base'),
        reason:
            'the projects that were processed are listed, so correcting the '
            'selector does not cost a second run to discover the right name',
      );
    });

    test('VBM_SEL02: every selector matching leaves nothing to report '
        '[2026-09-18] (PASS)', () {
      // The half that must NOT fail, pinned so the fix above cannot be made by
      // refusing everything.
      expect(
        unmatchedSelectorFailure(
          selectors: {'a', 'b'},
          matched: {'a', 'b'},
          processed: {'a', 'b'},
        ),
        isNull,
      );
      expect(
        unmatchedSelectorFailure(
          selectors: {},
          matched: {},
          processed: {'anything'},
        ),
        isNull,
        reason: 'no selectors at all is the ordinary patch-bump run',
      );
    });
  });

  group('SCE10: what a selector may name', () {
    test('VBM_SEL03: the pubspec name selects, as well as the path '
        '[2026-09-18] (PASS)', () {
      expect(
        projectMatchesSelector(
          projectName: 'd4rtgen',
          projectPath: '/w/tom_ai/d4rt/tom_d4rt_generator',
          pubspecName: 'tom_d4rt_generator',
          selectors: {'tom_d4rt_generator'},
        ),
        isTrue,
        reason: 'the pubspec name is the name a release checklist writes',
      );

      expect(
        projectMatchesSelector(
          projectName: 'd4rtgen',
          projectPath: '/w/tom_ai/d4rt/tom_d4rt_generator',
          pubspecName: null,
          selectors: {'tom_d4rt_generator'},
        ),
        isTrue,
        reason: 'the path suffix still matches when no pubspec name is known',
      );

      expect(
        projectMatchesSelector(
          projectName: 'd4rtgen',
          projectPath: '/w/tom_ai/d4rt/tom_d4rt_generator',
          pubspecName: 'tom_d4rt_generator',
          selectors: {'tom_d4rt'},
        ),
        isFalse,
        reason:
            'a PREFIX of the name must not match — `tom_d4rt` and '
            '`tom_d4rt_generator` are different packages, and a selector that '
            'caught both would bump the wrong one',
      );
    });
  });
}
