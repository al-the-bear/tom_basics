// Styled console output: Markdown markers become ANSI styling.
//
// TomStandalonePlatformUtils.out / outError push their text through
// console_markdown's .toConsole(), so `**bold**`, `*italic*`, `__underline__`,
// and `` `code` `` come out as ANSI escapes in a terminal — the markers
// themselves are consumed. We import console_markdown here only to *show* the
// transform; in app code you just call `out`.
//
// Run with: dart run example/03_console_output_example.dart
import 'package:console_markdown/console_markdown.dart';
import 'package:tom_basics_console/tom_basics_console.dart';

void main() {
  final p = TomStandalonePlatformUtils();

  // Inspect the transform deterministically (no raw ANSI in the asserts).
  final styled = '**Build complete** in *2.3s*'.toConsole();
  print('contains literal **:    ${styled.contains('**')}');
  print('contains ESC (ANSI):    ${styled.contains('\x1B')}');
  print('words still present:    '
      '${styled.contains('Build complete') && styled.contains('2.3s')}');

  // The package method itself: in a terminal this prints "Build complete" bold
  // and "2.3s" italic; the markers never appear.
  print('--- styled line (ANSI in a terminal): ---');
  p.out('**Build complete** in *2.3s*');
  p.outError('**error:** could not open `config.yaml`');

  // expected output:
  // contains literal **:    false
  // contains ESC (ANSI):    true
  // words still present:    true
  // --- styled line (ANSI in a terminal): ---
  //   <"Build complete" bold, "2.3s" italic — rendered with ANSI escapes>
  //   <"error:" bold, "config.yaml" dimmed>
}
