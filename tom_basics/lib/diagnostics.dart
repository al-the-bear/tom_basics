/// Structured diagnostics: the sink port, its events, notices and failures,
/// and the two sinks that need no platform (a bounded ring and a discard).
///
/// Imports nothing, so a package that must stay web-linkable or dependency-light
/// can take this entry point without the rest of `tom_basics`. The rolling log
/// file is `package:tom_basics/diagnostics_io.dart`; the bridge that sends
/// `TomLogger` lines into a sink is in `package:tom_basics/tom_basics.dart`.
library;

export 'src/diagnostics/diagnostics.dart';
