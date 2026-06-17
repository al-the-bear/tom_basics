// What happens when every attempt fails: RetryExhaustedException.
//
// When the operation keeps throwing retryable errors past the last configured
// delay, withRetry gives up and throws RetryExhaustedException — carrying the
// final error, its stack trace, and the total attempt count (initial try plus
// each retry). Here the local server always answers 503, so two short retries
// run and the third failure exhausts the budget.
//
// Run with: dart run example/02_retry_exhausted_example.dart
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:tom_basics_network/tom_basics_network.dart';

Future<void> main() async {
  // A server that is always unhappy.
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    req.response
      ..statusCode = 503
      ..write('{"error":"down"}');
    await req.response.close();
  });

  final client = http.Client();
  final url = Uri.parse('http://127.0.0.1:${server.port}/status');

  try {
    await withRetry<String>(
      () async {
        final res = await client.get(url);
        if (res.isRetryable) {
          throw http.ClientException('HTTP ${res.statusCode}', url);
        }
        return res.body;
      },
      // Two delays => one initial try + two retries = three attempts total.
      config: const RetryConfig(retryDelaysMs: [10, 20]),
    );
  } on RetryExhaustedException catch (e) {
    print('gave up after ${e.attempts} attempts');
    print('last error type: ${e.lastError.runtimeType}');
    print('has stack trace: ${e.lastStackTrace != null}');
  } finally {
    client.close();
    await server.close();
  }

  // expected output:
  // gave up after 3 attempts
  // last error type: ClientException
  // has stack trace: true
}
