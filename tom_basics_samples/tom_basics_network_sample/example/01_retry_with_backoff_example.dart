// Retrying a flaky HTTP call with exponential backoff.
//
// withRetry() re-runs an async operation when it throws a *retryable* error,
// waiting the configured delay between attempts. The natural pattern is: make
// the request, and if the response carries a retryable status code, throw so
// withRetry takes over. Here a tiny local server fails twice with 503 and then
// answers 200, so we watch two backoff steps and then a success.
//
// The real default schedule is 2/4/8/16/32 s; we override it with millisecond
// delays so the example finishes instantly. Run offline.
//
// Run with: dart run example/01_retry_with_backoff_example.dart
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:tom_basics_network/tom_basics_network.dart';

Future<void> main() async {
  // A flaky server: the first two requests get 503, the third gets 200.
  var hits = 0;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    hits++;
    if (hits < 3) {
      req.response
        ..statusCode = 503
        ..write('{"error":"warming up"}');
    } else {
      req.response
        ..statusCode = 200
        ..write('{"status":"ready"}');
    }
    await req.response.close();
  });

  final client = http.Client();
  final url = Uri.parse('http://127.0.0.1:${server.port}/status');

  try {
    final body = await withRetry<String>(
      () async {
        final res = await client.get(url);
        // Turn a retryable status code into a thrown error so withRetry sees
        // it. 2xx falls through and ends the retry loop.
        if (res.isRetryable) {
          throw http.ClientException('HTTP ${res.statusCode}', url);
        }
        return res.body;
      },
      config: RetryConfig(
        retryDelaysMs: const [20, 40, 80],
        onRetry: (attempt, error, nextDelay) {
          print('attempt $attempt failed: $error — retrying in $nextDelay');
        },
      ),
    );
    print('success on attempt $hits: $body');
  } finally {
    client.close();
    await server.close();
  }

  // expected output:
  // attempt 1 failed: ClientException: HTTP 503, uri=http://127.0.0.1:<port>/status — retrying in 0:00:00.020000
  // attempt 2 failed: ClientException: HTTP 503, uri=http://127.0.0.1:<port>/status — retrying in 0:00:00.040000
  // success on attempt 3: {"status":"ready"}
  //
  // (<port> is an OS-assigned ephemeral port, so it differs every run; the
  //  attempt counts, delays, and final body are stable.)
}
