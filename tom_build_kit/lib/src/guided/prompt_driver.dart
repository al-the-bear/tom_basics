/// Input abstraction for guided mode.
///
/// [GuidedMode] renders menus, confirmations and text prompts through a
/// [PromptDriver] rather than calling the terminal directly. This decouples
/// the guided-flow *logic* (menu → choice → command) from the *I/O* (reading
/// the TTY), so flows can be driven by a real terminal in production and by a
/// scripted list of answers in tests.
///
/// Two implementations are provided:
/// - [DcliPromptDriver] — the real terminal driver (used by default).
/// - [ScriptedPromptDriver] — a test double that replays pre-seeded answers.
library;

import 'package:dcli/dcli.dart' as dcli;

/// Raw interactive-prompt primitives used by [GuidedMode].
///
/// Kept intentionally small: everything guided mode needs can be expressed as a
/// single-choice menu, a yes/no confirmation, or a line of text input.
abstract class PromptDriver {
  /// Present [options] under [prompt] and return the chosen option string.
  ///
  /// [defaultOption] is pre-selected when the user just presses Enter.
  String menu(
    String prompt, {
    required List<String> options,
    String? defaultOption,
  });

  /// Ask a yes/no question, returning `true` for yes.
  bool confirm(String prompt, {bool defaultValue = true});

  /// Read a line of text. Returns [defaultValue] on empty input when set.
  ///
  /// When [hidden] is true the input is not echoed (password entry).
  String ask(String prompt, {String? defaultValue, bool hidden = false});
}

/// [PromptDriver] backed by the `dcli` package (real terminal I/O).
class DcliPromptDriver implements PromptDriver {
  /// Creates a driver that reads from and writes to the process terminal.
  const DcliPromptDriver();

  @override
  String menu(
    String prompt, {
    required List<String> options,
    String? defaultOption,
  }) =>
      dcli.menu(prompt, options: options, defaultOption: defaultOption);

  @override
  bool confirm(String prompt, {bool defaultValue = true}) =>
      dcli.confirm(prompt, defaultValue: defaultValue);

  @override
  String ask(String prompt, {String? defaultValue, bool hidden = false}) =>
      dcli.ask(prompt, defaultValue: defaultValue, hidden: hidden);
}

/// [PromptDriver] that replays a fixed list of [answers] for tests.
///
/// Answers are consumed in order, one per prompt:
/// - **menu** — an answer that parses as an integer is treated as a **1-based
///   index** into the presented options (robust to label decoration); any other
///   answer must match an option label exactly.
/// - **confirm** — `y`/`yes`/`true` → true, `n`/`no`/`false` → false, empty →
///   the prompt's default.
/// - **ask** — returned verbatim; an empty answer yields the prompt's default
///   when one is provided.
///
/// Running out of scripted answers throws a [StateError] so a mis-scripted test
/// fails loudly instead of hanging on real input.
class ScriptedPromptDriver implements PromptDriver {
  /// Creates a driver that replays [answers] in order.
  ScriptedPromptDriver(List<String> answers) : _answers = List.of(answers);

  final List<String> _answers;
  int _cursor = 0;

  /// Number of scripted answers not yet consumed.
  int get remaining => _answers.length - _cursor;

  String _next(String context) {
    if (_cursor >= _answers.length) {
      throw StateError(
        'ScriptedPromptDriver ran out of answers (needed one for $context)',
      );
    }
    return _answers[_cursor++];
  }

  @override
  String menu(
    String prompt, {
    required List<String> options,
    String? defaultOption,
  }) {
    final answer = _next('menu "$prompt"');
    final index = int.tryParse(answer.trim());
    if (index != null) {
      if (index < 1 || index > options.length) {
        throw StateError(
          'Scripted menu index $index is out of range 1..${options.length} '
          'for "$prompt"',
        );
      }
      return options[index - 1];
    }
    if (!options.contains(answer)) {
      throw StateError(
        'Scripted menu answer "$answer" is not one of the options for '
        '"$prompt"',
      );
    }
    return answer;
  }

  @override
  bool confirm(String prompt, {bool defaultValue = true}) {
    final answer = _next('confirm "$prompt"').trim().toLowerCase();
    if (answer.isEmpty) return defaultValue;
    return answer == 'y' || answer == 'yes' || answer == 'true';
  }

  @override
  String ask(String prompt, {String? defaultValue, bool hidden = false}) {
    final answer = _next('ask "$prompt"');
    if (answer.isEmpty && defaultValue != null) return defaultValue;
    return answer;
  }
}
