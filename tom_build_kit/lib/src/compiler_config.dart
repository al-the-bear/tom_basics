/// Configuration types for the compiler tool.
///
/// These are pure data classes used by both the CLI tool (CompilerTool)
/// and the build.yaml configuration parser. They have no dependency on
/// `package:build` or build_runner.
library;

/// Configuration for a command section (precompile, postcompile).
class CommandSection {
  /// Command line templates with placeholders.
  /// Used when `commandline:` is specified — runs as shell commands.
  final List<String> commandlines;

  /// Built-in command references.
  /// Used when `command:` is specified — dispatches to built-in tools.
  final List<String> commands;

  /// Pipeline commands in global pipeline syntax.
  /// Used when `pipeline:` is specified — follows global pipelines format.
  final List<String> pipeline;

  /// Whether this section uses built-in commands (true) or shell (false).
  final bool isBuiltinCommand;

  /// Platforms where these commands RUN (current platform filter).
  final List<String> platforms;

  CommandSection({
    required this.commandlines,
    this.commands = const [],
    this.pipeline = const [],
    this.isBuiltinCommand = false,
    List<String>? platforms,
  }) : platforms = platforms ?? [];

  /// Returns the command templates to execute.
  /// Prefers pipeline > commands > commandlines.
  List<String> get pipelineCommands =>
      pipeline.isNotEmpty ? pipeline : (commands.isNotEmpty ? commands : commandlines);

  /// Parse from JSON/YAML structure.
  ///
  /// Supports three mutually exclusive keys:
  /// - `pipeline:` — global pipeline syntax (preferred)
  /// - `commandline:` — shell command templates (legacy)
  /// - `command:` — built-in tool references (e.g., "versioner --output ...")
  factory CommandSection.fromJson(dynamic json) {
    if (json is! Map) {
      throw ArgumentError('CommandSection must be a map');
    }

    final pipelineRaw = json['pipeline'];
    final commandlineRaw = json['commandline'];
    final commandRaw = json['command'];

    final keyCount = [pipelineRaw, commandlineRaw, commandRaw]
        .where((k) => k != null)
        .length;
    if (keyCount > 1) {
      throw ArgumentError(
          'CommandSection cannot have multiple of "pipeline", "commandline", and "command"');
    }

    final platformsRaw = json['platforms'];
    List<String>? platforms;
    if (platformsRaw is String) {
      platforms = [platformsRaw];
    } else if (platformsRaw is List) {
      platforms = platformsRaw.map((e) => e.toString()).toList();
    }

    if (pipelineRaw != null) {
      // Pipeline mode (global pipeline syntax)
      List<String> pipeline;
      if (pipelineRaw is String) {
        pipeline = [pipelineRaw];
      } else if (pipelineRaw is List) {
        pipeline = pipelineRaw.map((e) => e.toString()).toList();
      } else {
        throw ArgumentError('pipeline must be a string or list');
      }
      if (pipeline.isEmpty) {
        throw ArgumentError('pipeline cannot be empty');
      }

      return CommandSection(
        commandlines: [],
        pipeline: pipeline,
        platforms: platforms,
      );
    }

    if (commandRaw != null) {
      // Built-in command mode
      List<String> commands;
      if (commandRaw is String) {
        commands = [commandRaw];
      } else if (commandRaw is List) {
        commands = commandRaw.map((e) => e.toString()).toList();
      } else {
        throw ArgumentError('command must be a string or list');
      }
      if (commands.isEmpty) {
        throw ArgumentError('command cannot be empty');
      }

      return CommandSection(
        commandlines: [],
        commands: commands,
        isBuiltinCommand: true,
        platforms: platforms,
      );
    }

    // Shell commandline mode (original behavior)
    List<String> commandlines;
    if (commandlineRaw is String) {
      commandlines = [commandlineRaw];
    } else if (commandlineRaw is List) {
      commandlines = commandlineRaw.map((e) => e.toString()).toList();
    } else {
      throw ArgumentError('pipeline, commandline, or command must be specified');
    }

    if (commandlines.isEmpty) {
      throw ArgumentError('commandline cannot be empty');
    }

    return CommandSection(
      commandlines: commandlines,
      platforms: platforms,
    );
  }
}

/// Configuration for a single compilation section.
class CompileSection {
  /// Command line templates with placeholders.
  /// Used when `commandline:` is specified — runs as shell commands.
  final List<String> commandlines;

  /// Built-in command references.
  /// Used when `command:` is specified — dispatches to built-in tools.
  final List<String> commands;

  /// Pipeline commands in global pipeline syntax.
  /// Used when `pipeline:` is specified — follows global pipelines format.
  final List<String> pipeline;

  /// Whether this section uses built-in commands (true) or shell (false).
  final bool isBuiltinCommand;

  /// List of source files to compile.
  final List<String> files;

  /// Target platforms to compile FOR (cross-compilation targets).
  final List<String> targets;

  /// Platforms where this compilation RUNS (current platform filter).
  final List<String> platforms;

  CompileSection({
    required this.commandlines,
    this.commands = const [],
    this.pipeline = const [],
    this.isBuiltinCommand = false,
    required this.files,
    List<String>? targets,
    List<String>? platforms,
  })  : targets = targets ?? [],
        platforms = platforms ?? [];

  /// Returns the command templates to execute.
  /// Prefers pipeline > commands > commandlines.
  List<String> get pipelineCommands =>
      pipeline.isNotEmpty ? pipeline : (commands.isNotEmpty ? commands : commandlines);

  /// Parse from JSON/YAML structure.
  ///
  /// Supports three mutually exclusive keys:
  /// - `pipeline:` — global pipeline syntax (preferred)
  /// - `commandline:` — shell command templates (legacy)
  /// - `command:` — built-in tool references (e.g., "compiler --targets ...")
  factory CompileSection.fromJson(dynamic json) {
    if (json is! Map) {
      throw ArgumentError('CompileSection must be a map');
    }

    final pipelineRaw = json['pipeline'];
    final commandlineRaw = json['commandline'];
    final commandRaw = json['command'];

    final keyCount = [pipelineRaw, commandlineRaw, commandRaw]
        .where((k) => k != null)
        .length;
    if (keyCount > 1) {
      throw ArgumentError(
          'CompileSection cannot have multiple of "pipeline", "commandline", and "command"');
    }

    // Parse files (required for all modes, but optional for pipeline-only sections)
    final filesRaw = json['files'];
    List<String> files;
    if (filesRaw is String) {
      files = [filesRaw];
    } else if (filesRaw is List) {
      files = filesRaw.map((e) => e.toString()).toList();
    } else if (pipelineRaw != null) {
      // Pipeline mode can have empty files (commands don't need file iteration)
      files = [];
    } else {
      throw ArgumentError('files must be a string or list');
    }

    final targetsRaw = json['targets'];
    List<String>? targets;
    if (targetsRaw is String) {
      targets = [targetsRaw];
    } else if (targetsRaw is List) {
      targets = targetsRaw.map((e) => e.toString()).toList();
    }

    final platformsRaw = json['platforms'];
    List<String>? platforms;
    if (platformsRaw is String) {
      platforms = [platformsRaw];
    } else if (platformsRaw is List) {
      platforms = platformsRaw.map((e) => e.toString()).toList();
    }

    if (pipelineRaw != null) {
      // Pipeline mode (global pipeline syntax)
      List<String> pipeline;
      if (pipelineRaw is String) {
        pipeline = [pipelineRaw];
      } else if (pipelineRaw is List) {
        pipeline = pipelineRaw.map((e) => e.toString()).toList();
      } else {
        throw ArgumentError('pipeline must be a string or list');
      }
      if (pipeline.isEmpty) {
        throw ArgumentError('pipeline cannot be empty');
      }

      return CompileSection(
        commandlines: [],
        pipeline: pipeline,
        files: files,
        targets: targets,
        platforms: platforms,
      );
    }

    if (commandRaw != null) {
      // Built-in command mode
      List<String> commands;
      if (commandRaw is String) {
        commands = [commandRaw];
      } else if (commandRaw is List) {
        commands = commandRaw.map((e) => e.toString()).toList();
      } else {
        throw ArgumentError('command must be a string or list');
      }
      if (commands.isEmpty) {
        throw ArgumentError('command cannot be empty');
      }

      return CompileSection(
        commandlines: [],
        commands: commands,
        isBuiltinCommand: true,
        files: files,
        targets: targets,
        platforms: platforms,
      );
    }

    // Shell commandline mode (original behavior)
    List<String> commandlines;
    if (commandlineRaw is String) {
      commandlines = [commandlineRaw];
    } else if (commandlineRaw is List) {
      commandlines = commandlineRaw.map((e) => e.toString()).toList();
    } else {
      throw ArgumentError('pipeline, commandline, or command must be specified');
    }

    if (commandlines.isEmpty) {
      throw ArgumentError('commandline cannot be empty');
    }

    return CompileSection(
      commandlines: commandlines,
      files: files,
      targets: targets,
      platforms: platforms,
    );
  }
}
