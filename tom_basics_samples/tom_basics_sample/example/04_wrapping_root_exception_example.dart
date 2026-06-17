// Wrapping a low-level cause in a domain exception.
//
// When a low-level failure (a FormatException, an IO error) bubbles up, wrap it
// in a TomBaseException so callers see a stable domain [key] and a safe message,
// while the original cause is preserved in [rootException] for diagnosis.
//
// Run with: dart run example/04_wrapping_root_exception_example.dart
import 'package:tom_basics/tom_basics.dart';

void main() {
  try {
    try {
      // A low-level parse failure deep in the stack.
      int.parse('not-a-number');
    } on FormatException catch (cause) {
      // Translate it into a domain failure, keeping the cause attached.
      throw TomBaseException(
        'PRICE_PARSE_FAILED',
        'The price could not be read.',
        rootException: cause,
        parameters: {'raw': 'not-a-number'},
      );
    }
  } on TomBaseException catch (e) {
    print('key: ${e.key}');
    print('rootException is FormatException: ${e.rootException is FormatException}');
    print('raw: ${e.parameters?['raw']}');
  }

  // expected output:
  // key: PRICE_PARSE_FAILED
  // rootException is FormatException: true
  // raw: not-a-number
}
