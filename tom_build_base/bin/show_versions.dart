#!/usr/bin/env dart

/// CLI entry point for the show-versions tool.
///
/// Discovers Dart projects under the given workspace path (or current
/// directory) and prints each project's name and version.
///
/// Usage:
///   dart run tom_build_base:show_versions [workspace-path]
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart';

void main(List<String> arguments) async {
  final basePath = arguments.isNotEmpty
      ? p.normalize(p.absolute(arguments.first))
      : Directory.current.path;

  print('Workspace: $basePath\n');

  final result = await showVersions(ShowVersionsOptions(
    basePath: basePath,
    verbose: arguments.contains('--verbose') || arguments.contains('-v'),
    log: (msg) => print('  $msg'),
  ));

  // Print versions
  for (final entry in result.versions.entries) {
    print('  ✓  ${p.basename(entry.key)} ${entry.value}');
  }
  for (final path in result.failures) {
    print('  ✗  ${p.basename(path)} — no version found');
  }

  // Summary
  final pr = result.processingResult;
  print('');
  print('──────────────────────────────────────');
  print('Total projects : ${pr.totalCount}');
  print('Succeeded      : ${pr.successCount}');
  print('Failed         : ${pr.failureCount}');
  print('Files scanned  : ${pr.fileCount}');

  if (pr.hasFailures) exit(1);
}
