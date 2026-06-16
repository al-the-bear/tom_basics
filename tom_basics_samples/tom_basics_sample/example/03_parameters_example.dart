// Attaching structured parameters to an exception.
//
// The [parameters] map carries structured context alongside the human message —
// the kind of data you want in a log or an error report but would never paste
// into a user-facing string. Keys are arbitrary; values are any Object?.
//
// Run with: dart run example/03_parameters_example.dart
import 'package:tom_basics/tom_basics.dart';

void main() {
  final declined = TomBaseException(
    'PAYMENT_DECLINED',
    'Your card was declined.',
    parameters: {'orderId': 42, 'amount': 19.99, 'currency': 'EUR'},
  );

  print('parameters: ${declined.parameters}');
  // Individual values are typed Object? — read them back by key.
  print('orderId: ${declined.parameters?['orderId']}');

  // expected output:
  // parameters: {orderId: 42, amount: 19.99, currency: EUR}
  // orderId: 42
}
