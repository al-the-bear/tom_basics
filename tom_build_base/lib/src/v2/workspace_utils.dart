import 'dart:io';

import 'package:path/path.dart' as p;

/// Filename for the workspace-level buildkit configuration.
const kBuildkitMasterYaml = 'buildkit_master.yaml';

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
  // Workspace-wide scratch dir (gitignored). Full project copies routinely
  // accumulate here for debugging; they carry stale dependency constraints and
  // must never be discovered, pub-updated, or built.
  'ztmp',
};

/// Find the workspace root by traversing upwards looking for workspace markers.
///
/// Returns the directory containing `buildkit_master.yaml`
/// or `tom.code-workspace`, or [startPath] if none is found.
String findWorkspaceRoot(String startPath) {
  var current = p.normalize(p.absolute(startPath));
  final root = p.rootPrefix(current);

  while (current != root) {
    if (File(p.join(current, kBuildkitMasterYaml)).existsSync() ||
        File(p.join(current, kTomCodeWorkspace)).existsSync()) {
      return current;
    }
    current = p.dirname(current);
  }

  return startPath;
}

/// Validate that no absolute `--project` pattern points outside [executionRoot].
///
/// `--project` patterns are filters resolved against the scanned tree: a project
/// id, a project name, a folder-name glob, or a relative path are all contained
/// by construction — they can only ever match something *inside* the workspace.
/// The single way a `--project` value can escape the workspace is an **absolute
/// path** that resolves outside the execution root. A tool that silently matches
/// nothing in that case looks like a successful no-op while actually being asked
/// to operate on a path it must never touch.
///
/// This function therefore checks only the absolute patterns: each must equal
/// [executionRoot] or be contained within it. The first offending pattern yields
/// a human-readable error string (mentioning "outside", "path", and "within" so
/// callers and tests can recognise the rejection); a return of `null` means all
/// patterns are safe.
String? validateProjectPathsWithinRoot(
  List<String> projectPatterns,
  String executionRoot,
) {
  final rootAbs = p.normalize(p.absolute(executionRoot));
  for (final pattern in projectPatterns) {
    if (!p.isAbsolute(pattern)) continue;
    final patternAbs = p.normalize(pattern);
    if (p.equals(rootAbs, patternAbs) || p.isWithin(rootAbs, patternAbs)) {
      continue;
    }
    return 'project path is outside the workspace and was rejected: '
        '$pattern (workspace root: $rootAbs). '
        '--project paths must be within the workspace.';
  }
  return null;
}

/// Validate that every *path-style, non-glob* `--project` pattern resolves to an
/// existing directory under [executionRoot].
///
/// A `--project` filter can be a project id, a project name, a folder-name glob,
/// or a path. Ids, names, and globs legitimately may match zero projects, so
/// they are never treated as "not found": only a **path** pattern names a
/// concrete directory. When such a path is **non-glob** (no `*`, `?`, `[`, `{`)
/// and the directory does not exist, the user mistyped it. Previously the run
/// scanned, matched nothing, and exited `0` — masking the typo and making the
/// tool look like a successful no-op (this is the bug #19 regression DEP_ERR01
/// guards against).
///
/// Relative patterns are resolved against [executionRoot] (the workspace root),
/// matching how [FilterPipeline] interprets relative `--project` paths; absolute
/// patterns are checked as-is (an absolute path *outside* the root is rejected
/// earlier by [validateProjectPathsWithinRoot], so this only sees in-root
/// absolutes). Returns a human-readable error (mentioning "not found") for the
/// first missing path pattern, or `null` when every path pattern exists.
String? validateProjectPathsExist(
  List<String> projectPatterns,
  String executionRoot,
) {
  final rootAbs = p.normalize(p.absolute(executionRoot));
  for (final pattern in projectPatterns) {
    if (!_isProjectPathPattern(pattern)) continue; // id / name — not a path
    if (_containsGlobChar(pattern)) continue; // glob path may match zero
    final resolved = p.isAbsolute(pattern)
        ? p.normalize(pattern)
        : p.normalize(p.join(rootAbs, pattern));
    if (Directory(resolved).existsSync()) continue;
    return 'project path not found: $pattern (resolved: $resolved). '
        '--project must reference an existing project directory, id, or name.';
  }
  return null;
}

/// Whether a `--project` pattern is path-style (contains a directory separator).
///
/// Mirrors the path/basename split [FilterPipeline] uses: a value with `/` or
/// `\` is matched against project paths, anything else against ids / names.
bool _isProjectPathPattern(String pattern) =>
    pattern.contains('/') || pattern.contains(r'\');

/// Whether a pattern contains a glob metacharacter, in which case it may
/// legitimately match zero directories and must not be existence-checked.
bool _containsGlobChar(String pattern) =>
    pattern.contains('*') ||
    pattern.contains('?') ||
    pattern.contains('[') ||
    pattern.contains('{');

/// Validate that the `--scan` path does not point outside [executionRoot].
///
/// Unlike `--project` (a filter over the scanned tree), `--scan` names the real
/// directory the traversal walks: the scanner runs `Directory(scan)` directly,
/// resolving a relative value against the current directory and using an
/// absolute value as-is. Either form can therefore escape the workspace — an
/// absolute path such as `/tmp`, or a relative `../../sibling`. As with
/// `--project`, a scan that lands outside the workspace previously produced an
/// empty result and an exit code of `0`, masking the fact that the tool was
/// pointed at a location it must not walk.
///
/// This resolves [scan] to an absolute, normalised path the same way the scanner
/// does (relative-to-cwd) and requires it to equal or be contained within the
/// resolved [executionRoot]. Returns a human-readable error string (mentioning
/// "outside", "path", and "within") for an out-of-root scan, or `null` when the
/// scan is safe.
String? validateScanPathWithinRoot(String scan, String executionRoot) {
  // Canonicalise both endpoints (resolving symlinks for existing paths) before
  // comparing. Without this, a symlinked root vs a cwd-resolved relative scan
  // can disagree purely on the link target — on macOS, for example,
  // `/var/folders/...` (a symlink) versus its `/private/var/folders/...` target
  // — and a legitimately-contained scan would be falsely rejected.
  final rootAbs = _canonicalize(executionRoot);
  final scanAbs = _canonicalize(scan);
  if (p.equals(rootAbs, scanAbs) || p.isWithin(rootAbs, scanAbs)) {
    return null;
  }
  return 'scan path is outside the workspace and was rejected: '
      '$scan (workspace root: $rootAbs). '
      '--scan paths must be within the workspace.';
}

/// Resolve [path] to a normalised absolute path, following symlinks when the
/// path exists. Falls back to a plain normalised-absolute path when the target
/// does not exist (e.g. a mistyped scan path), so the function never throws.
String _canonicalize(String path) {
  final abs = p.normalize(p.absolute(path));
  try {
    return Directory(abs).resolveSymbolicLinksSync();
  } on FileSystemException {
    try {
      return File(abs).resolveSymbolicLinksSync();
    } on FileSystemException {
      return abs;
    }
  }
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
/// - Stops at workspace boundaries (`buildkit_master.yaml`)
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
          if (kAlwaysSkipDirectories.contains(name)) continue;
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
    if (File(p.join(dir.path, kBuildkitMasterYaml)).existsSync()) {
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
