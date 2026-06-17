// Controlling how your own objects appear in logs with TomLoggable.
//
// Implement [TomLoggable] to give a domain object a deliberate log form. When
// you pass such an object to a logging method, the output uses
// [logRepresentation] instead of the default `toString()` — so you decide
// exactly what lands in the log (and what does not, e.g. secrets).
//
// Run with: dart run example/07_loggable_example.dart
import 'package:tom_basics/tom_basics.dart';

/// A domain object that opts in to a curated log representation.
class Order implements TomLoggable {
  Order(this.id, this.customer);
  final int id;
  final String customer;

  @override
  String get logRepresentation => 'Order(#$id for $customer)';
}

/// Deterministic output (see 05) so the expected output stays stable.
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
    if (logLevel.matches(loggerLevel)) {
      print('${level.trim()}: ${convertToString(message)}');
    }
  }
}

void main() {
  tomLog.logOutput = SimpleLogOutput();
  tomLog.setLogLevel(TomLogLevel.production);

  // The logger calls convertToString, which honours TomLoggable.
  tomLog.info(Order(42, 'Ada'));

  // expected output:
  // INFO: Order(#42 for Ada)
}
