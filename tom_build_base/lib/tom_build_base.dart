/// Tom Build Base — Unified CLI framework for workspace traversal and tool
/// definition.
///
/// This library provides:
/// - Tool definition and CLI argument parsing ([ToolDefinition], [CliArgs])
/// - Command execution with traversal ([ToolRunner], [CommandExecutor])
/// - Folder scanning and nature detection ([FolderScanner], [NatureDetector])
/// - Pipeline configuration and execution ([PipelineConfig], [PipelineExecutor])
/// - Help generation and shell completion ([HelpGenerator], [CompletionGenerator])
/// - Configuration loading from `buildkit_master.yaml` / `tom_master.yaml`
///
/// ## Quick Start
///
/// ```dart
/// import 'package:tom_build_base/tom_build_base.dart';
///
/// final tool = ToolDefinition(
///   name: 'mytool',
///   description: 'My custom tool',
///   version: Version(1, 0, 0),
///   commands: [
///     CommandDefinition(name: 'hello', description: 'Say hello'),
///   ],
/// );
///
/// void main(List<String> args) => ToolRunner(tool).run(args);
/// ```
library;

// ── Utility classes (config loading, process execution, YAML) ──────────
export 'src/build_config.dart';
export 'src/tool_logging.dart';
export 'src/yaml_utils.dart';

// ── Folder types ───────────────────────────────────────────────────────
export 'src/v2/folder/fs_folder.dart';
export 'src/v2/folder/run_folder.dart';
export 'src/v2/folder/natures/natures.dart';

// ── Traversal ──────────────────────────────────────────────────────────
export 'src/v2/traversal/traversal_info.dart';
export 'src/v2/traversal/command_context.dart';
export 'src/v2/traversal/folder_scanner.dart' hide kTomSkipYaml;
export 'src/v2/traversal/filter_pipeline.dart';
export 'src/v2/traversal/nature_detector.dart';
export 'src/v2/traversal/build_base.dart';
export 'src/v2/traversal/build_order.dart';
export 'src/v2/traversal/repository_id_lookup.dart';
export 'src/v2/traversal/anchor_walker.dart';
export 'src/v2/traversal/workspace_scanner.dart';

// ── Tool Framework ─────────────────────────────────────────────────────
export 'src/v2/core/option_definition.dart';
export 'src/v2/core/command_definition.dart';
export 'src/v2/core/tool_definition.dart';
export 'src/v2/core/cli_arg_parser.dart';
export 'src/v2/core/help_generator.dart';
export 'src/v2/core/command_executor.dart';
export 'src/v2/core/tool_runner.dart';
export 'src/v2/core/completion_generator.dart';
export 'src/v2/core/macro_expansion.dart';
export 'src/v2/core/special_commands.dart';
export 'src/v2/core/help_topic.dart';
export 'src/v2/core/builtin_help_topics.dart';
export 'src/v2/core/console_markdown_zone.dart';
export 'src/v2/core/tool_wiring_entry.dart';
export 'src/v2/core/tool_definition_serializer.dart';
export 'src/v2/core/pipeline_config.dart';
export 'src/v2/core/pipeline_executor.dart';
export 'src/v2/core/mklink_executor.dart';
export 'src/v2/core/binary_helpers.dart';
export 'src/v2/core/nested_tool_executor.dart';
export 'src/v2/core/wiring_loader.dart';

// ── Workspace utilities ────────────────────────────────────────────────
export 'src/v2/workspace_utils.dart';

// ── Placeholder resolution ─────────────────────────────────────────────
export 'src/v2/execute_placeholder.dart';

// ── Navigation bridge (ArgParser integration) ──────────────────────────
export 'src/v2/navigation_bridge.dart';
