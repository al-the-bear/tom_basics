/// Utilities for executing multi-line scripts and stdin-piped commands.
///
/// Provides shared functionality for both [PipelineExecutor] and
/// [CompilerTool] to handle multi-line shell scripts and stdin piping.
library;

import 'dart:convert';
import 'dart:io';

/// Check if a command string is a multi-line shell script.
///
/// Returns true if the trimmed command starts with "shell\n", indicating
/// the content after the keyword is a multi-line script body.
///
/// Example YAML:
/// ```yaml
/// commands:
///   - |
///     shell
///     echo "line 1"
///     echo "line 2"
/// ```
bool isMultiLineShellScript(String command) {
  return command.trim().startsWith('shell\n');
}

/// Extract the script body from a multi-line shell command.
///
/// Assumes the command starts with "shell\n". Returns the content
/// after "shell\n" with leading/trailing whitespace trimmed.
String extractScriptBody(String command) {
  final trimmed = command.trim();
  // "shell\n" is 6 characters
  return trimmed.substring(6);
}

/// Check if a command is a stdin-piping command.
///
/// Returns true if the command starts with "stdin " and contains
/// a newline (the content to pipe).
///
/// Example YAML:
/// ```yaml
/// commands:
///   - |
///     stdin dcli
///     import 'dart:io';
///     void main() {
///       print('Hello from DartScript!');
///     }
/// ```
bool isStdinCommand(String command) {
  final trimmed = command.trim();
  return trimmed.startsWith('stdin ') && trimmed.contains('\n');
}

/// Parse a stdin command into its command and stdin content parts.
///
/// Format: `stdin <command>\n<stdin-content>`
///
/// Returns null if the format is invalid (no command, no content,
/// or missing newline).
({String command, String stdinContent})? parseStdinCommand(String rawCommand) {
  final trimmed = rawCommand.trim();
  if (!trimmed.startsWith('stdin ')) return null;

  final firstNewline = trimmed.indexOf('\n');
  if (firstNewline == -1) return null;

  // Extract command (after "stdin " up to first newline)
  final commandPart = trimmed.substring(6, firstNewline).trim();
  final stdinContent = trimmed.substring(firstNewline + 1);

  if (commandPart.isEmpty) return null;

  return (command: commandPart, stdinContent: stdinContent);
}

/// Execute a command with content piped to its stdin.
///
/// Uses [Process.start] to launch the command via `sh -c` and writes
/// [stdinContent] to the process stdin before closing it.
///
/// Variable expansion should be applied to [command] by the caller
/// BEFORE calling this method. The [stdinContent] is passed through
/// without variable expansion to avoid conflicts with language-specific
/// `$` syntax (e.g., Dart string interpolation).
///
/// Returns true if the command exits with code 0.
Future<bool> executeWithStdin({
  required String command,
  required String stdinContent,
  String? workingDirectory,
  Map<String, String>? environment,
  bool dryRun = false,
  bool verbose = false,
}) async {
  if (dryRun) {
    final lines = stdinContent.split('\n');
    print('  [DRY RUN] Would pipe stdin to: $command');
    for (final line in lines.take(5)) {
      print('    | $line');
    }
    if (lines.length > 5) {
      print('    | ... (${lines.length - 5} more lines)');
    }
    return true;
  }

  if (verbose) {
    final lines = stdinContent.split('\n');
    print('  Piping stdin to: $command');
    for (final line in lines) {
      print('    | $line');
    }
  }

  try {
    final process = await Process.start(
      'sh',
      ['-c', command],
      workingDirectory: workingDirectory,
      environment: environment,
    );

    // Write stdin content and close
    process.stdin.write(stdinContent);
    await process.stdin.close();

    // Capture output
    final stdoutStr = await process.stdout.transform(utf8.decoder).join();
    final stderrStr = await process.stderr.transform(utf8.decoder).join();

    final exitCode = await process.exitCode;

    if (stdoutStr.isNotEmpty) {
      stdout.write(stdoutStr);
    }
    if (stderrStr.isNotEmpty) {
      stderr.write(stderrStr);
    }

    if (exitCode != 0) {
      print('  Command failed with exit code $exitCode');
      return false;
    }

    return true;
  } catch (e) {
    print('  Error executing command with stdin: $e');
    return false;
  }
}
