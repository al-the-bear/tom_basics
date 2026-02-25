/// Central logging and process execution for Tom build tools.
///
/// Provides:
/// - Verbose logging with automatic flag detection
/// - Centralized process execution that logs commands when verbose
/// - Consistent output formatting across all tools
library;

import 'dart:io';

/// Global verbose flag accessor.
///
/// Set via [ToolLogger.verbose] or checked via [ToolLogger.isVerbose].
// ignore: unnecessary_getters_setters - allows future logic in getters/setters
class ToolLogger {
  static bool _verbose = false;
  static StringSink _output = stdout;

  /// Whether verbose mode is enabled.
  static bool get isVerbose => _verbose;

  /// Set verbose mode globally.
  static set verbose(bool value) => _verbose = value;

  /// Output sink for log messages. Defaults to stdout.
  /// Change for testing.
  // ignore: unnecessary_getters_setters
  static StringSink get output => _output;
  // ignore: unnecessary_getters_setters
  static set output(StringSink sink) => _output = sink;

  /// Log a message only if verbose mode is enabled.
  ///
  /// Use for debugging output that should only appear with --verbose.
  static void logVerbose(String message) {
    if (_verbose) {
      _output.writeln(message);
    }
  }

  /// Log an info message (always shown).
  static void logInfo(String message) {
    _output.writeln(message);
  }

  /// Log an error message (always shown).
  static void logError(String message) {
    _output.writeln('Error: $message');
  }

  /// Log a warning message (always shown).
  static void logWarning(String message) {
    _output.writeln('Warning: $message');
  }

  /// Log the command being executed (only in verbose mode).
  ///
  /// Formats the command as: `$ command arg1 arg2 ...`
  static void logCommand(String executable, List<String> args,
      {String? workingDirectory}) {
    if (_verbose) {
      final cmdStr = [executable, ...args].join(' ');
      if (workingDirectory != null) {
        _output.writeln('[\$ $cmdStr] (in $workingDirectory)');
      } else {
        _output.writeln('[\$ $cmdStr]');
      }
    }
  }
}

/// Result of a process execution.
class ProcessRunResult {
  /// Exit code from the process.
  final int exitCode;

  /// Standard output as a string.
  final String stdout;

  /// Standard error as a string.
  final String stderr;

  /// Whether the process succeeded (exit code 0).
  bool get success => exitCode == 0;

  const ProcessRunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

/// Central process execution with verbose logging.
///
/// Use this instead of [Process.run] directly to get automatic
/// command logging when --verbose is enabled.
class ProcessRunner {
  /// Run a process and return the result.
  ///
  /// Logs the command when [ToolLogger.isVerbose] is true.
  /// The [workingDirectory] is used for both execution and log output.
  static Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    // Log command if verbose
    ToolLogger.logCommand(executable, arguments,
        workingDirectory: workingDirectory);

    // Run the process
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
    );

    return ProcessRunResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  /// Run a shell command (via sh -c on Unix, cmd /c on Windows).
  ///
  /// Logs the command when [ToolLogger.isVerbose] is true.
  static Future<ProcessRunResult> runShell(
    String command, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final isWindows = Platform.isWindows;
    final executable = isWindows ? 'cmd' : 'sh';
    final args = isWindows ? ['/c', command] : ['-c', command];

    // Log full shell command if verbose
    if (ToolLogger.isVerbose) {
      if (workingDirectory != null) {
        ToolLogger.output.writeln('[\$ $command] (in $workingDirectory)');
      } else {
        ToolLogger.output.writeln('[\$ $command]');
      }
    }

    // Run the process
    final result = await Process.run(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
    );

    return ProcessRunResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  /// Run a process with streaming output to stdout/stderr.
  ///
  /// Logs the command when [ToolLogger.isVerbose] is true.
  /// Returns the exit code.
  static Future<int> runStreaming(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    // Log command if verbose
    ToolLogger.logCommand(executable, arguments,
        workingDirectory: workingDirectory);

    // Start the process
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
    );

    // Stream output
    await Future.wait([
      process.stdout.forEach((data) => stdout.add(data)),
      process.stderr.forEach((data) => stderr.add(data)),
    ]);

    return process.exitCode;
  }
}
