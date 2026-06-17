/// Unit tests for the Windows `.exe` output guard.
///
/// These tests do NOT use TestWorkspace — they exercise the pure static
/// [CompilerExecutor.appendExeToCompileOutput] helper directly, so they run on
/// every host regardless of OS or workspace cleanliness.
///
/// Test IDs: CMP_EXE01–CMP_EXE07
@TestOn('!browser')
@Timeout(Duration(seconds: 30))
library;

import 'package:test/test.dart';
import 'package:tom_build_kit/src/v2/executors/compiler_executor.dart';

void main() {
  group('CompilerExecutor.appendExeToCompileOutput', () {
    test('CMP_EXE01: appends .exe to an extensionless -o target', () {
      final result = CompilerExecutor.appendExeToCompileOutput(
        r'dart compile exe bin/dcli.dart -o C:/tac/tom_binaries/tom/win32-x64/dcli',
      );
      expect(
        result,
        equals(
          r'dart compile exe bin/dcli.dart -o C:/tac/tom_binaries/tom/win32-x64/dcli.exe',
        ),
      );
    });

    test('CMP_EXE02: leaves an already-.exe target unchanged', () {
      const command =
          r'dart compile exe bin/dcli.dart -o C:/out/win32-x64/dcli.exe';
      expect(
        CompilerExecutor.appendExeToCompileOutput(command),
        equals(command),
      );
    });

    test('CMP_EXE03: handles the --output=<path> form', () {
      final result = CompilerExecutor.appendExeToCompileOutput(
        r'dart compile exe bin/x.dart --output=out/x',
      );
      expect(result, equals(r'dart compile exe bin/x.dart --output=out/x.exe'));
    });

    test('CMP_EXE04: preserves quoting on a quoted target', () {
      final result = CompilerExecutor.appendExeToCompileOutput(
        r'dart compile exe bin/x.dart -o "C:/Program Files/out/x"',
      );
      expect(
        result,
        equals(r'dart compile exe bin/x.dart -o "C:/Program Files/out/x.exe"'),
      );
    });

    test('CMP_EXE05: ignores non-compile shell commands', () {
      const command = r'mkdir -p C:/tac/tom_binaries/tom/win32-x64';
      expect(
        CompilerExecutor.appendExeToCompileOutput(command),
        equals(command),
      );
    });

    test('CMP_EXE06: does not touch a target that already has an extension', () {
      // `dart compile exe` with a non-.exe extension is left as-is (we only
      // fill in a *missing* extension, never override an explicit one).
      const command = r'dart compile exe bin/x.dart -o out/x.bin';
      expect(
        CompilerExecutor.appendExeToCompileOutput(command),
        equals(command),
      );
    });

    test('CMP_EXE07: ignores dart compile js (not an exe build)', () {
      const command = r'dart compile js bin/x.dart -o out/x';
      expect(
        CompilerExecutor.appendExeToCompileOutput(command),
        equals(command),
      );
    });
  });
}
