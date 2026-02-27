import 'command_definition.dart';
import 'option_definition.dart';
import 'tool_definition.dart';

/// Serializes a [ToolDefinition] tree to YAML format.
///
/// Used by the `--dump-definitions` flag to output all native commands,
/// options, and metadata. The host tool calls this on nested tools to
/// auto-discover their definitions.
///
/// ```dart
/// final yaml = ToolDefinitionSerializer.toYaml(myToolDefinition);
/// print(yaml);
/// ```
class ToolDefinitionSerializer {
  /// Serialize a [ToolDefinition] to YAML string.
  ///
  /// Includes all tool metadata, global options, and command definitions.
  /// Does NOT include commands added via tool wiring — those are the
  /// host tool's concern.
  static String toYaml(ToolDefinition tool) {
    final buf = StringBuffer();

    // Tool metadata
    buf.writeln('name: ${tool.name}');
    buf.writeln('version: ${tool.version}');
    buf.writeln('description: ${_yamlString(tool.description)}');
    buf.writeln('mode: ${_modeToString(tool.mode)}');

    // Features
    buf.writeln('features:');
    buf.writeln('  project_traversal: ${tool.features.projectTraversal}');
    buf.writeln('  git_traversal: ${tool.features.gitTraversal}');
    buf.writeln('  recursive_scan: ${tool.features.recursiveScan}');
    buf.writeln('  interactive_mode: ${tool.features.interactiveMode}');
    buf.writeln('  dry_run: ${tool.features.dryRun}');
    buf.writeln('  json_output: ${tool.features.jsonOutput}');
    buf.writeln('  verbose: ${tool.features.verbose}');

    // Natures
    if (tool.requiredNatures != null && tool.requiredNatures!.isNotEmpty) {
      buf.writeln(
        'required_natures: [${tool.requiredNatures!.map(_typeToString).join(', ')}]',
      );
    }
    if (tool.worksWithNatures.isNotEmpty) {
      buf.writeln(
        'works_with_natures: [${tool.worksWithNatures.map(_typeToString).join(', ')}]',
      );
    }

    // Global options (tool-specific, not the common ones)
    if (tool.globalOptions.isNotEmpty) {
      buf.writeln('global_options:');
      for (final opt in tool.globalOptions) {
        buf.writeln('  - ${_optionToYamlInline(opt)}');
      }
    } else {
      buf.writeln('global_options: []');
    }

    // Commands
    if (tool.commands.isNotEmpty) {
      buf.writeln('commands:');
      for (final cmd in tool.commands) {
        _writeCommand(buf, cmd);
      }
    } else if (tool.mode == ToolMode.singleCommand ||
        tool.mode == ToolMode.hybrid) {
      // For single-command tools, there are no sub-commands
      // but we still output an empty commands section for consistency
      buf.writeln('commands: {}');
    }

    return buf.toString();
  }

  /// Parse YAML output from `--dump-definitions` back into a
  /// [ToolDefinition].
  ///
  /// This is used by the host tool to parse the nested tool's definition
  /// response for wiring purposes.
  static ToolDefinition fromYaml(String yaml) {
    // Use simple line-by-line parsing to avoid yaml package dependency
    // in the serializer itself (the yaml package parses YamlMap, not Map).
    // For a robust implementation, the caller should use the yaml package.
    throw UnimplementedError(
      'Use ToolDefinitionParser.fromYamlMap() with a parsed YAML map instead',
    );
  }

  /// Parse a YAML map (from the `yaml` package) into a [ToolDefinition].
  ///
  /// Used by the wiring loader to parse `--dump-definitions` output.
  static ToolDefinition fromYamlMap(Map<dynamic, dynamic> map) {
    final name = map['name'] as String? ?? '';
    final version = map['version']?.toString() ?? '1.0.0';
    final description = map['description'] as String? ?? '';
    final mode = _modeFromString(map['mode'] as String? ?? 'multi_command');

    // Parse features
    final featMap = map['features'];
    final features = featMap is Map
        ? NavigationFeatures(
            projectTraversal: featMap['project_traversal'] == true,
            gitTraversal: featMap['git_traversal'] == true,
            recursiveScan: featMap['recursive_scan'] == true,
            interactiveMode: featMap['interactive_mode'] == true,
            dryRun: featMap['dry_run'] == true,
            jsonOutput: featMap['json_output'] == true,
            verbose: featMap['verbose'] == true,
          )
        : const NavigationFeatures();

    // Parse global options
    final globalOptsList = map['global_options'];
    final globalOptions = <OptionDefinition>[];
    if (globalOptsList is List) {
      for (final optMap in globalOptsList) {
        if (optMap is Map) {
          globalOptions.add(_optionFromMap(optMap));
        }
      }
    }

    // Parse commands
    final commandsMap = map['commands'];
    final commands = <CommandDefinition>[];
    if (commandsMap is Map) {
      for (final entry in commandsMap.entries) {
        final cmdName = entry.key.toString();
        final cmdMap = entry.value;
        if (cmdMap is Map) {
          commands.add(_commandFromMap(cmdName, cmdMap));
        }
      }
    }

    return ToolDefinition(
      name: name,
      version: version,
      description: description,
      mode: mode,
      features: features,
      globalOptions: globalOptions,
      commands: commands,
    );
  }

  // --- Private helpers ---

  static void _writeCommand(StringBuffer buf, CommandDefinition cmd) {
    buf.writeln('  ${cmd.name}:');
    buf.writeln('    description: ${_yamlString(cmd.description)}');

    if (cmd.aliases.isNotEmpty) {
      buf.writeln('    aliases: [${cmd.aliases.join(', ')}]');
    }

    if (cmd.options.isNotEmpty) {
      buf.writeln('    options:');
      for (final opt in cmd.options) {
        buf.writeln('      - ${_optionToYamlInline(opt)}');
      }
    }

    if (cmd.requiredNatures != null && cmd.requiredNatures!.isNotEmpty) {
      buf.writeln(
        '    required_natures: [${cmd.requiredNatures!.map(_typeToString).join(', ')}]',
      );
    }
    if (cmd.worksWithNatures.isNotEmpty) {
      buf.writeln(
        '    works_with_natures: [${cmd.worksWithNatures.map(_typeToString).join(', ')}]',
      );
    }

    if (cmd.hidden) {
      buf.writeln('    hidden: true');
    }
  }

  static String _optionToYamlInline(OptionDefinition opt) {
    final parts = <String>['name: ${opt.name}'];

    if (opt.abbr != null) {
      parts.add('abbr: ${opt.abbr}');
    }

    parts.add('type: ${_optionTypeToString(opt.type)}');
    parts.add('description: ${_yamlString(opt.description)}');

    if (opt.defaultValue != null) {
      parts.add('default: ${_yamlString(opt.defaultValue!)}');
    }
    if (opt.valueName != null) {
      parts.add('value_name: ${opt.valueName}');
    }
    if (opt.mandatory) {
      parts.add('mandatory: true');
    }
    if (opt.negatable) {
      parts.add('negatable: true');
    }
    if (opt.hidden) {
      parts.add('hidden: true');
    }
    if (opt.allowedValues != null && opt.allowedValues!.isNotEmpty) {
      parts.add('allowed: [${opt.allowedValues!.join(', ')}]');
    }

    return '{ ${parts.join(', ')} }';
  }

  static CommandDefinition _commandFromMap(
    String name,
    Map<dynamic, dynamic> map,
  ) {
    final description = map['description'] as String? ?? '';

    // Aliases
    final aliasesList = map['aliases'];
    final aliases = <String>[];
    if (aliasesList is List) {
      for (final a in aliasesList) {
        aliases.add(a.toString());
      }
    }

    // Options
    final optsList = map['options'];
    final options = <OptionDefinition>[];
    if (optsList is List) {
      for (final optMap in optsList) {
        if (optMap is Map) {
          options.add(_optionFromMap(optMap));
        }
      }
    }

    final hidden = map['hidden'] == true;

    return CommandDefinition(
      name: name,
      description: description,
      aliases: aliases,
      options: options,
      hidden: hidden,
    );
  }

  static OptionDefinition _optionFromMap(Map<dynamic, dynamic> map) {
    final name = map['name'] as String? ?? '';
    final abbr = map['abbr'] as String?;
    final description = map['description'] as String? ?? '';
    final typeStr = map['type'] as String? ?? 'flag';
    final type = _optionTypeFromString(typeStr);
    final defaultValue = map['default']?.toString();
    final valueName = map['value_name'] as String?;
    final mandatory = map['mandatory'] == true;
    final negatable = map['negatable'] == true;
    final hidden = map['hidden'] == true;

    final allowedList = map['allowed'];
    final allowedValues = allowedList is List
        ? allowedList.map((e) => e.toString()).toList()
        : null;

    return OptionDefinition(
      name: name,
      abbr: abbr,
      description: description,
      type: type,
      defaultValue: defaultValue,
      valueName: valueName,
      mandatory: mandatory,
      negatable: negatable,
      hidden: hidden,
      allowedValues: allowedValues,
    );
  }

  static String _modeToString(ToolMode mode) {
    switch (mode) {
      case ToolMode.multiCommand:
        return 'multi_command';
      case ToolMode.singleCommand:
        return 'single_command';
      case ToolMode.hybrid:
        return 'hybrid';
    }
  }

  static ToolMode _modeFromString(String str) {
    switch (str) {
      case 'multi_command':
        return ToolMode.multiCommand;
      case 'single_command':
        return ToolMode.singleCommand;
      case 'hybrid':
        return ToolMode.hybrid;
      default:
        return ToolMode.multiCommand;
    }
  }

  static String _optionTypeToString(OptionType type) {
    switch (type) {
      case OptionType.flag:
        return 'flag';
      case OptionType.option:
        return 'option';
      case OptionType.multiOption:
        return 'multi';
    }
  }

  static OptionType _optionTypeFromString(String str) {
    switch (str) {
      case 'flag':
        return OptionType.flag;
      case 'option':
        return OptionType.option;
      case 'multi':
        return OptionType.multiOption;
      default:
        return OptionType.flag;
    }
  }

  static String _typeToString(Type type) => type.toString();

  /// Escape a string for YAML output.
  ///
  /// Wraps in quotes if the string contains special YAML characters.
  static String _yamlString(String value) {
    if (value.contains(':') ||
        value.contains('#') ||
        value.contains('"') ||
        value.contains("'") ||
        value.contains('\n') ||
        value.startsWith(' ') ||
        value.endsWith(' ') ||
        value.startsWith('{') ||
        value.startsWith('[')) {
      // Use double quotes with escape sequences
      return '"${value.replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';
    }
    return value;
  }
}
