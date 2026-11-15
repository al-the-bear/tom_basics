/// Zone-based console_markdown integration for CLI tools.
///
/// Wraps tool execution in a Dart zone that intercepts `print()` calls and
/// applies console_markdown rendering. Markdown syntax (e.g. `**bold**`,
/// `<cyan>text</cyan>`) becomes ANSI escape codes on a terminal; piped or
/// redirected output, and every output under `NO_COLOR`, gets the text with
/// the markers removed and no escape code ([consoleStylingEnabled]).
///
/// Tools that already run inside a console_markdown zone (e.g. tom_d4rt_dcli)
/// are detected via the [kConsoleMarkdownZoneKey] zone value.  When nested,
/// the inner zone is a pass-through to avoid double-rendering.
///
/// ## Usage
///
/// In a tool's `main()`:
///
/// ```dart
/// Future<void> main(List<String> args) async {
///   await runWithConsoleMarkdown(() => _main(args));
/// }
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'package:console_markdown/console_markdown.dart';

// ---------------------------------------------------------------------------
// Zone key
// ---------------------------------------------------------------------------

/// Zone-local key that indicates console_markdown rendering is active.
///
/// Callers can check `Zone.current[kConsoleMarkdownZoneKey] == true`
/// to determine whether they are already inside a rendering zone.
const Symbol kConsoleMarkdownZoneKey = #consoleMarkdownActive;

/// Returns `true` if the current zone already applies console_markdown.
bool get isConsoleMarkdownActive =>
    Zone.current[kConsoleMarkdownZoneKey] == true;

// ---------------------------------------------------------------------------
// Styling decision and rendering
// ---------------------------------------------------------------------------

/// Whether console markdown becomes ANSI styling on a stream: `NO_COLOR` set
/// to a non-empty value turns it off (no-color.org), also over `FORCE_COLOR`;
/// `FORCE_COLOR` set to anything but `0` / `false` turns it on through a pipe;
/// otherwise the stream must be a terminal ([hasTerminal]). Logs, `| grep`,
/// files written with `>` and tests that capture stdout get no escape codes.
bool consoleStylingEnabled({
  required bool hasTerminal,
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  if ((env['NO_COLOR'] ?? '').isNotEmpty) return false;
  final force = (env['FORCE_COLOR'] ?? '').trim().toLowerCase();
  if (force.isNotEmpty) return force != '0' && force != 'false';
  return hasTerminal;
}

/// [consoleStylingEnabled] for [stream] (stdout or stderr) in this process.
/// A terminal is what [stdioType] reports: `Stdout.hasTerminal` is false in
/// some pseudo-terminals (e.g. under `script`) where the stream is one.
bool streamStylingEnabled(Stdout stream) => consoleStylingEnabled(
  hasTerminal: stdioType(stream) == StdioType.terminal || stream.hasTerminal,
);

/// SGR escape sequences (`ESC [ ... m`): what console_markdown writes, and
/// what a tool's own colored output carries.
final RegExp _sgr = RegExp(r'\x1B\[[0-9;]*m');

/// [text] with its console markdown rendered: as ANSI styling when [styled],
/// else as plain text, the markers removed and any escape code dropped.
String renderConsoleMarkdown(String text, {required bool styled}) {
  final rendered = text.toConsole();
  return styled ? rendered : rendered.replaceAll(_sgr, '');
}

// ---------------------------------------------------------------------------
// Rendering StringSink wrapper
// ---------------------------------------------------------------------------

/// A [StringSink] that renders console markdown in every string written
/// ([renderConsoleMarkdown]).
///
/// [styled] says whether it becomes ANSI styling; by default it is decided for
/// the stream the sink wraps ([streamStylingEnabled]: a terminal, no
/// `NO_COLOR`), and for any other sink as for [stdout].
class ConsoleMarkdownSink implements StringSink {
  /// The underlying output sink.
  final StringSink _delegate;

  /// Whether markdown becomes ANSI styling (else plain text).
  final bool styled;

  ConsoleMarkdownSink(this._delegate, {bool? styled})
    : styled =
          styled ??
          streamStylingEnabled(_delegate is Stdout ? _delegate : stdout);

  String _render(Object? object) =>
      renderConsoleMarkdown(object.toString(), styled: styled);

  @override
  void write(Object? object) {
    _delegate.write(_render(object));
  }

  @override
  void writeAll(Iterable objects, [String separator = '']) {
    _delegate.write(objects.map(_render).join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    _delegate.writeCharCode(charCode);
  }

  @override
  void writeln([Object? object = '']) {
    _delegate.writeln(_render(object));
  }
}

// ---------------------------------------------------------------------------
// Broken pipe
// ---------------------------------------------------------------------------

/// Whether [error] says the reader of a pipe went away: `tool | head -1`,
/// `grep -m1`, a pager quit early. EPIPE (32) on macOS and Linux;
/// ERROR_BROKEN_PIPE (109) and ERROR_NO_DATA (232) on Windows.
bool isBrokenPipe(Object error) {
  final OSError? os = switch (error) {
    FileSystemException(:final osError) => osError,
    SocketException(:final osError) => osError,
    _ => null,
  };
  if (os == null) return false;
  if (Platform.isWindows) {
    return os.errorCode == 109 || os.errorCode == 232;
  }
  return os.errorCode == 32;
}

/// Makes a broken pipe on stdout or stderr end the program quietly with the
/// exit code it has so far (0 for a run that went well), as `head` users
/// expect, instead of an unhandled error with a stack trace. A write can
/// throw at once (caught in [runWithConsoleMarkdown]), go to the zone's
/// handler, or fail the sink's `done` future, outside every zone a tool runs
/// in; this handles the last. Any other error on the sink still surfaces.
void _exitQuietlyOnBrokenPipe() {
  if (_brokenPipeHandled) return;
  _brokenPipeHandled = true;
  for (final sink in [stdout, stderr]) {
    sink.done.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (isBrokenPipe(error)) exit(exitCode);
        Zone.root.handleUncaughtError(error, stack);
      },
    );
  }
}

bool _brokenPipeHandled = false;

// ---------------------------------------------------------------------------
// Zone runner
// ---------------------------------------------------------------------------

/// Run [body] inside a Dart zone that automatically renders console_markdown
/// syntax in every `print()` call.
///
/// If the current zone already has console_markdown active (detected via
/// [kConsoleMarkdownZoneKey]), [body] runs directly without adding another
/// rendering layer — this prevents double-rendering when tools are invoked
/// from contexts that already set up the zone (e.g. `tom_d4rt_dcli`).
///
/// The optional [onError] callback handles uncaught errors.  By default,
/// errors are printed to stderr with console_markdown formatting and the
/// process exits with code 1. A broken pipe on stdout or stderr (the reader
/// of `tool | head -1` went away, [isBrokenPipe]) is no error: the process
/// exits quietly with the exit code it has so far.
///
/// Returns the value returned by [body].
Future<T> runWithConsoleMarkdown<T>(
  Future<T> Function() body, {
  void Function(Object error, StackTrace stack)? onError,
}) async {
  _exitQuietlyOnBrokenPipe();

  // Already inside a console_markdown zone → pass through.
  if (isConsoleMarkdownActive) {
    return body();
  }

  final completer = Completer<T>();
  // print() writes to stdout; decided once for the run.
  final styled = streamStylingEnabled(stdout);

  runZonedGuarded(
    () async {
      try {
        final result = await body();
        if (!completer.isCompleted) completer.complete(result);
      } catch (error, stack) {
        // A write to a closed pipe throws synchronously out of the tool's
        // own code: the reader went away, the run ends quietly.
        if (isBrokenPipe(error)) exit(exitCode);
        if (!completer.isCompleted) completer.completeError(error, stack);
      }
    },
    (error, stack) {
      if (isBrokenPipe(error)) exit(exitCode);
      if (onError != null) {
        onError(error, stack);
      } else {
        stderr.writeln(
          renderConsoleMarkdown(
            '<red>**Uncaught error:**</red> $error',
            styled: streamStylingEnabled(stderr),
          ),
        );
        stderr.writeln(stack.toString());
        exit(1);
      }
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        parent.print(zone, renderConsoleMarkdown(line, styled: styled));
      },
    ),
    zoneValues: {kConsoleMarkdownZoneKey: true},
  );

  return completer.future;
}

/// Synchronous variant of [runWithConsoleMarkdown] for tools that don't
/// need async (rarely used — prefer the async version).
T runWithConsoleMarkdownSync<T>(
  T Function() body, {
  void Function(Object error, StackTrace stack)? onError,
}) {
  if (isConsoleMarkdownActive) {
    return body();
  }
  final styled = streamStylingEnabled(stdout);

  return runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        parent.print(zone, renderConsoleMarkdown(line, styled: styled));
      },
    ),
    zoneValues: {kConsoleMarkdownZoneKey: true},
  );
}
