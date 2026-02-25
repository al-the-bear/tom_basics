import 'dart:io';

import 'package:path/path.dart' as p;

/// Filename for the workspace-level buildkit configuration.
const kBuildkitMasterYaml = 'buildkit_master.yaml';

/// Filename for the Tom workspace configuration.
const kTomWorkspaceYaml = 'tom_workspace.yaml';

/// Filename for the VS Code workspace file.
const kTomCodeWorkspace = 'tom.code-workspace';

/// Filename for the buildkit skip marker.
const kBuildkitSkipYaml = 'buildkit_skip.yaml';

/// Filename for the global skip marker (all tools).
const kTomSkipYaml = 'tom_skip.yaml';

/// Directories that should always be skipped during recursive scanning.
///
/// These are build artifacts, caches, or hidden infrastructure directories
/// that never contain relevant Dart projects.
const kAlwaysSkipDirectories = <String>{
  '.dart_tool',
  '.git',
  '.idea',
  '.vscode',
  'build',
  'node_modules',
  'coverage',
  '.pub-cache',
  '.pub',
  '__pycache__',
  '.fvm',
};

/// Find the workspace root by traversing upwards looking for workspace markers.
///
/// Returns the directory containing `buildkit_master.yaml`, `tom_workspace.yaml`,
/// or `tom.code-workspace`, or [startPath] if none is found.
String findWorkspaceRoot(String startPath) {
  var current = p.normalize(p.absolute(startPath));
  final root = p.rootPrefix(current);

  while (current != root) {
    if (File(p.join(current, kBuildkitMasterYaml)).existsSync() ||
        File(p.join(current, kTomWorkspaceYaml)).existsSync() ||
        File(p.join(current, kTomCodeWorkspace)).existsSync()) {
      return current;
    }
    current = p.dirname(current);
  }

  return startPath;
}

/// Check if a directory is a workspace boundary (contains buildkit_master.yaml).
///
/// Workspace boundaries are treated similarly to skip markers — they
/// mark directories that should be processed separately.
bool isWorkspaceBoundary(String dirPath) {
  return File(p.join(dirPath, kBuildkitMasterYaml)).existsSync();
}

/// Scan a directory for Dart projects (directories containing pubspec.yaml).
///
/// When [recursive] is true, performs a controlled recursive walk that:
/// - Skips hidden directories (names starting with `.`)
/// - Skips known non-project directories (build, node_modules, etc.)
/// - Skips `zom_*` test folders (unless [includeTestProjects] is true)
/// - Stops at workspace boundaries (`buildkit_master.yaml`, `tom_workspace.yaml`)
/// - Respects skip markers (`tom_skip.yaml`, `buildkit_skip.yaml`)
///
/// When [recursive] is false, only checks immediate subdirectories and the
/// root itself.
List<String> scanForDartProjects(
  String dir, {
  bool recursive = false,
  bool includeTestProjects = false,
  bool verbose = false,
}) {
  final root = Directory(dir);
  if (!root.existsSync()) return [];

  final results = <String>[];
  if (recursive) {
    _scanRecursive(
      root,
      results,
      isRoot: true,
      includeTestProjects: includeTestProjects,
      verbose: verbose,
    );
  } else {
    // Non-recursive: check immediate children + root itself
    final rootPubspec = File(p.join(dir, 'pubspec.yaml'));
    if (rootPubspec.existsSync()) results.add(dir);

    try {
      for (final entity in root.listSync()) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue;
          if (!includeTestProjects && name.startsWith('zom_')) continue;
          final pubspec = File(p.join(entity.path, 'pubspec.yaml'));
          if (pubspec.existsSync()) results.add(entity.path);
        }
      }
    } on FileSystemException {
      // Permission denied or other filesystem error
    }
  }
  return results;
}

/// Recursive walk that respects workspace boundaries, skip markers, and
/// always-skip directories.
void _scanRecursive(
  Directory dir,
  List<String> results, {
  required bool isRoot,
  required bool includeTestProjects,
  required bool verbose,
}) {
  final name = p.basename(dir.path);

  // Skip hidden directories
  if (!isRoot && name.startsWith('.')) return;

  // Skip always-skip directories (build, node_modules, etc.)
  if (kAlwaysSkipDirectories.contains(name)) return;

  // Skip zom_* test folders unless explicitly included
  if (!isRoot && !includeTestProjects && name.startsWith('zom_')) {
    if (verbose) {
      stderr.writeln('Skipping test project: $name');
    }
    return;
  }

  // Stop at workspace boundaries (sub-workspaces should be processed separately)
  if (!isRoot) {
    if (File(p.join(dir.path, kBuildkitMasterYaml)).existsSync() ||
        File(p.join(dir.path, kTomWorkspaceYaml)).existsSync()) {
      if (verbose) {
        stderr.writeln('Skipping subworkspace: $name');
      }
      return;
    }
  }

  // Stop at skip markers
  if (!isRoot) {
    if (File(p.join(dir.path, kTomSkipYaml)).existsSync() ||
        File(p.join(dir.path, kBuildkitSkipYaml)).existsSync()) {
      if (verbose) {
        stderr.writeln('Skipping (skip marker): $name');
      }
      return;
    }
  }

  // Check if this directory is a Dart project
  if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
    results.add(dir.path);
  }

  // Descend into subdirectories
  try {
    for (final entity in dir.listSync()) {
      if (entity is Directory) {
        _scanRecursive(
          entity,
          results,
          isRoot: false,
          includeTestProjects: includeTestProjects,
          verbose: verbose,
        );
      }
    }
  } on FileSystemException {
    // Permission denied or other filesystem error
  }
}
