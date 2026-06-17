/// Unit tests for the `skip-compile-with-buildkit` opt-out flag.
///
/// These exercise the pure static [CompilerExecutor.skipCompileWithBuildkit]
/// parser (and the exact [CompilerExecutor.compileSkippedMessage] text)
/// directly, so they run on every host without a provisioned workspace.
///
/// A project that sets `compiler: { skip-compile-with-buildkit: true }` in its
/// buildkit.yaml opts out of being compiled by a running buildkit — resolving
/// the Windows self-overwrite file lock (buildkit/tom_bs cannot overwrite their
/// own in-use .exe). The skip is a configured success, not a failure. See
/// tool_run_analysis §b.5 / §b.7 and cli_tools todo #15.
///
/// Test IDs: CMP_SKIP01–CMP_SKIP09
@TestOn('!browser')
@Timeout(Duration(seconds: 30))
library;

import 'package:test/test.dart';
import 'package:tom_build_kit/src/v2/executors/compiler_executor.dart';

void main() {
  group('CompilerExecutor.skipCompileWithBuildkit', () {
    test('CMP_SKIP01: true when the flag is set to true', () {
      const yaml = '''
compiler:
  skip-compile-with-buildkit: true
  compiles:
    - pipeline:
        - shell dart compile exe bin/buildkit.dart -o out
      files:
        - bin/buildkit.dart
''';
      expect(CompilerExecutor.skipCompileWithBuildkit(yaml), isTrue);
    });

    test('CMP_SKIP02: false when the flag is set to false', () {
      const yaml = '''
compiler:
  skip-compile-with-buildkit: false
  compiles: []
''';
      expect(CompilerExecutor.skipCompileWithBuildkit(yaml), isFalse);
    });

    test('CMP_SKIP03: false when the flag is absent', () {
      const yaml = '''
compiler:
  compiles:
    - files:
        - bin/buildkit.dart
''';
      expect(CompilerExecutor.skipCompileWithBuildkit(yaml), isFalse);
    });

    test('CMP_SKIP04: false when there is no compiler section', () {
      const yaml = '''
versioner:
  variable-prefix: buildkit
''';
      expect(CompilerExecutor.skipCompileWithBuildkit(yaml), isFalse);
    });

    test('CMP_SKIP05: false on empty content', () {
      expect(CompilerExecutor.skipCompileWithBuildkit(''), isFalse);
    });

    test('CMP_SKIP06: false on malformed YAML (no throw)', () {
      const yaml = 'compiler: : : not: valid: yaml: [';
      expect(CompilerExecutor.skipCompileWithBuildkit(yaml), isFalse);
    });

    test('CMP_SKIP07: a non-boolean truthy value does not count as true', () {
      // Only an actual YAML boolean `true` opts out — a string "true" must not.
      const yaml = '''
compiler:
  skip-compile-with-buildkit: "yes"
''';
      expect(CompilerExecutor.skipCompileWithBuildkit(yaml), isFalse);
    });

    test('CMP_SKIP08: compiler section that is not a map yields false', () {
      const yaml = '''
compiler: just-a-scalar
''';
      expect(CompilerExecutor.skipCompileWithBuildkit(yaml), isFalse);
    });
  });

  group('CompilerExecutor.compileSkippedMessage', () {
    test('CMP_SKIP09: matches the exact text required by the end summary', () {
      // tool_run_analysis §b.7 / todo #15 require the summary to read
      // "<project>: compile skipped as configured in buildkit.yaml".
      expect(
        CompilerExecutor.compileSkippedMessage,
        equals('compile skipped as configured in buildkit.yaml'),
      );
    });
  });
}
