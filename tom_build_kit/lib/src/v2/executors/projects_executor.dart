/// `:projects`: the workspace's projects as buildkit's own commands see them,
/// as a table or, with `--json`, as one JSON document on stdout.
///
/// The listing is tom_build_base's `listProjectsFor`: the same traversal, the
/// same `buildkit_master.yaml` navigation defaults and the same `-p`, `-r`,
/// `--exclude-projects`, `--group` selection as any project command. The VS
/// Code extension reads it (`tomAi_listProjects`, `tomAi_getWorkspaceInfo`)
/// instead of a generated workspace manifest, with `--all`: every project of
/// the tree, past the `navigation:` excludes that keep whole subtrees from the
/// build commands.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

/// The `formatVersion` of the JSON document; raised only when a change is not
/// backwards compatible (a field removed or its meaning changed).
const projectsJsonFormatVersion = 1;

/// Executor of `:projects`.
class ProjectsExecutor extends CommandExecutor {
  /// Where the document or table goes (stdout; a buffer in tests).
  final StringSink out;

  ProjectsExecutor({StringSink? out}) : out = out ?? stdout;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.failure(
        path: context.path,
        name: context.name,
        error: 'projects uses executeWithoutTraversal',
      );

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final root = p.normalize(
      p.absolute(
        args.root ??
            findWorkspaceRootOrNull(Directory.current.path) ??
            Directory.current.path,
      ),
    );
    final options = args.optionsFor('projects');
    final json = options['json'] == true;
    final all = options['all'] == true;

    // The scanner reports skipped folders with print(); on stdout those lines
    // would break the JSON document, so every print of the walk goes to
    // stderr.
    final projects = await runZoned(
      () =>
          listProjectsFor(args, executionRoot: root, navigationDefaults: !all),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => stderr.writeln(line),
      ),
    );

    if (json) {
      out.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'formatVersion': projectsJsonFormatVersion,
          'tool': 'buildkit',
          'root': root,
          'all': all,
          'count': projects.length,
          'projects': [for (final project in projects) project.toJson()],
        }),
      );
    } else {
      for (final project in projects) {
        out.writeln(
          '${project.path.padRight(56)} ${project.id.padRight(28)} '
          '${project.natures.join(',')}',
        );
      }
      out.writeln('${projects.length} project(s)');
    }
    return ToolResult.success();
  }
}
