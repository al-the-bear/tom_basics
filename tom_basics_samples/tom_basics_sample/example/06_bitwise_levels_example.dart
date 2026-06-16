// Composing log levels with bitwise operators.
//
// A [TomLogLevel] is a bit pattern. You combine levels with `+`, remove one with
// `-`, and test membership with `matches`. The named compound levels
// (`production`, `development`, …) are themselves built this way, and `byName`
// resolves a level from a case-insensitive string (handy for config/env vars).
//
// Run with: dart run example/06_bitwise_levels_example.dart
import 'package:tom_basics/tom_basics.dart';

void main() {
  // Build a custom level: info OR error only.
  final combined = TomLogLevel.info + TomLogLevel.error;
  print('info matches combined:  ${combined.matches(TomLogLevel.info)}');
  print('warn matches combined:  ${combined.matches(TomLogLevel.warn)}');

  // Subtract a level from a compound one.
  final quieter = TomLogLevel.production - TomLogLevel.info;
  print('info after removal:     ${quieter.matches(TomLogLevel.info)}');
  print('warn after removal:     ${quieter.matches(TomLogLevel.warn)}');

  // Resolve by name (case-insensitive); unknown names return null.
  print('byName(development): ${TomLogLevel.byName('development')}');
  print('byName(bogus):       ${TomLogLevel.byName('bogus')}');

  // expected output:
  // info matches combined:  true
  // warn matches combined:  false
  // info after removal:     false
  // warn after removal:     true
  // byName(development): TomLogLevel 3871
  // byName(bogus):       null
}
