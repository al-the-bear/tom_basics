/// UTF-8 console + process-output guard.
///
/// On Windows the console (conhost) defaults to the OEM/ANSI locale code page
/// rather than UTF-8. Two things go wrong as a result:
///
/// 1. **Captured subprocess output is mis-decoded.** `dart compile` and friends
///    write their diagnostics as UTF-8, but [Process.run] decodes them with
///    [systemEncoding] (the ANSI code page, e.g. Windows-1252 on a German host),
///    turning "für" into "fÃ¼r" — and once that re-enters the console pipeline
///    it can mangle a second time ("fÃƒÂ¼r").
/// 2. **Our own output is mis-rendered.** Even a correct Dart string is written
///    through [stdout]/[stderr] using [systemEncoding] and then displayed by a
///    non-UTF-8 console, so non-ASCII characters are garbled.
///
/// [enableUtf8Console] fixes both by switching the console code page to UTF-8
/// and routing the Dart sinks through UTF-8. [decodeProcessOutput] fixes the
/// capture side by decoding raw process bytes as UTF-8 (tolerating malformed
/// sequences from tools that still emit OEM text).
///
/// See `tool_run_analysis.md` §b.6 ("Minor finding (Windows console encoding)").
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

/// The Windows UTF-8 code page identifier (`CP_UTF8`).
const int _cpUtf8 = 65001;

bool _consoleConfigured = false;

/// Switch the process to UTF-8 console output so non-ASCII tool output renders
/// correctly.
///
/// On Windows this sets the console input/output code pages to UTF-8 (the
/// `chcp 65001` equivalent, done in-process via the Win32 API) and switches the
/// [stdout]/[stderr] sinks to UTF-8 encoding. On every other platform — where
/// the console is already UTF-8 — it is a no-op.
///
/// Safe to call more than once: only the first call takes effect. Every step is
/// individually guarded, so a redirected/detached stdout (no attached console,
/// or a sink that rejects an encoding change) degrades silently instead of
/// crashing the tool.
void enableUtf8Console() {
  if (_consoleConfigured) return;
  _consoleConfigured = true;

  if (Platform.isWindows) {
    _setWindowsConsoleCodePages();
  }

  // Encode our own output as UTF-8 so the (now UTF-8) console renders it
  // correctly. On non-Windows hosts the sinks are already UTF-8; reasserting it
  // is harmless.
  try {
    stdout.encoding = utf8;
  } catch (_) {
    // Sink does not allow changing the encoding (e.g. already written to, or
    // detached). Nothing actionable — leave the default in place.
  }
  try {
    stderr.encoding = utf8;
  } catch (_) {
    // As above.
  }
}

/// Set the Windows console input/output code pages to UTF-8 via kernel32.
///
/// Uses only integer-argument Win32 calls, so no `package:ffi` string
/// marshalling is required. Failures (FFI unavailable, output redirected so no
/// console is attached) are swallowed: the code-page switch is best-effort.
void _setWindowsConsoleCodePages() {
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final setConsoleOutputCp = kernel32.lookupFunction<Int32 Function(Uint32),
        int Function(int)>('SetConsoleOutputCP');
    final setConsoleCp = kernel32.lookupFunction<Int32 Function(Uint32),
        int Function(int)>('SetConsoleCP');
    setConsoleOutputCp(_cpUtf8);
    setConsoleCp(_cpUtf8);
  } catch (_) {
    // No attached console or FFI unavailable — best-effort only.
  }
}

/// Decode raw process output as UTF-8, tolerating malformed byte sequences.
///
/// [Process.run] returns `List<int>` for stdout/stderr when invoked with
/// `stdoutEncoding: null` / `stderrEncoding: null`; pass that here to decode it
/// as UTF-8 regardless of the host's locale code page. Already-decoded [String]
/// values pass through unchanged, and `null` becomes the empty string.
///
/// `allowMalformed: true` means bytes that are not valid UTF-8 (e.g. genuine
/// OEM-encoded text from a legacy tool) degrade to the Unicode replacement
/// character rather than throwing or producing double-mojibake.
String decodeProcessOutput(Object? raw) {
  if (raw == null) return '';
  if (raw is String) return raw;
  if (raw is List<int>) return utf8.decode(raw, allowMalformed: true);
  return raw.toString();
}
