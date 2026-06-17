import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

// Re-export scanForDartProjects and kAlwaysSkipDirectories from tom_build_base
// (previously duplicated here; now canonical in workspace_utils.dart).
export 'package:tom_build_base/tom_build_base.dart'
    show scanForDartProjects, kAlwaysSkipDirectories;

/// Resolve comma-separated project patterns (globs or paths) to a list of
/// project directories.
///
/// Patterns may contain wildcards (`*`, `?`, `[`). Non-glob patterns are
/// treated as literal paths, resolved relative to [basePath].
List<String> resolveProjectPatterns(
  String patterns, {
  required String basePath,
}) {
  final results = <String>[];
  for (final pattern
      in patterns.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
    if (pattern.contains('*') ||
        pattern.contains('?') ||
        pattern.contains('[')) {
      final glob = Glob(pattern);
      for (final entity in glob.listSync(root: basePath)) {
        if (entity is Directory) {
          final pubspec = File(p.join(entity.path, 'pubspec.yaml'));
          if (pubspec.existsSync()) results.add(entity.path);
        }
      }
    } else {
      final resolved = p.isAbsolute(pattern)
          ? pattern
          : p.join(basePath, pattern);
      if (Directory(resolved).existsSync()) results.add(resolved);
    }
  }
  return results;
}
