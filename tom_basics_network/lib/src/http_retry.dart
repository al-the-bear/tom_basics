/// HTTP retry utility with exponential backoff.
///
/// Provides standardized retry logic for HTTP clients.
/// Retries after 2, 4, 8, 16, 32 seconds (up to 62 seconds total).
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Default retry delays in milliseconds: 2, 4, 8, 16, 32 seconds.
const List<int> kDefaultRetryDelaysMs = [2000, 4000, 8000, 16000, 32000];

/// Exception thrown when all retries are exhausted.
class RetryExhaustedException implements Exception {
  /// The last error that occurred.
  final Object lastError;

  /// The last stack trace.
  final StackTrace? lastStackTrace;

  /// The number of attempts made.
  final int attempts;

  /// Creates a retry exhausted exception.
  RetryExhaustedException({
    required this.lastError,
    this.lastStackTrace,
    required this.attempts,
  });

  @override
  String toString() =>
      'RetryExhaustedException: All $attempts attempts failed. Last error: $lastError';
}

/// Configuration for retry behavior.
class RetryConfig {
  /// Delays between retry attempts in milliseconds.
  final List<int> retryDelaysMs;

  /// Optional callback for logging retry attempts.
  final void Function(int attempt, Object error, Duration nextDelay)? onRetry;

  /// Creates a retry configuration.
  const RetryConfig({
    this.retryDelaysMs = kDefaultRetryDelaysMs,
    this.onRetry,
  });

  /// Default configuration with standard 2, 4, 8, 16, 32 second delays.
  static const RetryConfig defaultConfig = RetryConfig();
}

/// Executes an async operation with retry logic.
///
/// Retries the operation according to [config] delays.
/// By default, retries after 2, 4, 8, 16, 32 seconds.
///
/// Example:
/// ```dart
/// final result = await withRetry(
///   () async => await httpClient.get(url),
///   config: RetryConfig(
///     onRetry: (attempt, error, delay) {
///       print('Retry $attempt after $delay: $error');
///     },
///   ),
/// );
/// ```
Future<T> withRetry<T>(
  Future<T> Function() operation, {
  RetryConfig config = RetryConfig.defaultConfig,
  bool Function(Object error)? shouldRetry,
}) async {
  final delays = config.retryDelaysMs;
  Object? lastError;
  StackTrace? lastStackTrace;

  for (var attempt = 0; attempt <= delays.length; attempt++) {
    try {
      return await operation();
    } catch (e, st) {
      lastError = e;
      lastStackTrace = st;

      // Check if we should retry this error
      if (shouldRetry != null && !shouldRetry(e)) {
        rethrow;
      }

      // Check if this error is retryable
      if (!_isRetryableError(e)) {
        rethrow;
      }

      // Check if we have more retries
      if (attempt >= delays.length) {
        throw RetryExhaustedException(
          lastError: lastError,
          lastStackTrace: lastStackTrace,
          attempts: attempt + 1,
        );
      }

      final delay = Duration(milliseconds: delays[attempt]);
      config.onRetry?.call(attempt + 1, e, delay);
      await Future.delayed(delay);
    }
  }

  // Should never reach here, but satisfy the compiler
  throw RetryExhaustedException(
    lastError: lastError!,
    lastStackTrace: lastStackTrace,
    attempts: delays.length + 1,
  );
}

/// Checks if an error is retryable.
bool _isRetryableError(Object error) {
  // Connection errors
  if (error is SocketException) return true;
  if (error is HttpException) return true;
  if (error is TimeoutException) return true;

  // HTTP client errors
  if (error is http.ClientException) return true;

  // OSError for connection issues
  if (error is OSError) return true;

  return false;
}

/// HTTP response extension for checking retryable status codes.
extension RetryableResponse on http.Response {
  /// Returns true if the status code indicates a retryable error.
  bool get isRetryable {
    // Server errors (5xx) are retryable
    if (statusCode >= 500 && statusCode < 600) return true;

    // Request timeout
    if (statusCode == 408) return true;

    // Too many requests (rate limiting)
    if (statusCode == 429) return true;

    return false;
  }
}
