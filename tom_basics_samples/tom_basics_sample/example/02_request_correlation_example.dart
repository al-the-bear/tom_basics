// Correlating failures across one request with requestUuid.
//
// Each exception gets its own [uuid], but you can stamp every failure raised
// while handling a single inbound request with a shared [requestUuid]. That
// lets you pull *all* failures for one request out of an aggregated log, while
// still telling the individual failures apart.
//
// Run with: dart run example/02_request_correlation_example.dart
import 'package:tom_basics/tom_basics.dart';

void main() {
  // A correlation id you would normally take from the inbound HTTP request.
  const requestUuid = 'req-7f3a';

  final validation = TomBaseException(
    'VALIDATION',
    'Bad input',
    requestUuid: requestUuid,
  );
  final dbTimeout = TomBaseException(
    'DB_TIMEOUT',
    'Slow store',
    requestUuid: requestUuid,
  );

  print('first.requestUuid:  ${validation.requestUuid}');
  print('second.requestUuid: ${dbTimeout.requestUuid}');
  // Same request, but each exception is still individually identifiable.
  print('same request:  ${validation.requestUuid == dbTimeout.requestUuid}');
  print('distinct uuid: ${validation.uuid != dbTimeout.uuid}');

  // expected output:
  // first.requestUuid:  req-7f3a
  // second.requestUuid: req-7f3a
  // same request:  true
  // distinct uuid: true
}
