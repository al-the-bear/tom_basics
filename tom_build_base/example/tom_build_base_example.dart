/// Example showing how to use `tom_build_base` to discover projects and
/// read their versions.
///
/// This is a simplified version of the `show_versions` CLI tool shipped in
/// `bin/show_versions.dart`.  It demonstrates calling the library function
/// [showVersions] and consuming the [ShowVersionsResult].
///
/// Run:
///   dart run example/tom_build_base_example.dart [workspace-path]
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart';

void main(List<String> arguments) async {
  final basePath = arguments.isNotEmpty
      ? p.normalize(p.absolute(arguments.first))
      : Directory.current.path;

  print('Scanning: $basePath\n');

  final result = await showVersions(ShowVersionsOptions(
    basePath: basePath,
    verbose: arguments.contains('-v'),
    log: print,
  ));

  for (final entry in result.versions.entries) {
    print('  ${p.basename(entry.key).padRight(30)} ${entry.value}');
  }

  print('\n${result.versions.length} projects found, '
      '${result.failures.length} failures.');
}
