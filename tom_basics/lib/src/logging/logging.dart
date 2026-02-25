/// Core logging module for the TomBase framework.
///
/// This library provides a flexible, configurable logging system with support for:
/// - Multiple log levels (trace, debug, traffic, info, warn, error, severe, fatal)
/// - Per-class and per-method log level customization
/// - Pluggable log outputs (console, remote, isolate-based)
/// - Stack trace analysis to identify log message origins
///
/// ## Quick Start
///
/// ```dart
/// // Use the global logger instance
/// tomLog.info('Application started');
/// tomLog.debug('Debug information');
/// tomLog.error('Something went wrong');
///
/// // Configure log level
/// tomLog.setLogLevel(TomLogLevel.development);
/// ```
///
/// See also:
/// - [TomLogger] for the main logging class
/// - [TomLogLevel] for available log levels
/// - [TomLogOutput] for custom output implementations
library;

// =============================================================================
// Imports
// =============================================================================

import 'package:stack_trace/stack_trace.dart';

import '../runtime/platform_neutral.dart';

// =============================================================================
// Utility Functions
// =============================================================================

/// Limits the string representation of an object to a maximum length.
///
/// If the string representation of [o] exceeds [maxLength], it will be
/// truncated and appended with '...'.
///
/// Example:
/// ```dart
/// limited('Hello World', 5); // Returns 'Hello...'
/// ```
String limited(Object? o, maxLength) {
  String result = "$o";
  if (result.length > maxLength) {
    result = "${result.substring(0, maxLength)}...";
  }
  return result;
}

// =============================================================================
// Log Level System
// =============================================================================

/// Represents a logging level with support for bitwise operations.
///
/// Log levels are implemented as bit patterns, allowing multiple levels to be
/// combined using the `+` operator and removed using the `-` operator.
///
/// ## Predefined Levels
///
/// Individual levels (in order of verbosity):
/// - [trace] - Most verbose, for detailed tracing
/// - [debug] - Debug information
/// - [traffic] - Network/data traffic logging
/// - [info] - General informational messages
/// - [warn] - Warning messages
/// - [status] - Status updates
/// - [error] - Error conditions
/// - [severe] - Severe errors
/// - [fatal] - Fatal errors that may cause termination
///
/// ## Compound Levels
///
/// - [development] - All levels including trace
/// - [extended] - Production + debug + traffic
/// - [production] - info, warn, errors, status
/// - [still] - warn + errors + status
/// - [silent] - errors + status only
/// - [off] - No logging
///
/// ## Usage
///
/// ```dart
/// // Combine levels
/// var myLevel = TomLogLevel.info + TomLogLevel.error;
///
/// // Remove a level
/// var quieter = TomLogLevel.production - TomLogLevel.info;
///
/// // Check if a message should be logged
/// if (currentLevel.matches(TomLogLevel.debug)) {
///   // Log the debug message
/// }
/// ```
class TomLogLevel {
  /// The bit pattern representing this log level.
  int levelPattern;

  TomLogLevel(this.levelPattern);

  static TomLogLevel trace = TomLogLevel(1);
  static TomLogLevel debug = TomLogLevel(2);
  static TomLogLevel traffic = TomLogLevel(4);
  static TomLogLevel info = TomLogLevel(8);
  static TomLogLevel warn = TomLogLevel(16);

  static TomLogLevel status = TomLogLevel(256);

  static TomLogLevel error = TomLogLevel(512);
  static TomLogLevel severe = TomLogLevel(1024);
  static TomLogLevel fatal = TomLogLevel(2048);

  static TomLogLevel all = TomLogLevel(65535);

  static TomLogLevel development = extended + trace;
  static TomLogLevel extended = production + debug + traffic;
  static TomLogLevel errors = error + severe + fatal;
  static TomLogLevel production = info + warn + errors + status;
  static TomLogLevel still = warn + errors + status;
  static TomLogLevel silent = errors + status;
  static TomLogLevel off = none;

  /// Disables all logging.
  static TomLogLevel none = TomLogLevel(0);

  /// Combines this level with another level using bitwise OR.
  ///
  /// Returns a new [TomLogLevel] that matches both levels.
  TomLogLevel operator +(TomLogLevel other) {
    return TomLogLevel(levelPattern | other.levelPattern);
  }

  /// Removes another level from this level using bitwise AND NOT.
  ///
  /// Returns a new [TomLogLevel] that excludes the other level.
  TomLogLevel operator -(TomLogLevel other) {
    return TomLogLevel(levelPattern & (other.levelPattern ^ all.levelPattern));
  }

  /// Checks if this level matches the given [messageLevel].
  ///
  /// Returns `true` if any bit in both patterns overlaps.
  bool matches(TomLogLevel messageLevel) {
    return (levelPattern & messageLevel.levelPattern) != 0;
  }

  @override
  String toString() {
    return "TomLogLevel $levelPattern";
  }

  /// Looks up a log level by its string name (case-insensitive).
  ///
  /// Returns `null` if the name is not recognized.
  ///
  /// Valid names: TRACE, DEBUG, TRAFFIC, INFO, WARN, STATUS, ERROR, SEVERE,
  /// FATAL, ALL, DEVELOPMENT, EXTENDED, ERRORS, PRODUCTION, STILL, SILENT, OFF
  static TomLogLevel? byName(String name) {
    return _tomLogLevels[name.toUpperCase()];
  }
}

Map<String, TomLogLevel> _tomLogLevels = {
  "TRACE": TomLogLevel.trace,
  "DEBUG": TomLogLevel.debug,
  "TRAFFIC": TomLogLevel.traffic,
  "INFO": TomLogLevel.info,
  "WARN": TomLogLevel.warn,
  "STATUS": TomLogLevel.status,
  "ERROR": TomLogLevel.error,
  "SEVERE": TomLogLevel.severe,
  "FATAL": TomLogLevel.fatal,
  "ALL": TomLogLevel.all,
  "DEVELOPMENT": TomLogLevel.extended + TomLogLevel.trace,
  "EXTENDED": TomLogLevel.production + TomLogLevel.debug + TomLogLevel.traffic,
  "ERRORS": TomLogLevel.error + TomLogLevel.severe + TomLogLevel.fatal,
  "PRODUCTION":
      TomLogLevel.info +
      TomLogLevel.warn +
      TomLogLevel.errors +
      TomLogLevel.status,
  "STILL": TomLogLevel.warn + TomLogLevel.errors + TomLogLevel.status,
  "SILENT": TomLogLevel.errors + TomLogLevel.status,
  "OFF": TomLogLevel.none,
};

// =============================================================================
// Main Logger Class
// =============================================================================

/// The main logger class providing structured logging capabilities.
///
/// TomLogger provides multiple log levels and supports customization through:
/// - Global log level settings
/// - Per-class/method log level overrides
/// - Pluggable output destinations
/// - Stack trace analysis for automatic origin detection
///
/// ## Basic Usage
///
/// Use the global [tomLog] instance for most logging:
///
/// ```dart
/// tomLog.info('Server started on port 8080');
/// tomLog.debug('Processing request: $requestId');
/// tomLog.error('Failed to connect to database');
/// ```
///
/// ## Log Level Configuration
///
/// ```dart
/// // Set global log level
/// tomLog.setLogLevel(TomLogLevel.development);
///
/// // Temporarily increase verbosity
/// tomLog.pushLogLevel(TomLogLevel.trace);
/// // ... verbose operations ...
/// tomLog.popLogLevel();
///
/// // Set level for specific class/method
/// tomLog.addNameLevel('MyClass', TomLogLevel.debug);
/// tomLog.addNameLevel('MyClass.sensitiveMethod', TomLogLevel.trace);
/// ```
///
/// ## Custom Output
///
/// ```dart
/// // Redirect output to a custom destination
/// tomLog.logOutput = MyCustomLogOutput();
/// ```
class TomLogger {
  // ignore: constant_identifier_names
  static const String INFO = "INFO   ";
  // ignore: constant_identifier_names
  static const String ERROR = "ERROR  ";
  // ignore: constant_identifier_names
  static const String WARN = "WARN   ";
  // ignore: constant_identifier_names
  static const String DEBUG = "DEBUG  ";
  // ignore: constant_identifier_names
  static const String TRACE = "TRACE  ";
  // ignore: constant_identifier_names
  static const String TRAFFIC = "TRAFFIC";
  // ignore: constant_identifier_names
  static const String SEVERE = "SEVERE ";
  // ignore: constant_identifier_names
  static const String FATAL = "FATAL  ";
  // ignore: constant_identifier_names
  static const String STATUS = "STATUS ";

  /// Controls whether the logger analyzes the stack trace to determine the caller.
  ///
  /// When `true` (default), the logger will inspect the call stack to identify
  /// which class/method generated the log message. This enables:
  /// - Automatic origin detection in log output
  /// - Per-class/method log level overrides via [addNameLevel]
  ///
  /// Set to `false` to improve performance in high-volume logging scenarios.
  /// Note: Per-name log levels will not work when this is disabled.
  static bool globalSettingDetermineCaller = true;

  TomLogLevel _logLevel = TomLogLevel.production;
  final List<TomLogLevel> _levelStack = [TomLogLevel.production];

  /// The current effective log level.
  TomLogLevel get logLevel => _logLevel;

  /// Sets the current log level.
  ///
  /// Messages with levels not matching [l] will be filtered out.
  void setLogLevel(TomLogLevel l) {
    _logLevel = l;
  }

  /// Pushes a new log level onto the level stack.
  ///
  /// Use this for temporarily changing the log level (e.g., for debugging
  /// a specific section of code). Call [popLogLevel] to restore the previous level.
  ///
  /// Example:
  /// ```dart
  /// tomLog.pushLogLevel(TomLogLevel.trace);
  /// // ... verbose operations ...
  /// tomLog.popLogLevel(); // Restore previous level
  /// ```
  void pushLogLevel(TomLogLevel l) {
    _levelStack.add(l);
    _logLevel = l;
  }

  /// Restores the previous log level from the stack.
  ///
  /// Does nothing if the stack only contains the initial level.
  void popLogLevel() {
    if (_levelStack.length > 1) {
      _levelStack.removeAt(0);
      _logLevel = _levelStack.first;
    }
  }

  static const Type fallback = Object;

  // ---------------------------------------------------------------------------
  // Logging Methods
  // ---------------------------------------------------------------------------

  /// Global toggle for info-level logging.
  static bool globalSettingInfoEnabled = true;

  /// Logs an informational message.
  ///
  /// Use for general runtime information that may be useful for monitoring.
  void info(Object s) {
    if (globalSettingInfoEnabled) output(TomLogLevel.info, INFO, s);
  }

  /// Global toggle for warning-level logging.
  static bool globalSettingWarnEnabled = true;

  /// Logs a warning message.
  ///
  /// Use for potentially problematic situations that don't prevent operation.
  void warn(Object s) {
    if (globalSettingWarnEnabled) output(TomLogLevel.warn, WARN, s);
  }

  /// Global toggle for error-level logging.
  static bool globalSettingErrorEnabled = true;

  /// Logs an error message.
  ///
  /// Use for error conditions that may affect functionality but are recoverable.
  void error(Object s) {
    if (globalSettingErrorEnabled) output(TomLogLevel.error, ERROR, s);
  }

  /// Global toggle for debug-level logging.
  static bool globalSettingDebugEnabled = true;

  /// Logs a debug message.
  ///
  /// Use for detailed information useful during development and debugging.
  void debug(Object s) {
    if (globalSettingDebugEnabled) output(TomLogLevel.debug, DEBUG, s);
  }

  /// Global toggle for trace-level logging.
  static bool globalSettingTraceEnabled = true;

  /// Logs a trace message.
  ///
  /// Use for very detailed tracing information, typically for debugging
  /// complex issues. This is the most verbose level.
  void trace(Object s) {
    if (globalSettingTraceEnabled) output(TomLogLevel.trace, TRACE, s);
  }

  /// Global toggle for traffic-level logging.
  static bool globalSettingTrafficEnabled = true;

  /// Logs a traffic message.
  ///
  /// Use for logging network traffic, API calls, or data flow.
  void traffic(Object s) {
    if (globalSettingTrafficEnabled) output(TomLogLevel.traffic, TRAFFIC, s);
  }

  /// Global toggle for severe-level logging.
  static bool globalSettingSevereEnabled = true;

  /// Logs a severe error message.
  ///
  /// Use for serious errors that may require immediate attention.
  void severe(Object s) {
    if (globalSettingSevereEnabled) output(TomLogLevel.severe, SEVERE, s);
  }

  /// Global toggle for fatal-level logging.
  static bool globalSettingFatalEnabled = true;

  /// Logs a fatal error message.
  ///
  /// Use for critical errors that typically cause application termination.
  void fatal(Object s) {
    if (globalSettingFatalEnabled) output(TomLogLevel.fatal, FATAL, s);
  }

  /// Global toggle for status-level logging.
  static bool globalSettingStatusEnabled = true;

  /// Logs a status message.
  ///
  /// Use for important status updates that should always be visible
  /// (e.g., startup messages, configuration changes).
  void status(Object s) {
    if (globalSettingStatusEnabled) output(TomLogLevel.status, STATUS, s);
  }

  // ---------------------------------------------------------------------------
  // Output Configuration
  // ---------------------------------------------------------------------------

  /// The current log output destination.
  ///
  /// Replace this with a custom [TomLogOutput] implementation to redirect
  /// log messages to different destinations (file, remote server, etc.).
  TomLogOutput logOutput = TomConsoleLogOutput();

  /// Outputs a log message through the configured [logOutput].
  ///
  /// This method handles stack trace analysis (if enabled) and delegates
  /// to the configured output implementation.
  ///
  /// Generally, you should use the convenience methods like [info], [debug],
  /// [error], etc. instead of calling this directly.
  void output(TomLogLevel messageLogLevel, String level, Object message) {
    TomLogLevel? precalculatedLevel;
    String origin = "";
    if (globalSettingDetermineCaller == true) {
      final frames = Chain.forTrace(StackTrace.current)
          .foldFrames(
            (frame) =>
                frame.isCore ||
                frame.package == 'shelf' ||
                (frame.member != null
                    ? frame.member!.startsWith("TomLogger.")
                    : false),
            terse: true,
          )
          .traces[0]
          .frames;
      final frame = frames.firstWhere(
        (frame) =>
            frame.member != null && !frame.member!.startsWith("TomLogger."),
        orElse: () => frames[0],
      );
      if (frame.member != null) {
        origin = frame.member!;
        precalculatedLevel = getNameLevel(origin);

        if (precalculatedLevel == null && frame.member!.contains(".")) {
          String typeName = frame.member!.split(".")[0];

          precalculatedLevel = getNameLevel(typeName);
        }
      }
    }

    TomLogLevel logWith = precalculatedLevel ?? logLevel;

    try {
      logOutput.output(
        logWith,
        messageLogLevel,
        level,
        message,
        TomPlatformUtils.current.getIsolateName(),
        DateTime.now(),
        origin,
      );
    } catch (logError) {
      print("log output failed with error $logError");
    }
  }

  final Map<String, TomLogLevel> _nameLevels = {};

  // ---------------------------------------------------------------------------
  // Per-Name Log Level Configuration
  // ---------------------------------------------------------------------------

  /// Adds a custom log level for a specific method, class, or member.
  ///
  /// Use this to override the global log level for specific code locations.
  /// The [t] parameter can be:
  /// - A method name (e.g., 'isValidEmail') for global functions
  /// - A class name (e.g., 'MyService') for all methods in that class
  /// - A fully qualified member (e.g., 'MyService.processRequest')
  ///
  /// Example:
  /// ```dart
  /// tomLog.addNameLevel('DatabaseService', TomLogLevel.trace);
  /// tomLog.addNameLevel('ApiClient.sendRequest', TomLogLevel.debug);
  /// ```
  void addNameLevel(String t, TomLogLevel tll) {
    _nameLevels[t] = tll;
  }

  /// Gets the custom log level for a specific name.
  ///
  /// Returns `null` if no custom level is set.
  TomLogLevel? getNameLevel(String t) {
    return _nameLevels[t];
  }

  /// Removes the custom log level for a specific name.
  void removeNameLevel(String t) {
    _nameLevels.remove(t);
  }

  /// Sets the log level by its string name.
  ///
  /// Valid names: TRACE, DEBUG, TRAFFIC, INFO, WARN, STATUS, ERROR, SEVERE,
  /// FATAL, ALL, DEVELOPMENT, EXTENDED, ERRORS, PRODUCTION, STILL, SILENT, OFF
  ///
  /// Logs an error if the name is not recognized.
  void setLogLevelByName(String levelName) {
    if (levelName.isEmpty) return;
    TomLogLevel? level = TomLogLevel.byName(levelName);
    if (level != null) {
      setLogLevel(level);
      tomLog.info("Log level set to $levelName");
    } else {
      tomLog.error(
        "Failed to set log level by name, [$levelName] not found. Possible entries are $_tomLogLevels",
      );
    }
  }

  /// Configures multiple per-name log level exceptions from a pattern string.
  ///
  /// The pattern format is: `name1=level1,name2=level2,...`
  ///
  /// Example:
  /// ```dart
  /// tomLog.setLogLevelExceptions('MyClass=DEBUG,ApiClient=TRACE');
  /// ```
  void setLogLevelExceptions(String pattern) {
    if (pattern.isEmpty) return;
    try {
      List<String> pairs = pattern.split(",");
      for (var pair in pairs) {
        List<String> entry = pair.split("=");
        var [name, level] = entry;
        addNameLevel(name, TomLogLevel.byName(level)!);
      }
    } catch (error) {
      tomLog.error(
        "Failed to parse loglevel pattern [$pattern]. Must be <name1>=<level1>,<name2>=<level2>... Allowed levels are $_tomLogLevels",
      );
    }
  }

  @override
  String toString() {
    return "TomLogger $_logLevel $globalSettingDetermineCaller $_levelStack $_nameLevels";
  }
}

// =============================================================================
// Log Output System
// =============================================================================

/// Interface for objects that can provide a custom log representation.
///
/// Implement this interface to control how your objects appear in log messages.
///
/// Example:
/// ```dart
/// class User implements TomLoggable {
///   final String id;
///   final String name;
///
///   @override
///   String get logRepresentation => 'User($id, $name)';
/// }
/// ```
abstract class TomLoggable {
  /// Returns the string representation to use in log messages.
  String get logRepresentation;
}

/// Abstract base class for log output implementations.
///
/// Extend this class to create custom log destinations (file, database,
/// remote server, etc.).
///
/// ## Built-in Implementations
///
/// - [TomConsoleLogOutput] - Outputs to stdout/stderr
/// - `TomRemoteLogOutput` - Sends logs to a remote server
/// - `TomIsolateLogOutput` - Routes logs through isolates
///
/// ## Custom Implementation
///
/// ```dart
/// class FileLogOutput extends TomLogOutput {
///   final File logFile;
///
///   FileLogOutput(this.logFile);
///
///   @override
///   void output(
///     TomLogLevel loggerLevel,
///     TomLogLevel logLevel,
///     String level,
///     Object message,
///     String isolateName,
///     DateTime timeStamp, [
///     String? origin,
///   ]) {
///     if (logLevel.matches(loggerLevel)) {
///       logFile.writeAsStringSync(
///         '$timeStamp $level ${convertToString(message)}\n',
///         mode: FileMode.append,
///       );
///     }
///   }
/// }
/// ```
abstract class TomLogOutput {
  /// Default endpoint path for remote logging.
  static const String _defaultRemoteLogEndpoint = "/remotelog";

  /// Configurable endpoint path for remote logging.
  static String globalSettingRemoteLogEndpoint = _defaultRemoteLogEndpoint;

  /// Outputs a log message.
  ///
  /// Parameters:
  /// - [loggerLevel]: The current logger's configured level
  /// - [logLevel]: The level of this specific message
  /// - [level]: Human-readable level string (e.g., "INFO   ")
  /// - [message]: The log message content
  /// - [isolateName]: Name of the isolate generating the log
  /// - [timeStamp]: When the log was generated
  /// - [origin]: Optional caller information (class.method)
  void output(
    TomLogLevel loggerLevel,
    TomLogLevel logLevel,
    String level,
    Object message,
    String isolateName,
    DateTime timeStamp,
    String? origin,
  );

  /// Converts a message object to its string representation.
  ///
  /// Handles:
  /// - Strings (returned as-is)
  /// - Functions (called and result converted)
  /// - [TomLoggable] objects (uses [logRepresentation])
  /// - Other objects (uses [toString])
  String convertToString(Object message) {
    if (message is String) {
      return message;
    } else if (message is Function) {
      return convertToString(message());
    } else if (message is TomLoggable) {
      return message.logRepresentation;
    } else {
      return "$message";
    }
  }
}

/// Default console-based log output implementation.
///
/// Writes log messages to stdout and stderr based on configurable log levels.
/// This is the default output used by [TomLogger].
///
/// ## Output Routing
///
/// By default:
/// - Errors and status messages go to stderr
/// - All other messages go to stdout
///
/// Configure with [globalSettingStderrLogLevel] and [globalSettingStdoutLogLevel].
///
/// ## Output Format
///
/// Messages are formatted as:
/// ```
/// <timestamp> <isolate>-<name> <level> <message> [<origin>]
/// ```
class TomConsoleLogOutput extends TomLogOutput {
  /// Log levels that will be written to stderr.
  ///
  /// Default: errors + status
  static TomLogLevel globalSettingStderrLogLevel =
      TomLogLevel.errors + TomLogLevel.status;

  /// Log levels that will be written to stdout.
  ///
  /// Default: all except errors and status.
  /// Note: Messages can theoretically appear in both stdout and stderr.
  static TomLogLevel globalSettingStdoutLogLevel =
      TomLogLevel.all - (TomLogLevel.errors + TomLogLevel.status);

  /// Whether to use extended format with additional details.
  bool useExtendedFormat = false;

  @override
  void output(
    TomLogLevel loggerLevel,
    TomLogLevel logLevel,
    String level,
    Object message,
    String isolateName,
    DateTime timeStamp, [
    String? origin,
  ]) {
    if (logLevel.matches(loggerLevel)) {
      String msgString = convertToString(message);
      var msg =
          "$timeStamp ${TomPlatformUtils.current.getIsolateName()}-$isolateName $level $msgString ${origin != null ? ' [$origin]' : ''}";
      if (logLevel.matches(globalSettingStderrLogLevel)) {
        TomPlatformUtils.current.outError(msg);
      }
      if (logLevel.matches(globalSettingStdoutLogLevel)) {
        TomPlatformUtils.current.out(msg);
      }
    }
  }
}

// =============================================================================
// Global Logger Instance
// =============================================================================

/// The global logger instance.
///
/// Use this for all logging throughout the application:
///
/// ```dart
/// tomLog.info('Application started');
/// tomLog.debug('Processing item $id');
/// tomLog.error('Failed to save: $error');
/// ```
///
/// Configure the logger at application startup:
///
/// ```dart
/// void main() {
///   tomLog.setLogLevel(TomLogLevel.development);
///   tomLog.logOutput = MyCustomOutput();
///   // ...
/// }
/// ```
TomLogger tomLog = TomLogger();
