/// Unit tests for compiler placeholder misuse detection.
///
/// These tests do NOT use TestWorkspace — they exercise the pure static
/// [CompilerExecutor.detectMisusedPlaceholders] helper directly, so they run
/// regardless of workspace cleanliness.
///
/// Test IDs: CMP_PLM01, CMP_PLM02, CMP_PLM03, CMP_PLM04, CMP_PLM05
@TestOn('!browser')
@Timeout(Duration(seconds: 30))
library;

import 'package:test/test.dart';
import 'package:tom_build_kit/src/v2/executors/compiler_executor.dart';

void main() {
  group('CompilerExecutor.detectMisusedPlaceholders', () {
    test('CMP_PLM01: flags a known placeholder written as \${...}', () {
      final result = CompilerExecutor.detectMisusedPlaceholders(
        r'dart compile exe ${file} -o out',
      );
      expect(result, equals(['file']));
    });

    test('CMP_PLM02: flags every known \${...} misuse, de-duplicated', () {
      final result = CompilerExecutor.detectMisusedPlaceholders(
        r'mkdir -p $HOME/.tom/bin/${target-platform-vs} && '
        r'dart compile exe ${file} --target-os=${target-os} '
        r'-o $HOME/.tom/bin/${target-platform-vs}/${file.name}',
      );
      // First-appearance order, no duplicates ($HOME is a real env var and
      // must NOT be flagged).
      expect(
        result,
        equals(['target-platform-vs', 'file', 'target-os', 'file.name']),
      );
    });

    test('CMP_PLM03: correct %{...} syntax is not flagged', () {
      final result = CompilerExecutor.detectMisusedPlaceholders(
        r'shell dart compile exe %{file} --target-os=%{dart-target-os} '
        r'--target-arch=%{dart-target-arch} '
        r'-o $HOME/.tom/bin/%{target-platform-vs}/%{file.name}',
      );
      expect(result, isEmpty);
    });

    test('CMP_PLM04: real env vars in \${...} form are not flagged', () {
      // ${HOME}/${PATH} are environment variables, not compiler placeholders.
      final result = CompilerExecutor.detectMisusedPlaceholders(
        r'echo ${HOME} ${PATH} ${SOME_VAR}',
      );
      expect(result, isEmpty);
    });

    test('CMP_PLM05: bracket [name] form is not flagged as misuse', () {
      // [file] is an accepted alternate placeholder form, not a ${} mistake.
      final result = CompilerExecutor.detectMisusedPlaceholders(
        r'dart compile exe [file] -o out',
      );
      expect(result, isEmpty);
    });
  });
}
