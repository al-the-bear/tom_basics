/// `TomLogger` into the structured sink: one place a program's log goes.
library;

import '../logging/logging.dart';
import 'diagnostics.dart';

/// A [TomLogOutput] that writes every `TomLogger` line into a
/// [TomDiagnostics] sink, so a program that logs both ways — rendered lines
/// through `tomLog`, structured events through the port — keeps one log.
///
/// A line becomes an event under [operation] with the rendered text in a
/// `message` field and the caller in `origin`. That field is text by nature:
/// a `TomLogger` caller has already rendered its message, so the redaction the
/// port guarantees for structured events cannot extend to it. What the bridge
/// keeps is everything else the port promises — the level, the UTC time, the
/// isolate, and the sink's own filtering and bounds.
///
/// Levels map onto the port's four: error, severe and fatal are `error`; warn
/// is `warn`; info and status are `info`; debug, traffic and trace are
/// `debug`. A line the logger's own level filters out is not written.
class TomDiagnosticsLogOutput extends TomLogOutput {
  TomDiagnosticsLogOutput(this.sink, {this.operation = 'log'});

  /// Where the lines go.
  final TomDiagnostics sink;

  /// The operation every line is recorded under.
  final String operation;

  @override
  void output(
    TomLogLevel loggerLevel,
    TomLogLevel logLevel,
    String level,
    Object message,
    String isolateName,
    DateTime timeStamp, [
    String? origin,
  ]) {
    if (!logLevel.matches(loggerLevel)) return;
    sink.log(TomDiagnosticEvent(
      operation: operation,
      level: diagnosticLevelOf(logLevel),
      at: timeStamp,
      fields: {
        'message': convertToString(message),
        'isolate': isolateName,
        if (origin != null && origin.isNotEmpty) 'origin': origin,
      },
    ));
  }

  /// The port level a [TomLogLevel] is recorded at.
  static TomDiagnosticLevel diagnosticLevelOf(TomLogLevel level) {
    bool any(List<TomLogLevel> of) => of.any(level.matches);
    if (any([TomLogLevel.error, TomLogLevel.severe, TomLogLevel.fatal])) {
      return TomDiagnosticLevel.error;
    }
    if (any([TomLogLevel.warn])) return TomDiagnosticLevel.warn;
    if (any([TomLogLevel.info, TomLogLevel.status])) {
      return TomDiagnosticLevel.info;
    }
    return TomDiagnosticLevel.debug;
  }
}
