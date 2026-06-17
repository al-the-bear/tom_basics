/// Guided mode utilities using DCli package.
///
/// Provides interactive prompts for BuildKit CLI tools.
/// This is a DCli-based replacement for the interact package.
library;

import 'dart:io';

import 'package:dcli/dcli.dart' as dcli;

/// Result of a guided mode operation.
enum GuidedResult {
  /// User completed the flow
  completed,

  /// User cancelled the operation
  cancelled,

  /// User wants to go back
  back,
}

/// Helper class for guided mode interactions.
///
/// Uses DCli for cross-platform interactive prompts.
class GuidedMode {
  /// Show a single-select menu and return selected index.
  ///
  /// Returns -1 if cancelled.
  int menu(
    String prompt,
    List<String> options, {
    int defaultIndex = 0,
    bool showCancel = true,
  }) {
    final allOptions = showCancel ? [...options, 'Cancel'] : options;

    // DCli menu returns the selected item, not the index
    final result = dcli.menu(
      prompt,
      options: allOptions,
      defaultOption: allOptions[defaultIndex],
    );

    final index = allOptions.indexOf(result);

    // If Cancel was selected
    if (showCancel && index == allOptions.length - 1) {
      return -1;
    }

    return index;
  }

  /// Show a multi-select menu with checkboxes.
  ///
  /// Uses a looping menu approach since DCli doesn't have native multi-select.
  /// Returns list of selected indices, or empty list if cancelled.
  List<int> multiSelect(
    String prompt,
    List<String> options, {
    List<bool>? defaults,
    bool showInstructions = true,
  }) {
    final selected = <int>{};

    // Initialize with defaults
    if (defaults != null) {
      for (var i = 0; i < defaults.length && i < options.length; i++) {
        if (defaults[i]) selected.add(i);
      }
    }

    if (showInstructions) {
      print('  (Select options one by one, choose "Done" when finished)');
    }

    while (true) {
      // Build display options with checkmarks
      final displayOptions = options
          .asMap()
          .entries
          .map((e) => '${selected.contains(e.key) ? "[✓]" : "[ ]"} ${e.value}')
          .toList();
      displayOptions.add('── Done ──');
      displayOptions.add('── Cancel ──');

      final result = dcli.menu(prompt, options: displayOptions);

      final idx = displayOptions.indexOf(result);

      if (idx == displayOptions.length - 1) {
        // Cancel
        return [];
      } else if (idx == displayOptions.length - 2) {
        // Done
        return selected.toList()..sort();
      } else {
        // Toggle selection
        if (selected.contains(idx)) {
          selected.remove(idx);
        } else {
          selected.add(idx);
        }
      }
    }
  }

  /// Show a confirmation prompt (Y/n or y/N).
  bool confirm(String prompt, {bool defaultYes = true}) {
    return dcli.confirm(prompt, defaultValue: defaultYes);
  }

  /// Show a text input prompt.
  String input(
    String prompt, {
    String? defaultValue,
    bool Function(String)? validator,
    String? validationError,
  }) {
    // DCli's ask doesn't support custom validators directly,
    // so we implement validation manually
    while (true) {
      final result = dcli.ask(prompt, defaultValue: defaultValue);
      if (validator == null || validator(result)) {
        return result;
      }
      print(validationError ?? 'Invalid input, please try again.');
    }
  }

  /// Show a password input prompt (hidden text).
  String password(String prompt) {
    return dcli.ask(prompt, hidden: true);
  }

  /// Show a command preview box before execution.
  void showPreview({
    required String command,
    List<String>? repositories,
    Map<String, String>? details,
  }) {
    print('');
    print('┌─ Command Preview ────────────────────────────');
    print('│');
    print('│  $command');

    if (details != null && details.isNotEmpty) {
      print('│');
      for (final entry in details.entries) {
        print('│  ${entry.key}: ${entry.value}');
      }
    }

    if (repositories != null && repositories.isNotEmpty) {
      print('│');
      print('├─ Repositories ───────────────────────────────');
      for (final repo in repositories.take(5)) {
        print('│    $repo');
      }
      if (repositories.length > 5) {
        print('│    ... and ${repositories.length - 5} more');
      }
    }

    print('│');
    print('└──────────────────────────────────────────────');
    print('');
  }

  /// Show a spinner during a long-running operation.
  ///
  /// Note: DCli doesn't have the same spinner API as interact.
  /// This prints a message instead. Use waitForSpinner for async operations.
  void showSpinner(String message) {
    print('⏳ $message...');
  }

  /// Run a task with a progress indicator.
  Future<T> waitForSpinner<T>(String message, Future<T> Function() task) async {
    stdout.write('⏳ $message...');
    try {
      final result = await task();
      stdout.write('\r✓ $message     \n');
      return result;
    } catch (e) {
      stdout.write('\r✗ $message     \n');
      rethrow;
    }
  }

  /// Show a success message.
  void success(String message) {
    print('✓ $message');
  }

  /// Show an error message.
  void error(String message) {
    print('✗ $message');
  }

  /// Show an info message.
  void info(String message) {
    print('ℹ $message');
  }

  /// Show a warning message.
  void warning(String message) {
    print('⚠ $message');
  }

  /// Show a section header.
  void header(String title) {
    print('');
    print('=== $title ===');
    print('');
  }

  /// Show a sub-header.
  void subHeader(String title) {
    print('');
    print('--- $title ---');
    print('');
  }

  /// Wait for Enter key to continue.
  void waitForEnter([String message = 'Press Enter to continue...']) {
    dcli.ask(message, defaultValue: '');
  }
}
