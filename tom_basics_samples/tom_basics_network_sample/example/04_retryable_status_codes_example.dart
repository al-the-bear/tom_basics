// Classifying HTTP responses: which status codes are worth a retry.
//
// The RetryableResponse extension adds `.isRetryable` to any http.Response.
// It is true for the whole 5xx server-error range plus 408 (Request Timeout)
// and 429 (Too Many Requests) — the codes where the same request might succeed
// later. Client errors like 400/404 are *not* retryable: the request itself is
// the problem. This is pure classification, so no server is needed.
//
// Run with: dart run example/04_retryable_status_codes_example.dart
import 'package:http/http.dart' as http;
import 'package:tom_basics_network/tom_basics_network.dart';

Future<void> main() async {
  const codes = [200, 400, 404, 408, 429, 500, 503, 599];

  for (final code in codes) {
    final response = http.Response('', code);
    final verdict = response.isRetryable ? 'retry' : 'fail fast';
    print('HTTP $code -> $verdict');
  }

  // expected output:
  // HTTP 200 -> fail fast
  // HTTP 400 -> fail fast
  // HTTP 404 -> fail fast
  // HTTP 408 -> retry
  // HTTP 429 -> retry
  // HTTP 500 -> retry
  // HTTP 503 -> retry
  // HTTP 599 -> retry
}
