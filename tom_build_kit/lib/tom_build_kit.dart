/// Tom Build Kit - Build orchestration and CLI tools.
///
/// Provides the v2 executor-based build infrastructure for the buildkit CLI.
/// All build commands are implemented as native v2 [CommandExecutor]s.
library;

// Version info
export 'src/version.versioner.dart';

// Shared utilities
export 'src/builtin_commands.dart';
export 'src/compiler_config.dart';
export 'src/platform_utils.dart';
export 'src/script_utils.dart';

// Standalone commands (used by v2 executors)
export 'src/pubget_command.dart';
export 'src/pubupdate_command.dart';

// V2 API
export 'src/v2/buildkit_tool.dart';
export 'src/v2/buildkit_executors.dart';
