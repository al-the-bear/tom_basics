/// Handles special commands (help, version) before regular argument parsing.
///
/// This module provides utilities to detect and handle `help` and `version`
/// commands that should work without full argument parsing.
library;

import 'help_generator.dart';
import 'help_topic.dart';
import 'tool_definition.dart';
import 'command_definition.dart';

/// Result of checking for special commands.
enum SpecialCommandResult {
  /// No special command found - continue normal processing.
  none,

  /// Special command handled - caller should exit.
  handled,
}

/// Check for and handle special commands (help, version).
///
/// Returns [SpecialCommandResult.handled] if a special command was processed
/// and the caller should exit, or [SpecialCommandResult.none] to continue
/// normal argument processing.
///
/// Supports:
/// - `tool help` - Show tool help
/// - `tool help :command` - Show command help
/// - `tool help command` - Show command help (without colon)
/// - `tool --help` or `tool -h` - Show tool help
/// - `tool version` - Show version
/// - `tool --version` or `tool -V` - Show version
///
/// Parameters:
/// - [args] - Command line arguments
/// - [tool] - Tool definition for generating help
/// - [printer] - Optional custom print function (defaults to [print])
/// - [toolHelpGenerator] - Optional custom function to generate tool help text
/// - [commandHelpGenerator] - Optional custom function to generate command help text
/// - [versionGenerator] - Optional custom function to generate version text
///
/// Example:
/// ```dart
/// Future<void> main(List<String> args) async {
///   if (handleSpecialCommands(args, myTool) == SpecialCommandResult.handled) {
///     return;
///   }
///   // Continue normal processing...
/// }
/// ```
SpecialCommandResult handleSpecialCommands(
  List<String> args,
  ToolDefinition tool, {
  void Function(String)? printer,
  String Function(ToolDefinition)? toolHelpGenerator,
  String Function(ToolDefinition, CommandDefinition)? commandHelpGenerator,
  String Function(ToolDefinition)? versionGenerator,
}) {
  printer ??= print;
  toolHelpGenerator ??= generatePlainToolHelp;
  commandHelpGenerator ??= (t, c) => generatePlainCommandHelp(t, c);
  versionGenerator ??= (t) => '${t.name} v${t.version}';

  if (args.isEmpty) {
    printer(toolHelpGenerator(tool));
    return SpecialCommandResult.handled;
  }

  final first = args.first.toLowerCase();

  // Version command
  if (first == 'version' || first == '--version' || first == '-v') {
    printer(versionGenerator(tool));
    return SpecialCommandResult.handled;
  }

  // Help command
  if (first == 'help' || first == '--help' || first == '-h') {
    if (args.length > 1 && first == 'help') {
      // Command-specific help: help :command or help command or help topic
      final target = args[1];
      final cmdName = target.startsWith(':') ? target.substring(1) : target;
      // Check help topics first (they don't need : prefix)
      final topic = tool.helpTopics.cast<HelpTopic?>().firstWhere(
        (t) => t!.name == cmdName,
        orElse: () => null,
      );
      if (topic != null) {
        printer(HelpGenerator.generateTopicHelp(topic, tool: tool));
      } else {
        _printCommandHelp(tool, cmdName, printer, commandHelpGenerator);
      }
    } else {
      printer(toolHelpGenerator(tool));
    }
    return SpecialCommandResult.handled;
  }

  return SpecialCommandResult.none;
}

/// Print help for a specific command.
void _printCommandHelp(
  ToolDefinition tool,
  String cmdName,
  void Function(String) printer,
  String Function(ToolDefinition, CommandDefinition) commandHelpGenerator,
) {
  // Find the command
  final cmd = tool.commands.cast<CommandDefinition?>().firstWhere(
    (c) => c!.name == cmdName || c.aliases.contains(cmdName),
    orElse: () => null,
  );

  if (cmd == null) {
    final buf = StringBuffer();
    buf.writeln('Unknown command: $cmdName');
    buf.writeln();
    buf.writeln('Available commands:');
    for (final c in tool.visibleCommands) {
      buf.writeln('  :${c.name.padRight(16)} ${c.description}');
    }
    if (tool.helpTopics.isNotEmpty) {
      buf.writeln();
      buf.writeln('Help Topics:');
      for (final topic in tool.helpTopics) {
        buf.writeln('  ${topic.name.padRight(16)} ${topic.summary}');
      }
    }
    printer(buf.toString());
    return;
  }

  printer(commandHelpGenerator(tool, cmd));
}

/// Generate plain-text help for a command (no ANSI colors).
///
/// This is useful for tools that want to display help without
/// using the markdown-style formatting of [HelpGenerator].
String generatePlainCommandHelp(ToolDefinition tool, CommandDefinition cmd) {
  final buf = StringBuffer();

  buf.writeln('${tool.name} v${tool.version}');
  buf.writeln();
  buf.writeln('Command: :${cmd.name}');
  if (cmd.aliases.isNotEmpty) {
    buf.writeln('Aliases: ${cmd.aliases.map((a) => ':$a').join(', ')}');
  }
  buf.writeln();
  buf.writeln(cmd.description);
  buf.writeln();

  // Command-specific options
  if (cmd.options.isNotEmpty) {
    buf.writeln('Options:');
    for (final opt in cmd.options) {
      final abbr = opt.abbr != null ? '-${opt.abbr}, ' : '    ';
      final name = '--${opt.name}';
      final valuePart = opt.valueName != null ? '=<${opt.valueName}>' : '';
      buf.writeln('  $abbr$name$valuePart');
      buf.writeln('      ${opt.description}');
      if (opt.defaultValue != null) {
        buf.writeln('      (default: ${opt.defaultValue})');
      }
    }
    buf.writeln();
  }

  // Examples
  if (cmd.examples.isNotEmpty) {
    buf.writeln('Examples:');
    for (final ex in cmd.examples) {
      buf.writeln('  $ex');
    }
    buf.writeln();
  }

  // Traversal info
  if (cmd.supportsProjectTraversal || cmd.supportsGitTraversal) {
    buf.writeln('Traversal:');
    if (cmd.supportsProjectTraversal) {
      buf.writeln('  Supports --project, --exclude-project filters');
    }
    if (cmd.supportsGitTraversal) {
      buf.writeln('  Supports --inner-first-git, --outer-first-git traversal');
    }
    buf.writeln();
  }

  return buf.toString();
}

/// Generate plain-text tool help (no ANSI colors).
///
/// This provides a simpler alternative to [HelpGenerator.generateToolHelp]
/// without markdown styling.
String generatePlainToolHelp(ToolDefinition tool) {
  final buf = StringBuffer();

  buf.writeln('${tool.name} v${tool.version} - ${tool.description}');
  buf.writeln();
  buf.writeln('Usage: ${tool.name} [options] <pipeline|:command> [args...]');
  buf.writeln();

  // Commands by category
  final buildCmds = <CommandDefinition>[];
  final gitCmds = <CommandDefinition>[];
  final otherCmds = <CommandDefinition>[];

  for (final cmd in tool.visibleCommands) {
    if (cmd.name.startsWith('git')) {
      gitCmds.add(cmd);
    } else if ([
      'versioner',
      'bumpversion',
      'compiler',
      'runner',
      'cleanup',
      'dependencies',
      'publisher',
      'buildsorter',
      'pubget',
      'pubgetall',
      'pubupdate',
      'pubupdateall',
    ].contains(cmd.name)) {
      buildCmds.add(cmd);
    } else {
      otherCmds.add(cmd);
    }
  }

  if (buildCmds.isNotEmpty) {
    buf.writeln('Build Commands:');
    for (final cmd in buildCmds) {
      buf.writeln('  :${cmd.name.padRight(16)} ${cmd.description}');
    }
    buf.writeln();
  }

  if (gitCmds.isNotEmpty) {
    buf.writeln('Git Commands:');
    for (final cmd in gitCmds) {
      buf.writeln('  :${cmd.name.padRight(16)} ${cmd.description}');
    }
    buf.writeln();
  }

  if (otherCmds.isNotEmpty) {
    buf.writeln('Other Commands:');
    for (final cmd in otherCmds) {
      buf.writeln('  :${cmd.name.padRight(16)} ${cmd.description}');
    }
    buf.writeln();
  }

  // Help footer hint
  buf.writeln(
    'Use "${tool.name} help :command" for detailed help on a specific command.',
  );
  buf.writeln();

  // Help topics
  if (tool.helpTopics.isNotEmpty) {
    buf.writeln('Help Topics:');
    for (final topic in tool.helpTopics) {
      buf.writeln('  ${topic.name.padRight(20)} ${topic.summary}');
    }
    buf.writeln();
    buf.writeln('Use "${tool.name} help <topic>" for detailed information.');
    buf.writeln();
  }

  // Footer from tool definition
  if (tool.helpFooter != null) {
    buf.writeln(tool.helpFooter!);
  }

  return buf.toString();
}
