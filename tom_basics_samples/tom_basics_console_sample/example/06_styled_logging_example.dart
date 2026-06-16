// Styled logging: the logger routes through the platform seam.
//
// The default console log sink writes via TomPlatformUtils.current.out/outError.
// So once the standalone implementation is installed, every `tomLog` line is
// rendered through console_markdown too — `**bold**` in a log message becomes
// ANSI bold. The log line also carries a timestamp/isolate/origin (host- and
// time-specific), so we assert the deterministic rendering transform and emit
// one real styled line for illustration.
//
// Run with: dart run example/06_styled_logging_example.dart
import 'package:console_markdown/console_markdown.dart';
import 'package:tom_basics_console/tom_basics_console.dart';

void main() {
  TomPlatformUtils.setCurrentPlatform(TomStandalonePlatformUtils());
  tomLog.setLogLevel(TomLogLevel.production);

  // The same transform the logger's console sink applies to each message.
  final rendered = '**server** started on port 8080'.toConsole();
  print('markers consumed: ${!rendered.contains('**')}');
  print('ANSI present:     ${rendered.contains('\x1B')}');

  // A real log line (timestamped; "server" comes out bold in a terminal).
  print('--- a real, styled log line follows: ---');
  tomLog.info('**server** started on port 8080');

  // expected output:
  // markers consumed: true
  // ANSI present:     true
  // --- a real, styled log line follows: ---
  //   <timestamped INFO line; "server" rendered bold via ANSI>
}
