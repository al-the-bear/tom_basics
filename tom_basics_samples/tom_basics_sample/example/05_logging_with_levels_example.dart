// Structured logging with a custom output and a level filter.
//
// The global [tomLog] routes through a [TomLogOutput]. The default console
// output stamps each line with a timestamp and origin (great for real apps, but
// non-deterministic), so here we install a tiny deterministic output to keep the
// expected output stable. We then show that the active [TomLogLevel] filters
// which messages are emitted: at `production`, debug is suppressed.
//
// Run with: dart run example/05_logging_with_levels_example.dart
import 'package:tom_basics/tom_basics.dart';

/// Emits `LEVEL: message` with no timestamp — deterministic for tests/examples.
class SimpleLogOutput extends TomLogOutput {
  @override
  void output(
    TomLogLevel loggerLevel,
    TomLogLevel logLevel,
    String level,
    Object message,
    String isolateName,
    DateTime timeStamp,
    String? origin,
  ) {
    // Only emit when the message's level is enabled by the logger's level.
    if (logLevel.matches(loggerLevel)) {
      print('${level.trim()}: ${convertToString(message)}');
    }
  }
}

void main() {
  tomLog.logOutput = SimpleLogOutput();

  // `production` = info + warn + errors + status (no debug/trace/traffic).
  tomLog.setLogLevel(TomLogLevel.production);
  tomLog.debug('this debug is filtered at production');
  tomLog.info('order received');
  tomLog.warn('inventory low');
  tomLog.error('checkout failed');

  print('--- raise to development ---');
  // `development` adds debug, trace and traffic on top.
  tomLog.setLogLevel(TomLogLevel.development);
  tomLog.debug('now visible');

  // expected output:
  // INFO: order received
  // WARN: inventory low
  // ERROR: checkout failed
  // --- raise to development ---
  // DEBUG: now visible
}
