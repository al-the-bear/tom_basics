/// Help topics for CLI tools.
///
/// Help topics provide documentation sections accessible via
/// `tool help <topic>`. Unlike commands, topics only display text
/// and don't execute anything.
///
/// ## Built-in Topics
///
/// - `placeholders` — Variable substitution in commands and config
///
/// ## Usage
///
/// ```dart
/// final tool = ToolDefinition(
///   name: 'buildkit',
///   helpTopics: [placeholdersHelpTopic],
///   // ...
/// );
/// ```
///
/// Then: `buildkit help placeholders`
library;

/// A named help topic that can be shown via `tool help <name>`.
class HelpTopic {
  /// Topic name (used in `help <name>`).
  final String name;

  /// Short description shown in the topics list.
  final String summary;

  /// Full help text (may include markdown-style formatting).
  final String content;

  const HelpTopic({
    required this.name,
    required this.summary,
    required this.content,
  });

  @override
  String toString() => 'HelpTopic($name)';
}
