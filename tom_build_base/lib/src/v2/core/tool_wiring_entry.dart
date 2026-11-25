/// Mode for how a nested tool is wired into a host tool.
enum WiringMode {
  /// Multi-command tool (supports :command syntax).
  ///
  /// Requires [ToolWiringEntry.commands] to specify the command mapping.
  multiCommand,

  /// Standalone (single-command) tool.
  ///
  /// The host command name defaults to the wiring entry key
  /// (or the binary name if no key override).
  standalone,
}

/// Describes how a nested tool is wired into a host tool.
///
/// Binary names are platform-independent — `.exe` is appended
/// automatically on Windows at resolution time.
///
/// ```dart
/// const testkit = ToolWiringEntry(
///   binary: 'testkit',
///   mode: WiringMode.multiCommand,
///   commands: {
///     'buildkittest': 'test',
///     'buildkitbaseline': 'baseline',
///   },
/// );
///
/// const astgen = ToolWiringEntry(
///   binary: 'astgen',
///   mode: WiringMode.standalone,
/// );
/// ```
class ToolWiringEntry {
  /// Binary name (without platform extension).
  ///
  /// The `.exe` suffix is appended automatically on Windows at every
  /// resolution point (validation, dump-definitions calls, execution).
  final String binary;

  /// Whether this is a multi-command or standalone tool.
  final WiringMode mode;

  /// Command mapping: `{ hostName: nestedName }`.
  ///
  /// Required for [WiringMode.multiCommand] tools. Maps the host tool's
  /// command name to the nested tool's command name.
  ///
  /// For [WiringMode.standalone] tools, this should be null or empty —
  /// the host command is [name].
  final Map<String, String>? commands;

  /// The host command of a [WiringMode.standalone] tool: in
  /// `nested_tools:` the entry's YAML key, so `d4rtgen: {binary:
  /// /opt/x/d4rtgen}` is `:d4rtgen`. Null: the base name of [binary]
  /// (without its folder and a `.exe`), which is what a code-level
  /// `defaultIncludes` entry such as `binary: 'astgen'` gives.
  final String? name;

  const ToolWiringEntry({
    required this.binary,
    required this.mode,
    this.commands,
    this.name,
  });

  /// The base name of [binary]: without its folder (after the last slash or
  /// backslash) and a trailing `.exe`.
  String get binaryBaseName {
    final last = binary.split(RegExp(r'[/\\]')).last;
    return last.toLowerCase().endsWith('.exe')
        ? last.substring(0, last.length - 4)
        : last;
  }

  /// What identifies the entry when code-level defaults and YAML entries are
  /// merged (a YAML entry replaces the code entry of the same key): a
  /// standalone tool's host command, a multi-command tool's binary.
  String get key =>
      mode == WiringMode.standalone ? (name ?? binaryBaseName) : binary;

  /// Whether this entry has any command mappings.
  bool get hasCommands => commands != null && commands!.isNotEmpty;

  /// All host command names defined by this wiring entry.
  ///
  /// For multi-command tools, returns the keys of [commands].
  /// For standalone tools, returns a single-element set with [name], else the
  /// base name of [binary].
  Set<String> get hostCommandNames {
    if (mode == WiringMode.standalone) {
      return {name ?? binaryBaseName};
    }
    return commands?.keys.toSet() ?? {};
  }

  @override
  String toString() =>
      'ToolWiringEntry($binary, $mode'
      '${name != null ? ', name: $name' : ''}'
      '${hasCommands ? ', commands: $commands' : ''})';
}
