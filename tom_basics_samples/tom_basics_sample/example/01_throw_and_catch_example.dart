// Throwing and catching a TomBaseException.
//
// A TomBaseException always carries a machine-readable [key], a human-readable
// [defaultUserMessage], and a freshly generated UUIDv4 you can quote to the user
// and grep for in your logs. Every instance is uniquely identifiable.
//
// Run with: dart run example/01_throw_and_catch_example.dart
import 'package:tom_basics/tom_basics.dart';

void main() {
  try {
    // A service layer signals a domain failure with a stable key and a message
    // safe to show an end user.
    throw TomBaseException('ORDER_NOT_FOUND', 'We could not find your order.');
  } on TomBaseException catch (e) {
    print('key: ${e.key}');
    print('message: ${e.defaultUserMessage}');
    // The UUID is a random v4 (36 chars: 8-4-4-4-12), unique per instance.
    print('uuid length: ${e.uuid.length}');
    print('runtimeType: ${e.runtimeType}');
  }

  // expected output:
  // key: ORDER_NOT_FOUND
  // message: We could not find your order.
  // uuid length: 36
  // runtimeType: TomBaseException
}
