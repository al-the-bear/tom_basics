#!/usr/bin/env dart
/// Test traversal tool — spawned by integration tests to verify traversal
/// behavior from an external process perspective.
///
/// Outputs JSON to stdout describing the traversal results.
///
/// Usage:
///   dart run test/v2/fixtures/traversal_tool.dart [options]
///
/// Options are passed straight to CliArgParser + BuildBase.traverse.
/// The tool uses the same parsing pipeline as a real tool (ToolRunner flow).
///
/// Output format (JSON):
/// ```json
/// {
///   "traversalType": "project|git",
///   "executionRoot": "/path/to/root",
///   "folders": [
///     {
///       "name": "proj_alpha",
///       "path": "/abs/path",
///       "relative": "proj_alpha",
///       "natures": ["DartConsoleFolder", "DartProjectFolder"],
///       "order": 0
///     }
///   ],
///   "parsedArgs": {
///     "scan": ".",
///     "recursive": true,
///     "innerFirstGit": false,
///     "outerFirstGit": false,
///     "buildOrder": true,
///     "projectPatterns": [],
///     "excludePatterns": [],
///     "positionalArgs": [],
///     "commands": []
///   }
/// }
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:tom_build_base/tom_build_base_v2.dart';

Future<void> main(List<String> args) async {
  // Redirect all verbose/print output to stderr so stdout is pure JSON
  try {
    final result = await _runTraversal(args);
    stdout.writeln(jsonEncode(result));
  } catch (e, st) {
    stderr.writeln('ERROR: $e');
    stderr.writeln(st);
    exit(2);
  }
}

Future<Map<String, dynamic>> _runTraversal(List<String> args) async {
  // Parse args using the same parser a real tool uses
  final parser = CliArgParser();
  final cliArgs = parser.parse(args);

  // Determine execution root
  final String executionRoot;
  if (cliArgs.root != null) {
    executionRoot = cliArgs.root!;
  } else {
    executionRoot = Directory.current.path;
  }

  // Determine traversal type
  final useGit = cliArgs.innerFirstGit || cliArgs.outerFirstGit;

  final BaseTraversalInfo traversalInfo;
  final String traversalType;

  if (useGit) {
    traversalType = 'git';
    final gitInfo = cliArgs.toGitTraversalInfo(executionRoot: executionRoot);
    if (gitInfo == null) {
      return {
        'error': 'Git traversal mode required but could not be determined',
      };
    }
    traversalInfo = gitInfo;
  } else {
    traversalType = 'project';
    traversalInfo = cliArgs.toProjectTraversalInfo(
      executionRoot: executionRoot,
    );
  }

  // Traverse and collect results
  final folders = <Map<String, dynamic>>[];
  var order = 0;

  await BuildBase.traverse(
    info: traversalInfo,
    verbose: cliArgs.verbose,
    requiredNatures: {FsFolder},
    run: (ctx) async {
      folders.add({
        'name': ctx.name,
        'path': ctx.path,
        'relative': ctx.relativePath,
        'natures': ctx.natures.map((n) => n.runtimeType.toString()).toList(),
        'order': order++,
      });
      return true;
    },
  );

  return {
    'traversalType': traversalType,
    'executionRoot': executionRoot,
    'folders': folders,
    'parsedArgs': {
      'scan': cliArgs.scan,
      'recursive': cliArgs.recursive,
      'notRecursive': cliArgs.notRecursive,
      'root': cliArgs.root,
      'bareRoot': cliArgs.bareRoot,
      'innerFirstGit': cliArgs.innerFirstGit,
      'outerFirstGit': cliArgs.outerFirstGit,
      'topRepo': cliArgs.topRepo,
      'buildOrder': cliArgs.buildOrder,
      'projectPatterns': cliArgs.projectPatterns,
      'excludePatterns': cliArgs.excludePatterns,
      'excludeProjects': cliArgs.excludeProjects,
      'modules': cliArgs.modules,
      'skipModules': cliArgs.skipModules,
      'positionalArgs': cliArgs.positionalArgs,
      'commands': cliArgs.commands,
      'verbose': cliArgs.verbose,
      'dryRun': cliArgs.dryRun,
      'includeTestProjects': cliArgs.includeTestProjects,
      'testProjectsOnly': cliArgs.testProjectsOnly,
    },
  };
}
