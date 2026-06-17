/// Native v2 executor for the buildsorter command.
///
/// Delegates build order computation to [BuildOrderComputer] from
/// tom_build_base, which implements topological sort (Kahn's algorithm).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

/// Native v2 executor for the `:buildsorter` command.
///
/// Uses `requiresTraversal: false` because it needs all project info
/// collected before running the topological sort.
class BuildSorterExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    return ItemResult.failure(
      path: context.path,
      name: context.name,
      error: ':buildsorter uses executeWithoutTraversal',
    );
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final cmdOpts = _getCmdOpts(args);
    final reverse = cmdOpts['reverse'] == true;
    final showNames = cmdOpts['names'] == true;
    final includeDev = cmdOpts['include-dev'] == true;

    final executionRoot = args.root ?? Directory.current.path;
    final traversalInfo =
        args.toProjectTraversalInfo(executionRoot: executionRoot);

    // Collect all project paths
    final projectPaths = <String>[];
    await BuildBase.traverse(
      info: traversalInfo,
      worksWithNatures: {DartProjectFolder},
      run: (context) async {
        if (File('${context.path}/pubspec.yaml').existsSync()) {
          projectPaths.add(context.path);
        }
        return true;
      },
    );

    if (projectPaths.isEmpty) {
      print('No projects found.');
      return const ToolResult.success();
    }

    // Delegate to BuildOrderComputer from tom_build_base
    final sorted = BuildOrderComputer.computeBuildOrder(
      projectPaths,
      includeDev: includeDev,
    );

    if (sorted == null) {
      return const ToolResult.failure('Circular dependency detected');
    }

    final ordered = reverse ? sorted.reversed.toList() : sorted;

    print('');
    print('Build order (${reverse ? "reverse" : "dependency-first"}):');
    for (var i = 0; i < ordered.length; i++) {
      final path = ordered[i];
      if (showNames) {
        final name = BuildOrderComputer.getProjectName(path);
        print('  ${i + 1}. $name');
      } else {
        print('  ${i + 1}. ${p.relative(path, from: executionRoot)}');
      }
    }

    return const ToolResult.success();
  }

  Map<String, dynamic> _getCmdOpts(CliArgs args) {
    for (final cmd in args.commands) {
      if (cmd == 'buildsorter' || cmd == 'sort') {
        final cmdArgs = args.commandArgs[cmd];
        if (cmdArgs != null) return cmdArgs.options;
      }
    }
    return args.extraOptions;
  }
}
