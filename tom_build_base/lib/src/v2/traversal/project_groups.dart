import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The file that marks a directory as a project group.
///
/// Its optional `name:` is the group's name; without one the group is named
/// after its directory.
const kBuildkitGroupYaml = 'buildkit_group.yaml';

/// The names of the groups the project at [projectPath] belongs to.
///
/// Groups are derived from the directory walk, never listed: every directory
/// from the project itself up to [executionRoot] (both included) that
///
/// - is a git repository (holds a `.git` directory, or a `.git` file as a
///   submodule checkout does) is a group named by its folder name and by its
///   path relative to [executionRoot];
/// - holds a `buildkit_group.yaml` is a group named by the file's `name:`, or
///   by its folder name when the file names none.
///
/// A project outside [executionRoot] belongs to no group.
Set<String> projectGroupsOf(String projectPath, String executionRoot) {
  final root = p.normalize(p.absolute(executionRoot));
  var dir = p.normalize(p.absolute(projectPath));
  if (!p.equals(dir, root) && !p.isWithin(root, dir)) return const {};
  final names = <String>{};
  while (true) {
    if (FileSystemEntity.typeSync(p.join(dir, '.git')) !=
        FileSystemEntityType.notFound) {
      names.add(p.basename(dir));
      final relative = p.relative(dir, from: root).replaceAll(r'\', '/');
      names.add(relative);
    }
    final marker = File(p.join(dir, kBuildkitGroupYaml));
    if (marker.existsSync()) names.add(_groupName(marker, dir));
    if (p.equals(dir, root)) return names;
    dir = p.dirname(dir);
  }
}

String _groupName(File marker, String dir) {
  final yaml = loadYaml(marker.readAsStringSync());
  final name = yaml is YamlMap ? yaml['name'] : null;
  return name is String && name.trim().isNotEmpty
      ? name.trim()
      : p.basename(dir);
}

/// The [groups] that no project in [projectPaths] belongs to, in the order
/// given and each once.
List<String> unmatchedGroups(
  Iterable<String> projectPaths,
  List<String> groups,
  String executionRoot,
) {
  final seen = <String>{
    for (final path in projectPaths) ...projectGroupsOf(path, executionRoot),
  };
  final unmatched = <String>[];
  for (final group in groups) {
    if (!seen.contains(group) && !unmatched.contains(group)) {
      unmatched.add(group);
    }
  }
  return unmatched;
}
