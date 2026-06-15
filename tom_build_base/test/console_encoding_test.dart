/// Unit tests for the UTF-8 console / process-output guard.
///
/// These exercise the pure [decodeProcessOutput] helper and the idempotent
/// [enableUtf8Console] entry point directly, so they run on every host
/// regardless of OS or whether a console is attached.
///
/// See `tool_run_analysis.md` §b.6 ("Minor finding (Windows console
/// encoding)") and cli_tools todo #14.
///
/// Test IDs: ENC01–ENC09
@TestOn('!browser')
@Timeout(Duration(seconds: 30))
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base.dart';

void main() {
  group('decodeProcessOutput', () {
    test('ENC01: decodes UTF-8 bytes with non-ASCII correctly', () {
      // "für" — the umbrella-build failure text that was double-mojibake'd.
      final bytes = utf8.encode('Die Syntax für den Dateinamen ist falsch');
      expect(
        decodeProcessOutput(bytes),
        equals('Die Syntax für den Dateinamen ist falsch'),
      );
    });

    test('ENC02: round-trips a pure-ASCII byte list', () {
      final bytes = utf8.encode('compilation failed: 3 errors');
      expect(decodeProcessOutput(bytes), equals('compilation failed: 3 errors'));
    });

    test('ENC03: passes an already-decoded String through unchanged', () {
      const text = 'already a string with ü';
      expect(decodeProcessOutput(text), same(text));
    });

    test('ENC04: maps null to the empty string', () {
      expect(decodeProcessOutput(null), equals(''));
    });

    test('ENC05: empty byte list decodes to empty string', () {
      expect(decodeProcessOutput(<int>[]), equals(''));
    });

    test('ENC06: tolerates malformed (non-UTF-8) bytes without throwing', () {
      // 0xFC is "ü" in Windows-1252 but an invalid lone UTF-8 byte. It must
      // degrade to the replacement character, never throw or double-mangle.
      final bytes = <int>[0x66, 0xFC, 0x72]; // "f", <bad>, "r"
      final result = decodeProcessOutput(bytes);
      expect(result, startsWith('f'));
      expect(result, endsWith('r'));
      expect(result, contains('�')); // U+FFFD REPLACEMENT CHARACTER
    });

    test('ENC07: does NOT reproduce the double-mojibake of the bug report', () {
      // The regression: capturing UTF-8 "für" via the ANSI code page produced
      // "fÃƒÂ¼r". Decoding the same bytes as UTF-8 must yield clean text.
      final bytes = utf8.encode('für');
      final result = decodeProcessOutput(bytes);
      expect(result, equals('für'));
      expect(result, isNot(contains('Ã')));
      expect(result, isNot(contains('Â')));
    });
  });

  group('enableUtf8Console', () {
    test('ENC08: completes without throwing on this host', () {
      expect(enableUtf8Console, returnsNormally);
    });

    test('ENC09: is idempotent (safe to call repeatedly)', () {
      expect(enableUtf8Console, returnsNormally);
      expect(enableUtf8Console, returnsNormally);
    });
  });
}
