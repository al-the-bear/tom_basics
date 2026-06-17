// Reading the default backoff schedule without waiting for it.
//
// kDefaultRetryDelaysMs is the schedule withRetry uses when you pass no custom
// delays: 2, 4, 8, 16, 32 seconds — exponential, capped at five retries, ~62 s
// of total patience. RetryConfig.defaultConfig wraps exactly that. This example
// just inspects the constants so you can see the shape of the policy; it does
// not actually sleep.
//
// Run with: dart run example/05_default_backoff_schedule_example.dart
import 'package:tom_basics_network/tom_basics_network.dart';

void main() {
  final seconds = kDefaultRetryDelaysMs.map((ms) => '${ms ~/ 1000}s').join(', ');
  print('retries: ${kDefaultRetryDelaysMs.length}');
  print('schedule: $seconds');

  final totalMs = kDefaultRetryDelaysMs.fold<int>(0, (sum, ms) => sum + ms);
  print('total wait: ${totalMs ~/ 1000}s');

  // defaultConfig is just the standard schedule with no onRetry hook.
  final usingDefault = RetryConfig.defaultConfig.retryDelaysMs == kDefaultRetryDelaysMs;
  print('defaultConfig uses kDefaultRetryDelaysMs: $usingDefault');

  // expected output:
  // retries: 5
  // schedule: 2s, 4s, 8s, 16s, 32s
  // total wait: 62s
  // defaultConfig uses kDefaultRetryDelaysMs: true
}
