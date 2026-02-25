/// tom_build_base v2 - Unified CLI framework for workspace traversal.
///
/// This library provides:
/// - Structured traversal configuration ([TraversalInfo])
/// - Automatic folder scanning and nature detection
/// - Filter pipelines for flexible project selection
/// - Type-safe command context ([CommandContext])
///
/// ## Quick Start
///
/// ```dart
/// import 'package:tom_build_base/tom_build_base_v2.dart';
///
/// void main() async {
///   await BuildBase.traverse(
///     info: ProjectTraversalInfo(
///       scan: '.',
///       recursive: true,
///       executionRoot: Directory.current.path,
///     ),
///     run: (ctx) async {
///       print('Processing: ${ctx.name}');
///       return true;
///     },
///   );
/// }
/// ```

// Folder types
export 'src/v2/folder/fs_folder.dart';
export 'src/v2/folder/run_folder.dart';
export 'src/v2/folder/natures/natures.dart';

// Traversal
export 'src/v2/traversal/traversal_info.dart';
export 'src/v2/traversal/command_context.dart';
export 'src/v2/traversal/folder_scanner.dart' hide kTomSkipYaml;
export 'src/v2/traversal/filter_pipeline.dart';
export 'src/v2/traversal/nature_detector.dart';
export 'src/v2/traversal/build_base.dart';
export 'src/v2/traversal/build_order.dart';
export 'src/v2/traversal/repository_id_lookup.dart';
export 'src/v2/traversal/anchor_walker.dart';

// Tool Framework (Phase 2)
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

// Workspace utilities (constants, findWorkspaceRoot)
export 'src/v2/workspace_utils.dart';

// Placeholder resolution
export 'src/v2/execute_placeholder.dart';

// Navigation bridge (ArgParser integration)
export 'src/v2/navigation_bridge.dart';
