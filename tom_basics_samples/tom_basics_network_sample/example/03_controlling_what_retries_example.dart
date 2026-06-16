// Deciding which errors are worth retrying.
//
// withRetry only retries a built-in set of *transport* failures — SocketException,
// HttpException, TimeoutException, http.ClientException, OSError. Anything else
// (a programming error like FormatException, an ArgumentError) is surfaced
// immediately, because retrying a bug just wastes time. The optional
// shouldRetry callback can only *narrow* that set further: returning false
// stops a retry that would otherwise happen.
//
// No network needed — we throw the errors directly to show the policy.
//
// Run with: dart run example/03_controlling_what_retries_example.dart
import 'dart:async';

import 'package:tom_basics_network/tom_basics_network.dart';

Future<void> main() async {
  // Part A: a non-retryable error short-circuits — the operation runs once.
  var runsA = 0;
  try {
    await withRetry<void>(
      () async {
        runsA++;
        throw const FormatException('malformed payload');
      },
      config: const RetryConfig(retryDelaysMs: [10, 20]),
    );
  } on FormatException catch (e) {
    print('A: surfaced ${e.runtimeType} after $runsA run(s)');
  }

  // Part B: shouldRetry can veto an otherwise-retryable error. A TimeoutException
  // is normally retried, but here we decide a "fatal" one should not be.
  var runsB = 0;
  try {
    await withRetry<void>(
      () async {
        runsB++;
        throw TimeoutException('fatal: deadline exceeded');
      },
      config: const RetryConfig(retryDelaysMs: [10, 20]),
      shouldRetry: (error) =>
          !(error is TimeoutException && error.message!.startsWith('fatal')),
    );
  } on TimeoutException catch (e) {
    print('B: vetoed ${e.runtimeType} after $runsB run(s)');
  }

  // expected output:
  // A: surfaced FormatException after 1 run(s)
  // B: vetoed TimeoutException after 1 run(s)
}
