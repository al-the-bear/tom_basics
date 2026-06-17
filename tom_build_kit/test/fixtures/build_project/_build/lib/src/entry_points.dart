/// CLI entry point wrappers for all consolidated binaries.
///
/// These import from the source packages using package: imports
/// and re-export callable main functions.
library;

// Tom Build CLI tools - complete CLI entry points
export 'package:tom_build_cli/cli_entry.dart';

// VS Code bridge - bridge server
export 'package:tom_vscode_bridge/bridge_server.dart';

// Process monitor - CLI command
export 'package:tom_process_monitor_tool/tom_process_monitor_tool.dart';

// DCLI - D4rt REPL with dcli bridges
export 'package:tom_d4rt_dcli/tom_d4rt_dcli.dart';
