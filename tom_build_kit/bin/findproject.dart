#!/usr/bin/env dart

/// Standalone findproject tool.
///
/// Resolves a project by name, project ID, or folder name and prints
/// the absolute path to stdout.  Designed to be wrapped by a shell
/// function for `cd`:
///
/// ```bash
/// goto() { local d; d="$(findproject "$@" 2>/dev/null)"; if [[ -n "$d" && -d "$d" ]]; then cd "$d"; else findproject "$@"; return 1; fi; }
/// ```
library;

import 'dart:io';

import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/src/v2/executors/findproject_executor.dart';
import 'package:tom_build_kit/src/version.versioner.dart';

Future<void> main(List<String> arguments) async {
  // Handle --version
  if (arguments.contains('--version') || arguments.contains('-V')) {
    print(BuildkitVersionInfo.versionLong);
    return;
  }

  // Handle --help
  if (arguments.contains('--help') || arguments.contains('-h')) {
    _printHelp();
    return;
  }

  final executor = FindProjectExecutor();

  final args = CliArgs(
    root: Directory.current.path,
    positionalArgs: arguments.where((a) => !a.startsWith('-')).toList(),
    verbose: arguments.contains('-v') || arguments.contains('--verbose'),
  );

  final result = await executor.executeWithoutTraversal(args);

  if (!result.success) {
    exit(1);
  }
}

void _printHelp() {
  print('Usage: findproject <project-name|project-id|folder>');
  print('');
  print('Resolves a project and prints its absolute path.');
  print('Walks up from the current directory, scanning at each');
  print('anchor (.git or buildkit_master.yaml) until found.');
  print('');
  print('Options:');
  print('  -v, --verbose   Show detailed search output');
  print('  -h, --help      Show this help');
  print('  -V, --version   Show version');
  print('');
  print('Shell integration (add to .zshrc):');
  print(
    r'  goto() { local d; d="$(findproject "$@" 2>/dev/null)"; if [[ -n "$d" && -d "$d" ]]; then cd "$d"; else findproject "$@"; return 1; fi; }',
  );
}
