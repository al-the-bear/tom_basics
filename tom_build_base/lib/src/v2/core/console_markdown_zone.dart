/// Zone-based console_markdown integration for CLI tools.
///
/// Wraps tool execution in a Dart zone that intercepts `print()` calls and
/// applies console_markdown rendering.  This converts markdown syntax
/// (e.g. `**bold**`, `<cyan>text</cyan>`) to ANSI escape codes automatically.
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
// Rendering StringSink wrapper
// ---------------------------------------------------------------------------

/// A [StringSink] that applies `.toConsole()` to every line written.
///
/// Wraps an underlying sink (typically [stdout] or [stderr]) and transparently
/// renders console_markdown syntax into ANSI escape codes.
class ConsoleMarkdownSink implements StringSink {
  /// The underlying output sink.
  final StringSink _delegate;

  ConsoleMarkdownSink(this._delegate);

  @override
  void write(Object? object) {
    _delegate.write(object.toString().toConsole());
  }

  @override
  void writeAll(Iterable objects, [String separator = '']) {
    final rendered = objects
        .map((o) => o.toString().toConsole())
        .join(separator);
    _delegate.write(rendered);
  }

  @override
  void writeCharCode(int charCode) {
    _delegate.writeCharCode(charCode);
  }

  @override
  void writeln([Object? object = '']) {
    _delegate.writeln(object.toString().toConsole());
  }
}

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
/// process exits with code 1.
///
/// Returns the value returned by [body].
Future<T> runWithConsoleMarkdown<T>(
  Future<T> Function() body, {
  void Function(Object error, StackTrace stack)? onError,
}) async {
  // Already inside a console_markdown zone → pass through.
  if (isConsoleMarkdownActive) {
    return body();
  }

  final completer = Completer<T>();

  runZonedGuarded(
    () async {
      try {
        final result = await body();
        if (!completer.isCompleted) completer.complete(result);
      } catch (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      }
    },
    (error, stack) {
      if (onError != null) {
        onError(error, stack);
      } else {
        stderr.writeln('<red>**Uncaught error:**</red> $error'.toConsole());
        stderr.writeln(stack.toString());
        exit(1);
      }
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        parent.print(zone, line.toConsole());
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

  return runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        parent.print(zone, line.toConsole());
      },
    ),
    zoneValues: {kConsoleMarkdownZoneKey: true},
  );
}
