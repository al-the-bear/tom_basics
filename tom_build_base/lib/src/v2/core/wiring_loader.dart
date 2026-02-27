import 'dart:io';

import 'package:yaml/yaml.dart';

import 'binary_helpers.dart';
import 'command_definition.dart';
import 'nested_tool_executor.dart';
import 'tool_definition.dart';
import 'tool_definition_serializer.dart';
import 'tool_wiring_entry.dart';

/// Result of loading and resolving wired tool definitions.
///
/// Contains the dynamically-created [CommandDefinition]s and
/// [NestedToolExecutor]s for nested commands, ready to be merged
/// into the host tool's command + executor maps.
class WiringResult {
  /// New command definitions for wired commands.
  final List<CommandDefinition> commands;

  /// Executors keyed by host command name.
  final Map<String, NestedToolExecutor> executors;

  /// Warnings (e.g., missing binaries in help mode).
  final List<String> warnings;

  /// Errors (e.g., missing binaries in execution mode).
  final List<String> errors;

  const WiringResult({
    this.commands = const [],
    this.executors = const {},
    this.warnings = const [],
    this.errors = const [],
  });

  /// Whether any errors were encountered.
  bool get hasErrors => errors.isNotEmpty;
}

/// Loads and resolves nested tool wiring for a host tool.
///
/// Merges code-level `defaultIncludes` with YAML `nested_tools:` entries,
/// then lazily queries only the nested tools needed for the current
/// invocation via `--dump-definitions`.
///
/// ```dart
/// final loader = WiringLoader(tool: buildkitTool);
/// final result = await loader.resolve(
///   requestedCommands: {'cleanup', 'buildkittest'},
///   workspaceRoot: '/path/to/workspace',
/// );
/// ```
class WiringLoader {
  /// The host tool definition.
  final ToolDefinition tool;

  /// Effective wiring entries after merging code + YAML.
  ///
  /// Populated after [mergeWiringSources] is called.
  late final Map<String, ToolWiringEntry> _effectiveWiring;

  /// Map from host command name → wiring entry that owns it.
  late final Map<String, ToolWiringEntry> _commandToWiring;

  WiringLoader({required this.tool});

  /// Resolve nested tool wiring for the given context.
  ///
  /// [requestedCommands] — commands the user is invoking. Only nested
  /// tools providing these commands will be queried. Pass null to wire
  /// all tools (e.g., in help mode).
  ///
  /// [workspaceRoot] — workspace root for finding the wiring YAML file.
  ///
  /// [tolerateMissing] — if true, missing binaries produce warnings
  /// instead of errors (used in help mode).
  Future<WiringResult> resolve({
    Set<String>? requestedCommands,
    required String workspaceRoot,
    bool tolerateMissing = false,
  }) async {
    // Step 1: Merge wiring sources
    mergeWiringSources(workspaceRoot: workspaceRoot);

    if (_effectiveWiring.isEmpty) {
      return const WiringResult();
    }

    // Step 2: Determine which tools need querying
    final neededTools = <String, ToolWiringEntry>{};
    if (requestedCommands == null) {
      // Help mode: wire all tools
      neededTools.addAll(_effectiveWiring);
    } else {
      for (final cmdName in requestedCommands) {
        final wiring = _commandToWiring[cmdName];
        if (wiring != null) {
          neededTools[wiring.binary] = wiring;
        }
      }
    }

    if (neededTools.isEmpty) {
      return const WiringResult();
    }

    // Step 3: Query each needed tool
    final commands = <CommandDefinition>[];
    final executors = <String, NestedToolExecutor>{};
    final warnings = <String>[];
    final errors = <String>[];

    for (final entry in neededTools.entries) {
      final binary = entry.key;
      final wiring = entry.value;
      final resolved = resolveBinary(binary);

      // Check binary exists
      if (!isBinaryOnPath(resolved)) {
        final msg =
            ':${wiring.hostCommandNames.join(', :')} '
            '— binary $resolved not found';
        if (tolerateMissing) {
          warnings.add(msg);
          // Add placeholder commands for help display
          _addUnavailableCommands(
            commands, wiring, 'binary $binary not found');
          continue;
        } else {
          errors.add(msg);
          continue;
        }
      }

      // Run --dump-definitions
      final dumpResult = await _queryDumpDefinitions(binary, workspaceRoot);
      if (dumpResult == null) {
        final msg = 'Failed to query $binary --dump-definitions';
        if (tolerateMissing) {
          warnings.add(msg);
          continue;
        } else {
          errors.add(msg);
          continue;
        }
      }

      // Build commands and executors from dump
      _buildFromDump(wiring, dumpResult, commands, executors);
    }

    return WiringResult(
      commands: commands,
      executors: executors,
      warnings: warnings,
      errors: errors,
    );
  }

  /// Merge code-level [ToolDefinition.defaultIncludes] with YAML
  /// `nested_tools:` entries.
  ///
  /// YAML entries override code entries for the same binary.
  /// Updates [_effectiveWiring] and [_commandToWiring].
  void mergeWiringSources({required String workspaceRoot}) {
    _effectiveWiring = {};
    _commandToWiring = {};

    // Start with code-level defaults
    if (tool.defaultIncludes != null) {
      for (final entry in tool.defaultIncludes!) {
        _effectiveWiring[entry.binary] = entry;
      }
    }

    // Overlay YAML entries (wins on conflict)
    final yamlEntries = _loadYamlWiring(workspaceRoot);
    for (final entry in yamlEntries.entries) {
      _effectiveWiring[entry.key] = entry.value;
    }

    // Build command → wiring lookup
    for (final entry in _effectiveWiring.values) {
      for (final cmdName in entry.hostCommandNames) {
        _commandToWiring[cmdName] = entry;
      }
    }
  }

  /// Load `nested_tools:` section from the wiring YAML file.
  Map<String, ToolWiringEntry> _loadYamlWiring(String workspaceRoot) {
    if (tool.wiringFile == null) return {};

    final fileName = tool.wiringFile!.isEmpty
        ? '${tool.name}_master.yaml'
        : tool.wiringFile!;

    final file = File('$workspaceRoot/$fileName');
    if (!file.existsSync()) return {};

    try {
      final content = file.readAsStringSync();
      final yaml = loadYaml(content);
      if (yaml is! YamlMap) return {};

      final nestedTools = yaml['nested_tools'];
      if (nestedTools is! YamlMap) return {};

      return _parseNestedToolsYaml(nestedTools);
    } catch (_) {
      return {};
    }
  }

  /// Parse `nested_tools:` YAML section into wiring entries.
  Map<String, ToolWiringEntry> _parseNestedToolsYaml(YamlMap nestedTools) {
    final result = <String, ToolWiringEntry>{};

    for (final entry in nestedTools.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is! YamlMap) continue;

      final binary = value['binary'] as String? ?? key;
      final modeStr = value['mode'] as String? ?? 'standalone';
      final mode = modeStr == 'multi_command'
          ? WiringMode.multiCommand
          : WiringMode.standalone;

      Map<String, String>? commands;
      final cmdsMap = value['commands'];
      if (cmdsMap is YamlMap) {
        commands = {};
        for (final cmd in cmdsMap.entries) {
          commands[cmd.key.toString()] = cmd.value.toString();
        }
      }

      result[binary] = ToolWiringEntry(
        binary: binary,
        mode: mode,
        commands: commands,
      );
    }

    return result;
  }

  /// Query a tool's `--dump-definitions` and parse the result.
  Future<ToolDefinition?> _queryDumpDefinitions(
    String binary,
    String workingDirectory,
  ) async {
    try {
      final result = await runBinary(binary, [
        '--dump-definitions',
      ], workingDirectory);
      if (result.exitCode != 0) return null;

      final output = result.stdout.toString().trim();
      if (output.isEmpty) return null;

      final yaml = loadYaml(output);
      if (yaml is! YamlMap) return null;

      return ToolDefinitionSerializer.fromYamlMap(yaml);
    } catch (_) {
      return null;
    }
  }

  /// Build [CommandDefinition]s and [NestedToolExecutor]s from a dump result.
  void _buildFromDump(
    ToolWiringEntry wiring,
    ToolDefinition dumpResult,
    List<CommandDefinition> commands,
    Map<String, NestedToolExecutor> executors,
  ) {
    if (wiring.mode == WiringMode.standalone) {
      // Standalone tool: one host command = binary name
      final hostName = wiring.hostCommandNames.isNotEmpty
          ? wiring.hostCommandNames.first
          : wiring.binary;

      commands.add(
        CommandDefinition(
          name: hostName,
          description: '${dumpResult.description} (via ${wiring.binary})',
        ),
      );

      executors[hostName] = NestedToolExecutor(
        binary: wiring.binary,
        hostCommandName: hostName,
        isStandalone: true,
      );
    } else {
      // Multi-command tool: create one host command per mapping
      final mapping = wiring.commands ?? {};
      for (final entry in mapping.entries) {
        final hostName = entry.key;
        final nestedName = entry.value;

        // Find the nested command in the dump
        final nestedCmd = dumpResult.findCommand(nestedName);
        final description = nestedCmd != null
            ? '${nestedCmd.description} (via ${wiring.binary})'
            : '$nestedName (via ${wiring.binary})';

        // Build command options from the nested command's options
        final options = nestedCmd?.options ?? [];

        commands.add(
          CommandDefinition(
            name: hostName,
            description: description,
            options: options,
            worksWithNatures: nestedCmd?.worksWithNatures ?? {},
            requiredNatures: nestedCmd?.requiredNatures,
          ),
        );

        executors[hostName] = NestedToolExecutor(
          binary: wiring.binary,
          hostCommandName: hostName,
          nestedCommand: nestedName,
        );
      }
    }
  }

  /// Add placeholder commands for tools whose binary is unavailable.
  void _addUnavailableCommands(
    List<CommandDefinition> commands,
    ToolWiringEntry wiring,
    String reason,
  ) {
    for (final cmdName in wiring.hostCommandNames) {
      commands.add(CommandDefinition(name: cmdName, description: '[$reason]'));
    }
  }
}
