/// Structured diagnostics: a sink, and what lands in it.
///
/// A **port** with two implementations that need no platform — a bounded ring
/// buffer and a discard — so code that logs runs unchanged on the web, on the
/// VM and in tests. The rolling log file, which needs `dart:io`, is
/// `package:tom_basics/diagnostics_io.dart`. This library imports nothing, so
/// any package can depend on it without its dependency closure growing.
///
/// ## Structured, not formatted
///
/// An event carries an operation name and a field map, never a rendered
/// sentence. The redaction rule is that secrets are *structurally* unable to
/// reach a log, and that rule only has teeth while the payload is still data: a
/// caller that hands over a pre-formatted string has already interpolated
/// whatever it had, and the sink can no longer tell a locator from a password.
/// Rendering is the backend's job and happens after the decision about what may
/// be logged has been made.
///
/// `TomLogger` lines reach the same sink through `TomDiagnosticsLogOutput`
/// (`package:tom_basics/tom_basics.dart`), so a program has one place its log
/// goes, whichever of the two a caller writes with.
library;

/// How much the reader is meant to care.
enum TomDiagnosticLevel { error, warn, info, debug }

/// One structured entry.
class TomDiagnosticEvent {
  /// When it happened, in UTC — the log is read across machines that do not
  /// share a timezone, and a local stamp makes two hosts' lines uncomparable.
  final DateTime at;

  final TomDiagnosticLevel level;

  /// What was being done, in dotted form (`script.run`, `sync.commit`).
  ///
  /// A closed vocabulary is not imposed: the field exists so a reader can
  /// filter, and a registry of operation names would have to be edited by every
  /// feature that ever logs.
  final String operation;

  /// The payload. Values must be JSON-shaped; nothing here is rendered by
  /// interpolation at the call site.
  final Map<String, Object?> fields;

  TomDiagnosticEvent({
    required this.operation,
    required this.fields,
    this.level = TomDiagnosticLevel.info,
    DateTime? at,
  }) : at = (at ?? DateTime.now()).toUtc();

  Map<String, Object?> toMap() => {
    'at': at.toIso8601String(),
    'level': level.name,
    'operation': operation,
    ...fields,
  };
}

/// A finding that has to be **both shown and logged**.
///
/// The redaction rule is that secrets are structurally unable to reach a log,
/// and that rule only has teeth while the payload is still data. But some
/// findings are also addressed to a person, and a person needs a sentence. Producing the sentence and then handing
/// *it* to the sink would defeat the rule; producing the sentence somewhere
/// else and the fields here would let the two drift.
///
/// So one producer emits both halves at once. [fields] is what the log keeps;
/// [message] is what the user reads; neither is derived from the other, and a
/// caller branches on [operation] or [fields], never on the rendered text.
class TomDiagnosticNotice {
  final TomDiagnosticLevel level;

  /// Dotted operation name, as [TomDiagnosticEvent.operation].
  final String operation;

  /// JSON-shaped payload. Carries locators, never contents.
  final Map<String, Object?> fields;

  /// The sentence, already phrased for a person.
  final String message;

  TomDiagnosticNotice({
    required this.operation,
    required this.fields,
    required this.message,
    this.level = TomDiagnosticLevel.warn,
  });

  /// The log form. A fresh event each call, so its `at` is the moment it was
  /// recorded rather than the moment the finding was made — the two differ
  /// whenever a finding is carried across an await, which is every time one
  /// travels out of a factory.
  TomDiagnosticEvent get event => TomDiagnosticEvent(
    operation: operation,
    level: level,
    fields: fields,
  );

  @override
  String toString() => 'TomDiagnosticNotice($level $operation: $message)';
}

/// Where structured events go.
abstract interface class TomDiagnostics {
  void log(TomDiagnosticEvent event);
}

/// The sink a build that logs nowhere gets.
///
/// It exists so that "diagnostics are not bound in this build" is a value a
/// caller can hold rather than a null it must test before every log. A
/// producer with no sink would otherwise grow a null check per call site, and
/// one of them would eventually be missing.
class TomNullDiagnostics implements TomDiagnostics {
  const TomNullDiagnostics();

  @override
  void log(TomDiagnosticEvent event) {}
}

/// A bounded in-memory sink.
///
/// The default that is actually useful: a test can assert what was logged, and
/// a diagnostics panel can show the recent past without a file backend
/// existing. Bounded because an unbounded one is a leak in a long session —
/// [capacity] events are kept and the oldest are dropped.
class TomInMemoryDiagnostics implements TomDiagnostics {
  TomInMemoryDiagnostics({this.capacity = 500})
    : assert(capacity > 0, 'a zero-capacity sink is a null sink');

  final int capacity;
  final List<TomDiagnosticEvent> _events = [];

  /// Oldest first.
  List<TomDiagnosticEvent> get events => List.unmodifiable(_events);

  @override
  void log(TomDiagnosticEvent event) {
    _events.add(event);
    if (_events.length > capacity) {
      _events.removeRange(0, _events.length - capacity);
    }
  }

  void clear() => _events.clear();
}

/// A failure that can say what it is without its text.
///
/// An exception's `toString()` is prose from whoever raised it, and the log's
/// rule is that a field map carries structure only: a sidecar parse error can
/// quote the file it failed on, which is where people's comments are, and a
/// network library's message is not something this codebase wrote. A failure
/// that knows structural facts about itself — an HTTP status, which operation,
/// which section — states them here, so a log site can record them without
/// knowing the failure's type, including types it may not name.
abstract interface class TomStructuredFailure {
  /// Structural facts only: identifiers, codes and kinds — never a message, a
  /// body, or text a producer outside this codebase wrote.
  Map<String, Object> get diagnosticFields;
}

/// The field map a failure is logged under: its type, and whatever it says
/// about itself structurally ([TomStructuredFailure]). Never its text.
Map<String, Object> tomFailureFields(Object error) => {
  'error': error.runtimeType.toString(),
  if (error is TomStructuredFailure) ...error.diagnosticFields,
};
