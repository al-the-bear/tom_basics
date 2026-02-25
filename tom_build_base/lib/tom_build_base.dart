/// Tom Build Base - Shared configuration and traversal logic for Tom build tools.
///
/// This library provides common infrastructure for Tom build tools that use
/// `tom_build.yaml` configuration files and need to traverse project directories.
///
/// ## Features
///
/// - Unified `tom_build.yaml` configuration loading
/// - Workspace root detection via [findWorkspaceRoot]
/// - Path containment validation
/// - Processing result tracking
///
/// ## Usage
///
/// ```dart
/// import 'package:tom_build_base/tom_build_base.dart';
///
/// // Load tool-specific config from tom_build.yaml
/// final config = TomBuildConfig.load(
///   dir: Directory.current.path,
///   toolKey: 'dartgen',
/// );
///
/// // Find workspace root
/// final wsRoot = findWorkspaceRoot(Directory.current.path);
///
/// // Check if build.yaml defines a builder (should be ignored by CLI tools)
/// if (isBuildYamlBuilderDefinition(projectPath)) {
///   print('Skipping builder definition package');
///   return;
/// }
/// ```
library;

export 'src/build_yaml_utils.dart';

export 'src/build_config.dart';
export 'src/config_loader.dart' hide kTomSkipYaml;
export 'src/config_merger.dart';
export 'src/path_utils.dart';
export 'src/processing_result.dart';
export 'src/tool_logging.dart';
export 'src/yaml_utils.dart';
export 'src/show_versions.dart';

// V2 workspace utilities (constants, findWorkspaceRoot)
export 'src/v2/workspace_utils.dart';

// Console markdown zone integration
export 'src/v2/core/console_markdown_zone.dart';

// V2 navigation bridge (ArgParser integration)
export 'src/v2/navigation_bridge.dart';

// V2 traversal API
export 'src/v2/folder/fs_folder.dart';
export 'src/v2/folder/run_folder.dart';
export 'src/v2/folder/natures/dart_project_folder.dart';
export 'src/v2/folder/natures/git_folder.dart';
export 'src/v2/folder/natures/extension_folder.dart';
export 'src/v2/folder/natures/buildkit_folder.dart';
export 'src/v2/traversal/workspace_scanner.dart';
export 'src/v2/traversal/folder_scanner.dart' show GitRepoFinder;
export 'src/v2/traversal/nature_detector.dart';
export 'src/v2/execute_placeholder.dart';
