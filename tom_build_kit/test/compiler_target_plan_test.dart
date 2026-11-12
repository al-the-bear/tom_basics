/// Which of a compile section's `targets:` a run builds, and why the others
/// are not built (oqa8: the listed targets used to vanish from the trace).
///
/// Pure: [CompilerExecutor.planTargets] and [PlatformUtils.canBuildOn] are
/// exercised directly; nothing is compiled.
///
/// Test IDs: CMP_PLAN01 .. CMP_PLAN07
@TestOn('!browser')
library;

import 'package:test/test.dart';
import 'package:tom_build_kit/src/platform_utils.dart';
import 'package:tom_build_kit/src/v2/executors/compiler_executor.dart';

void main() {
  group('CompilerExecutor.planTargets', () {
    test('CMP_PLAN01: a plain run builds the host and names the rest', () {
      final plan = CompilerExecutor.planTargets(
        allowedTargets: ['darwin-arm64', 'linux-x64'],
        currentPlatform: 'darwin-arm64',
      );
      expect(plan.build, ['darwin-arm64']);
      expect(plan.notBuilt.keys, ['linux-x64']);
      expect(plan.notBuilt['linux-x64'], contains('--all-platforms'));
      expect(plan.unbuildable, isEmpty);
    });

    test('CMP_PLAN02: --all-platforms builds every listed target', () {
      final plan = CompilerExecutor.planTargets(
        allowedTargets: ['darwin-arm64', 'linux-x64'],
        currentPlatform: 'darwin-arm64',
        allPlatforms: true,
      );
      expect(plan.build, ['darwin-arm64', 'linux-x64']);
      expect(plan.notBuilt, isEmpty);
    });

    test('CMP_PLAN03: a target the host cannot build is a named skip', () {
      final plan = CompilerExecutor.planTargets(
        allowedTargets: ['darwin-arm64', 'linux-x64', 'win32-x64'],
        currentPlatform: 'darwin-arm64',
        allPlatforms: true,
      );
      expect(plan.build, ['darwin-arm64', 'linux-x64']);
      expect(plan.unbuildable.keys, ['win32-x64']);
      expect(
        plan.unbuildable['win32-x64'],
        contains('cannot build win32-x64 on darwin-arm64'),
      );
    });

    test('CMP_PLAN04: --targets builds the matching targets only', () {
      final plan = CompilerExecutor.planTargets(
        allowedTargets: ['darwin-arm64', 'linux-x64'],
        currentPlatform: 'darwin-arm64',
        targetFilter: ['linux-x64'],
      );
      expect(plan.build, ['linux-x64']);
      expect(plan.notBuilt['darwin-arm64'], contains('--targets'));
    });

    test('CMP_PLAN05: a host outside the list builds nothing by default', () {
      final plan = CompilerExecutor.planTargets(
        allowedTargets: ['darwin-arm64', 'linux-x64'],
        currentPlatform: 'win32-x64',
      );
      expect(plan.build, isEmpty);
      expect(plan.notBuilt.keys, ['darwin-arm64', 'linux-x64']);
    });

    test(
      'CMP_PLAN06: --targets naming an unbuildable target skips it by name',
      () {
        final plan = CompilerExecutor.planTargets(
          allowedTargets: ['darwin-arm64', 'win32-x64'],
          currentPlatform: 'linux-x64',
          targetFilter: ['win32-x64'],
        );
        expect(plan.build, isEmpty);
        expect(plan.unbuildable.keys, ['win32-x64']);
      },
    );
  });

  test('CMP_PLAN07: dart compile exe cross-compiles to Linux only', () {
    expect(PlatformUtils.canBuildOn('darwin-arm64', 'darwin-arm64'), isTrue);
    expect(PlatformUtils.canBuildOn('darwin-arm64', 'linux-x64'), isTrue);
    expect(PlatformUtils.canBuildOn('win32-x64', 'linux-arm64'), isTrue);
    expect(PlatformUtils.canBuildOn('darwin-arm64', 'win32-x64'), isFalse);
    expect(PlatformUtils.canBuildOn('linux-x64', 'darwin-arm64'), isFalse);
    expect(PlatformUtils.canBuildOn('darwin-arm64', 'darwin-x64'), isFalse);
  });
}
