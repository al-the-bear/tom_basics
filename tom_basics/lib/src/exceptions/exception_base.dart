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
    stackTrace = renderStackTrace(stack, -1);
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

  /// Prints the stack trace to stdout.
  ///
  /// [depth] bounds the frames printed, counting from the throw site, so a
  /// bounded trace keeps the frames nearest the failure. Any negative value
  /// means all of them — -1 is the default and the conventional spelling, not a
  /// required sentinel, so a computed -2 is unbounded too. A [depth] of 0 is a
  /// genuine request for no frames and prints none.
  ///
  /// The bound is applied to the string [stackTrace] already holds rather than
  /// by formatting the trace again. Re-formatting would have to decide what to
  /// do about a null [stack] — falling back to `StackTrace.current` would
  /// report the call path of the *report*, naming none of the code that failed,
  /// and a wrong trace is worse than none because it looks right. The stored
  /// string was captured where the exception was created, which is the moment
  /// worth reporting.
  ///
  /// One frame per line is the contract every renderer here keeps, and is what
  /// makes counting lines the same as counting frames.
  void printStackTrace([int depth = -1]) {
    // ignore: avoid_print
    print(
      "$uuid-$requestUuid exception stacktrace:\n"
      "${_limitFrames(stackTrace, depth)}",
    );
  }

  /// Renders [stack] into the string form [stackTrace] carries.
  ///
  /// **The seam that lets one renderer serve a whole framework.** This class
  /// ships a deliberately narrow default — core frames folded, each remaining
  /// frame rendered with `Frame.toString()` — because tom_basics sits at the
  /// bottom and has no view of what else counts as noise in the layers above
  /// it. A framework that does have one overrides this, and then the string
  /// stored here at construction and whatever that framework formats later are
  /// produced by the same code rather than by two algorithms that quietly
  /// disagree. `tom_core_kernel`'s `TomException` overrides it with
  /// `tomGetStackTrace`.
  ///
  /// Called from the constructor body, so an override must not read state its
  /// own class has not initialised yet. It needs none: [stack] and [depth] are
  /// both arguments, and a renderer is a pure function of them.
  ///
  /// [depth] bounds the frames, counting from the throw site; any negative
  /// value means all of them.
  String renderStackTrace(StackTrace? stack, int depth) {
    final trace = stack ?? StackTrace.current;
    final frames = Chain.forTrace(trace)
        .foldFrames((frame) => frame.isCore, terse: true)
        .traces
        .expand((trace) => trace.frames)
        .toList();

    // `depth >= 0`, not `depth > 0`: a non-negative depth is a bound and every
    // negative one is the absence of a bound. Read as `depth > 0`, a computed
    // depth of 0 fell through to "all frames" — the opposite of what it asks
    // for — and a caller driving the limit from configuration had to
    // special-case zero.
    final selected = depth >= 0 && depth < frames.length
        ? frames.sublist(0, depth)
        : frames;

    return selected.map((frame) => frame.toString()).join('\n');
  }

  /// The first [depth] lines of [trace], or all of it when [depth] is negative.
  ///
  /// One frame per line, so a line count is a frame count.
  static String _limitFrames(String trace, int depth) {
    if (depth < 0 || trace.isEmpty) {
      return trace;
    }
    final lines = trace.split('\n');
    return lines.length <= depth ? trace : lines.take(depth).join('\n');
  }
}
