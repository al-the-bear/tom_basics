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
  /// the host command name defaults to the binary name.
  final Map<String, String>? commands;

  const ToolWiringEntry({
    required this.binary,
    required this.mode,
    this.commands,
  });

  /// Whether this entry has any command mappings.
  bool get hasCommands => commands != null && commands!.isNotEmpty;

  /// All host command names defined by this wiring entry.
  ///
  /// For multi-command tools, returns the keys of [commands].
  /// For standalone tools, returns a single-element set with the [binary] name.
  Set<String> get hostCommandNames {
    if (mode == WiringMode.standalone) {
      return {binary};
    }
    return commands?.keys.toSet() ?? {};
  }

  @override
  String toString() =>
      'ToolWiringEntry($binary, $mode'
      '${hasCommands ? ', commands: $commands' : ''})';
}
