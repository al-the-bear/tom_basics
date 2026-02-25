import 'help_topic.dart';
import 'option_definition.dart';
import 'command_definition.dart';
import 'tool_definition.dart';

/// Generates help text from tool and command definitions.
///
/// Produces markdown-styled help output that can be rendered
/// by console_markdown for ANSI-colored terminal output.
class HelpGenerator {
  /// Generate tool-level help text.
  ///
  /// Shows tool description, usage, global options, and available commands.
  static String generateToolHelp(ToolDefinition tool) {
    final buf = StringBuffer();

    // Header
    buf.writeln('**${tool.name}** v${tool.version}');
    buf.writeln();
    buf.writeln(tool.description);
    buf.writeln();

    // Usage
    buf.writeln('<cyan>**Usage**</cyan>');
    if (tool.mode == ToolMode.multiCommand) {
      buf.writeln('  ${tool.name} [global-options] :command [command-options]');
    } else {
      buf.writeln('  ${tool.name} [options]');
    }
    buf.writeln();

    // Global options
    if (tool.allGlobalOptions.isNotEmpty) {
      buf.writeln('<yellow>**Global Options**</yellow>');
      _writeOptions(buf, tool.allGlobalOptions);
      buf.writeln();
    }

    // Commands
    if (tool.commands.isNotEmpty) {
      buf.writeln('<green>**Commands**</green>');
      for (final cmd in tool.visibleCommands) {
        final aliasStr = cmd.aliases.isNotEmpty
            ? ' (${cmd.aliases.join(', ')})'
            : '';
        buf.writeln('  :${cmd.name}$aliasStr');
        buf.writeln('      ${cmd.description}');
      }
      buf.writeln();
      buf.writeln(
        '  Use `${tool.name} :command --help` for command-specific help.',
      );
      buf.writeln();
    }

    // Help topics
    if (tool.helpTopics.isNotEmpty) {
      buf.writeln('<magenta>**Help Topics**</magenta>');
      for (final topic in tool.helpTopics) {
        buf.writeln('  ${topic.name.padRight(20)} ${topic.summary}');
      }
      buf.writeln();
      buf.writeln(
        '  Use `${tool.name} help <topic>` for detailed information.',
      );
      buf.writeln();
    }

    // Footer
    if (tool.helpFooter != null) {
      buf.writeln(tool.helpFooter!);
    }

    return buf.toString();
  }

  /// Generate command-level help text.
  ///
  /// Shows command description, usage, and all options including
  /// inherited traversal options.
  static String generateCommandHelp(
    CommandDefinition command, {
    ToolDefinition? tool,
  }) {
    final buf = StringBuffer();
    final toolName = tool?.name ?? 'tool';

    // Header
    buf.writeln('**:${command.name}**');
    if (command.aliases.isNotEmpty) {
      buf.writeln('Aliases: ${command.aliases.map((a) => ':$a').join(', ')}');
    }
    buf.writeln();
    buf.writeln(command.description);
    buf.writeln();

    // Usage
    buf.writeln('<cyan>**Usage**</cyan>');
    buf.writeln('  $toolName [global-options] :${command.name} [options]');
    buf.writeln();

    // Command options
    if (command.options.isNotEmpty) {
      buf.writeln('<yellow>**Command Options**</yellow>');
      _writeOptions(buf, command.options);
      buf.writeln();
    }

    // Traversal options
    if (command.supportsProjectTraversal) {
      buf.writeln('<yellow>**Project Traversal Options**</yellow>');
      _writeOptions(buf, projectTraversalOptions);
      buf.writeln();
    }

    if (command.supportsGitTraversal) {
      buf.writeln('<yellow>**Git Traversal Options**</yellow>');
      _writeOptions(buf, gitTraversalOptions);
      buf.writeln();
    }

    // Per-command filters
    if (command.supportsPerCommandFilter) {
      buf.writeln(
        '<dim>This command supports per-command --project and --exclude filters.</dim>',
      );
      buf.writeln();
    }

    // Nature requirements
    if (command.requiredNatures != null &&
        command.requiredNatures!.isNotEmpty) {
      buf.writeln(
        '<dim>Requires: ${command.requiredNatures!.map(_natureName).join(', ')}</dim>',
      );
      buf.writeln();
    }

    // Common meta-options
    buf.writeln('<dim>**Common Options**</dim>');
    buf.writeln('  -h, --help                  Show this help');
    buf.writeln('  -v, --verbose               Verbose output');
    buf.writeln('  -n, --dry-run               Show what would be done');
    buf.writeln();

    // Examples
    if (command.examples.isNotEmpty) {
      buf.writeln('<green>**Examples**</green>');
      for (final example in command.examples) {
        buf.writeln('  $example');
      }
      buf.writeln();
    }

    return buf.toString();
  }

  /// Generate help text for a help topic.
  static String generateTopicHelp(HelpTopic topic, {ToolDefinition? tool}) {
    final buf = StringBuffer();
    if (tool != null) {
      buf.writeln('**${tool.name}** v${tool.version}');
      buf.writeln();
    }
    buf.write(topic.content);
    return buf.toString();
  }

  /// Generate a short usage summary for error messages.
  static String generateUsageSummary(ToolDefinition tool) {
    final buf = StringBuffer();
    buf.writeln('Usage: ${tool.name} [options]');
    if (tool.mode == ToolMode.multiCommand && tool.commands.isNotEmpty) {
      final cmdNames = tool.visibleCommands
          .take(5)
          .map((c) => ':${c.name}')
          .join(', ');
      buf.writeln(
        'Commands: $cmdNames${tool.visibleCommands.length > 5 ? '...' : ''}',
      );
    }
    buf.writeln();
    buf.writeln('Use --help for more information.');
    return buf.toString();
  }

  /// Generate option help for a single option.
  static String generateOptionHelp(OptionDefinition option) {
    final buf = StringBuffer();
    buf.write('  ');

    // Short form
    if (option.abbr != null) {
      buf.write('-${option.abbr}');
      if (option.type != OptionType.flag) {
        buf.write(' <${option.valueName ?? 'value'}>');
      }
      buf.write(', ');
    }

    // Long form
    buf.write('--${option.name}');
    if (option.type != OptionType.flag) {
      buf.write('=<${option.valueName ?? 'value'}>');
    }

    // Description
    buf.writeln();
    buf.write('      ${option.description}');

    // Default value
    if (option.defaultValue != null) {
      buf.write(' (default: ${option.defaultValue})');
    }

    buf.writeln();
    return buf.toString();
  }

  /// Write options in formatted help style.
  static void _writeOptions(StringBuffer buf, List<OptionDefinition> options) {
    for (final opt in options) {
      final shortPart = opt.abbr != null ? '-${opt.abbr}, ' : '    ';
      final longPart = '--${opt.name}';

      final valuePart = opt.type != OptionType.flag
          ? '=<${opt.valueName ?? 'value'}>'
          : '';

      final optStr = '$shortPart$longPart$valuePart';
      buf.write('  ${optStr.padRight(28)}');
      buf.writeln(opt.description);

      if (opt.defaultValue != null) {
        buf.writeln('${' ' * 30}Default: ${opt.defaultValue}');
      }
    }
  }

  /// Get human-readable name for a nature type.
  static String _natureName(Type type) {
    final name = type.toString();
    // Convert DartProjectFolder -> Dart Project
    return name
        .replaceAll('Folder', '')
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)}')
        .trim();
  }
}

/// ANSI color codes for terminal output.
///
/// These can be embedded in help text for direct rendering,
/// or stripped for plain-text output.
class AnsiColors {
  static const reset = '\x1B[0m';
  static const bold = '\x1B[1m';
  static const dim = '\x1B[2m';
  static const red = '\x1B[31m';
  static const green = '\x1B[32m';
  static const yellow = '\x1B[33m';
  static const blue = '\x1B[34m';
  static const magenta = '\x1B[35m';
  static const cyan = '\x1B[36m';
  static const white = '\x1B[37m';

  const AnsiColors._();

  /// Wrap text with a color code.
  static String wrap(String text, String color) => '$color$text$reset';

  /// Strip all ANSI codes from text.
  static String strip(String text) {
    return text.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
  }
}
