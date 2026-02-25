/// Base exception class for the TOM framework.
///
/// This library provides a minimal exception base class with UUID tracking
/// and stack trace support. It is designed to be independent of other
/// framework components for use in low-level libraries.
///
/// ## Example
///
/// ```dart
/// // Create and throw a tracked exception
/// throw TomBaseException(
///   'USER_NOT_FOUND',
///   'The requested user could not be found',
///   parameters: {'userId': userId},
/// );
///
/// // Catch and inspect
/// try {
///   // ... operation that may fail
/// } on TomBaseException catch (e) {
///   print('Error ${e.uuid}: ${e.key}');
///   print(e.stackTrace);
/// }
/// ```
library;

import 'package:uuid/v4.dart';
import 'package:stack_trace/stack_trace.dart';

// =============================================================================
// EXCEPTION CLASSES
// =============================================================================

/// Base exception class with UUID tracking, timestamps, and stack trace support.
///
/// [TomBaseException] provides a structured way to create and handle exceptions
/// with comprehensive metadata for debugging and error tracking:
///
/// - **UUID**: Each exception gets a unique identifier for tracing
/// - **Request UUID**: Optional correlation with request context
/// - **Timestamp**: When the exception occurred
/// - **Stack Trace**: Formatted and stored for later inspection
///
/// This class is designed to have minimal dependencies for use in foundational
/// libraries. For the full-featured exception class with logging support,
/// use [TomException] from tom_core_kernel.
///
/// ## Example
///
/// ```dart
/// // Basic exception
/// throw TomBaseException('ERROR_CODE', 'Something went wrong');
///
/// // Exception with parameters for context
/// throw TomBaseException(
///   'VALIDATION_ERROR',
///   'Invalid email format',
///   parameters: {'field': 'email', 'value': userInput},
/// );
/// ```
class TomBaseException implements Exception {
  /// Unique identifier for this exception instance.
  ///
  /// Auto-generated using UUIDv4 if not provided in constructor.
  late String uuid;

  /// Optional UUID of the request that triggered this exception.
  ///
  /// Used for correlating exceptions with specific API requests.
  String? requestUuid;

  /// When this exception was created.
  DateTime timeStamp = DateTime.timestamp();

  /// Error key/code for programmatic error handling.
  ///
  /// Use consistent keys like 'USER_NOT_FOUND', 'VALIDATION_ERROR', etc.
  String key;

  /// User-friendly error message suitable for display.
  String defaultUserMessage;

  /// Additional context parameters for debugging.
  ///
  /// Include relevant values that help diagnose the error.
  Map<String, Object?>? parameters;

  /// Original stack trace object for processing.
  Object? stack;

  /// The underlying exception that caused this error, if any.
  Object? rootException;

  /// Formatted stack trace string.
  late String stackTrace;

  /// Creates a new [TomBaseException] with the given error details.
  ///
  /// The [key] should be a consistent error code for programmatic handling.
  /// The [defaultUserMessage] should be human-readable.
  TomBaseException(
    this.key,
    this.defaultUserMessage, {
    this.requestUuid,
    this.parameters,
    this.rootException,
    this.stack,
    String? uuid,
  }) {
    stackTrace = _getStackTrace(stack);
    if (uuid != null) {
      this.uuid = uuid;
    } else {
      var generator = UuidV4();
      this.uuid = generator.generate();
    }
  }

  @override
  String toString() =>
      "$uuid-$requestUuid, $runtimeType: $key, $defaultUserMessage, $parameters, $rootException";

  /// Prints the stack trace to stderr.
  ///
  /// The [depth] parameter limits how many stack frames to print.
  /// Use -1 (default) to print all frames.
  void printStackTrace([int depth = -1]) {
    // ignore: avoid_print
    print("$uuid-$requestUuid exception stacktrace:\n$stackTrace");
  }

  /// Core implementation for processing stack trace frames.
  static String _getStackTrace([Object? s, int depth = -1]) {
    final trace = s as StackTrace? ?? StackTrace.current;
    final frames = Chain.forTrace(trace)
        .foldFrames(
          (frame) => frame.isCore,
          terse: true,
        )
        .traces
        .expand((trace) => trace.frames)
        .toList();

    final selectedFrames =
        depth > 0 && depth < frames.length ? frames.sublist(0, depth) : frames;

    return selectedFrames.map((frame) => frame.toString()).join('\n');
  }
}
