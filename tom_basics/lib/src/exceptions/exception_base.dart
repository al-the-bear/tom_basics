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
///   'users.fetch.not_found',
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
/// throw TomBaseException('orders.submit.no_positions', 'The order is empty');
///
/// // Exception with parameters for context
/// throw TomBaseException(
///   'users.validate.invalid_email',
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

  /// Error key for programmatic error handling.
  ///
  /// Dotted lowercase, `lower_snake_case` within each segment, reading
  /// `<area>.<operation>.<condition>` — `users.fetch.not_found`,
  /// `orders.submit.no_positions`. The **first segment names the module or
  /// subsystem**, which is what keeps keys from unrelated code from colliding
  /// and lets a handler match a whole area with a prefix test.
  ///
  /// The key is not a message: it is the value callers switch on and the
  /// natural lookup key for a translated message, so it should stay stable even
  /// when the wording it accompanies changes. `tom_core_kernel` documents the
  /// convention in full, and every key in the Tom framework follows it.
  String key;

  /// User-friendly error message suitable for display.
  String defaultUserMessage;

  /// Additional context parameters for debugging.
  ///
  /// Include relevant values that help diagnose the error.
  Map<String, Object?>? parameters;

  /// The trace captured where this exception was created, if there is one.
  ///
  /// `StackTrace?` rather than `Object?`, which is what the very next thing to
  /// touch it always required: the constructor hands this straight to
  /// [_getStackTrace], and `Chain.forTrace` takes a `StackTrace`. A wider field
  /// promised a width nothing downstream accepted, and — being public and
  /// mutable — let an unformattable value be assigned after construction, where
  /// it surfaced as a `TypeError` thrown *while reporting some other failure*.
  StackTrace? stack;

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
  ///
  /// The parameter is `StackTrace?` rather than `Object?` for the same reason
  /// the field is: this line used to read `s as StackTrace?`, an unchecked
  /// downcast that threw for any non-null value that was not a trace. Rejecting
  /// such a value at compile time costs the caller nothing, whereas the cast
  /// cost the failure being reported.
  static String _getStackTrace([StackTrace? s, int depth = -1]) {
    final trace = s ?? StackTrace.current;
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
