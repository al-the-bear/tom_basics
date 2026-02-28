import 'dart:io';

import 'package:yaml/yaml.dart';

import '../workspace_utils.dart';
import 'tool_definition.dart';

enum PipelineCommandPrefix { tool, shell, shellScan }

class PipelineCommandSpec {
  final String raw;
  final PipelineCommandPrefix prefix;
  final String body;

  const PipelineCommandSpec({
    required this.raw,
    required this.prefix,
    required this.body,
  });
}

class PipelineStepConfig {
  final List<PipelineCommandSpec> commands;

  const PipelineStepConfig({required this.commands});
}

class PipelineDefinition {
  final bool executable;
  final List<String> runBefore;
  final List<String> runAfter;
  final Map<String, String> globalOptions;
  final List<PipelineStepConfig> precore;
  final List<PipelineStepConfig> core;
  final List<PipelineStepConfig> postcore;

  const PipelineDefinition({
    this.executable = true,
    this.runBefore = const [],
    this.runAfter = const [],
    this.globalOptions = const {},
    this.precore = const [],
    this.core = const [],
    this.postcore = const [],
  });
}

class ToolPipelineConfig {
  final String sourcePath;
  final Map<String, PipelineDefinition> pipelines;

  const ToolPipelineConfig({required this.sourcePath, required this.pipelines});

  bool get hasPipelines => pipelines.isNotEmpty;
}

class PipelineCommandPrefixParser {
  static PipelineCommandSpec? parse(
    String rawCommand, {
    required String toolPrefix,
  }) {
    final trimmed = rawCommand.trim();
    if (trimmed.isEmpty) return null;

    final firstSpace = trimmed.indexOf(RegExp(r'\s'));
    final prefixToken = firstSpace == -1
        ? trimmed
        : trimmed.substring(0, firstSpace);
    final body = firstSpace == -1 ? '' : trimmed.substring(firstSpace).trim();

    if (prefixToken == toolPrefix) {
      return PipelineCommandSpec(
        raw: rawCommand,
        prefix: PipelineCommandPrefix.tool,
        body: body,
      );
    }
    if (prefixToken == 'shell') {
      return PipelineCommandSpec(
        raw: rawCommand,
        prefix: PipelineCommandPrefix.shell,
        body: body,
      );
    }
    if (prefixToken == 'shell-scan') {
      return PipelineCommandSpec(
        raw: rawCommand,
        prefix: PipelineCommandPrefix.shellScan,
        body: body,
      );
    }

    return null;
  }
}

class ToolPipelineConfigLoader {
  static bool isEligible({
    required ToolDefinition tool,
    required String fromDirectory,
  }) {
    if (tool.mode != ToolMode.multiCommand) return false;
    return _findMasterFile(tool.name, fromDirectory) != null;
  }

  static ToolPipelineConfig? load({
    required ToolDefinition tool,
    String? fromDirectory,
  }) {
    final dir = fromDirectory ?? Directory.current.path;
    if (!isEligible(tool: tool, fromDirectory: dir)) return null;

    final masterFile = _findMasterFile(tool.name, dir);
    if (masterFile == null || !masterFile.existsSync()) return null;

    final parsed = loadYaml(masterFile.readAsStringSync());
    if (parsed is! YamlMap) return null;

    final root = parsed;
    final toolSection = root[tool.name] is YamlMap
        ? root[tool.name] as YamlMap
        : null;

    final pipelinesNode =
        _extractPipelinesMap(root) ??
        (toolSection != null ? _extractPipelinesMap(toolSection) : null);
    if (pipelinesNode == null) {
      return ToolPipelineConfig(
        sourcePath: masterFile.path,
        pipelines: const {},
      );
    }

    final pipelines = <String, PipelineDefinition>{};
    for (final entry in pipelinesNode.entries) {
      final pipelineName = entry.key.toString();
      final value = entry.value;
      if (value is! YamlMap) continue;
      pipelines[pipelineName] = _parsePipeline(value, tool.pipelineName);
    }

    return ToolPipelineConfig(
      sourcePath: masterFile.path,
      pipelines: pipelines,
    );
  }

  static File? _findMasterFile(String toolName, String fromDirectory) {
    final root = findWorkspaceRoot(fromDirectory);
    final file = File('$root/${toolName}_master.yaml');
    return file.existsSync() ? file : null;
  }

  static YamlMap? _extractPipelinesMap(YamlMap container) {
    final direct = container['pipelines'];
    if (direct is YamlMap) return direct;

    final requiredEnv = container['required-environment'];
    if (requiredEnv is YamlMap) {
      final nested = requiredEnv['pipelines'];
      if (nested is YamlMap) return nested;
    }

    return null;
  }

  static PipelineDefinition _parsePipeline(YamlMap yaml, String toolPrefix) {
    return PipelineDefinition(
      executable: yaml['executable'] as bool? ?? true,
      runBefore: _parseStringList(yaml['runBefore']),
      runAfter: _parseStringList(yaml['runAfter']),
      globalOptions: _parseStringMap(yaml['global-options']),
      precore: _parseSteps(yaml['precore'], toolPrefix),
      core: _parseSteps(yaml['core'], toolPrefix),
      postcore: _parseSteps(yaml['postcore'], toolPrefix),
    );
  }

  static List<PipelineStepConfig> _parseSteps(
    dynamic value,
    String toolPrefix,
  ) {
    if (value is! YamlList) return const [];

    final steps = <PipelineStepConfig>[];
    for (final item in value) {
      if (item is! YamlMap) continue;
      final commandsRaw = item['commands'];
      if (commandsRaw is! YamlList) continue;

      final commands = <PipelineCommandSpec>[];
      for (final commandRaw in commandsRaw) {
        final text = commandRaw.toString();
        final parsed = PipelineCommandPrefixParser.parse(
          text,
          toolPrefix: toolPrefix,
        );
        if (parsed == null) {
          throw FormatException(
            'Unsupported pipeline command prefix in "$text". '
            'Allowed prefixes: $toolPrefix, shell, shell-scan.',
          );
        }
        commands.add(parsed);
      }

      steps.add(PipelineStepConfig(commands: commands));
    }

    return steps;
  }

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return const [];
    if (value is String) {
      return value
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (value is YamlList) {
      return value.map((e) => e.toString()).toList();
    }
    return const [];
  }

  static Map<String, String> _parseStringMap(dynamic value) {
    if (value is! YamlMap) return const {};
    final result = <String, String>{};
    for (final entry in value.entries) {
      result[entry.key.toString()] = entry.value.toString();
    }
    return result;
  }
}
