import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../folder/fs_folder.dart';
import 'project_files.dart';
import '../workspace_utils.dart' show kAlwaysSkipDirectories;

/// Global skip file that blocks all tools.
const kTomSkipYaml = 'tom_skip.yaml';

/// The skip marker in [dirPath], if any: a nested workspace
/// (`{toolBasename}_master.yaml`), `tom_skip.yaml` (all tools) or
/// `{toolBasename}_skip.yaml`. Shared by project and git mode.
_SkipType? _skipMarkerIn(String dirPath, String toolBasename) {
  if (File(p.join(dirPath, '${toolBasename}_master.yaml')).existsSync()) {
    return _SkipType.workspaceBoundary;
  }
  if (File(p.join(dirPath, kTomSkipYaml)).existsSync()) {
    return _SkipType.globalSkip;
  }
  if (File(p.join(dirPath, '${toolBasename}_skip.yaml')).existsSync()) {
    return _SkipType.toolSkip;
  }
  return null;
}

/// Tells the user on stderr which folder a skip marker excludes.
void _reportSkip(_SkipType marker, String dirPath, String toolBasename) {
  final folderName = p.basename(dirPath);
  switch (marker) {
    case _SkipType.workspaceBoundary:
      stderr.writeln('Skipping subworkspace: $folderName');
    case _SkipType.globalSkip:
      stderr.writeln('Skipping - $kTomSkipYaml found: $folderName');
    case _SkipType.toolSkip:
      stderr.writeln('Skipping - ${toolBasename}_skip.yaml found: $folderName');
  }
}

/// Type of skip marker found in a directory.
enum _SkipType {
  /// `tom_skip.yaml` — global skip for all tools.
  globalSkip,

  /// `{toolBasename}_skip.yaml` — tool-specific skip.
  toolSkip,

  /// Nested workspace boundary (e.g., `buildkit_master.yaml`).
  workspaceBoundary,
}

/// Scans directories and builds a list of FsFolders.
///
/// Handles recursive scanning, skip markers, and recursion exclusions.
class FolderScanner {
  /// Tool basename for tool-specific skip files (e.g., 'issuekit' → 'issuekit_skip.yaml').
  final String toolBasename;

  /// Whether to print verbose messages for skipped directories.
  final bool verbose;

  /// When true, ignore all skip markers (workspace boundaries, *_skip.yaml)
  /// and traverse into everything. Activated by `--no-skip`.
  final bool ignoreSkipMarkers;

  /// The nested workspaces (folders with `{toolBasename}_master.yaml`) the
  /// scans so far passed over, in the order met: `-w` runs the command in
  /// each of them.
  final skippedWorkspaces = <String>[];

  /// Create a FolderScanner.
  ///
  /// [toolBasename] - Tool name for tool-specific skip files. Defaults to 'buildkit'.
  /// [verbose] - If true, print extra messages.
  /// [ignoreSkipMarkers] - If true, traverse into skipped folders anyway.
  FolderScanner({
    this.toolBasename = 'buildkit',
    this.verbose = false,
    this.ignoreSkipMarkers = false,
  });

  /// Tool-specific skip filename.
  String get skipFilename => '${toolBasename}_skip.yaml';

  /// Scan for folders starting from [root].
  ///
  /// The scanner always descends into non-project directories (containers)
  /// to find projects — that is the purpose of scanning.
  ///
  /// [recursive] - Controls whether to descend into **project** directories
  ///   (those containing `pubspec.yaml`) to find nested projects within them.
  ///   When false, project directories are included but not entered.
  /// [recursionExclude] - Patterns to skip during recursive descent.
  Future<List<FsFolder>> scan(
    String root, {
    bool recursive = false,
    List<String> recursionExclude = const [],
  }) async {
    final folders = <FsFolder>[];
    final rootDir = Directory(root);

    if (!rootDir.existsSync()) {
      return folders;
    }

    await _scanDirectory(
      rootDir,
      folders,
      recursive: recursive,
      recursionExclude: recursionExclude,
      isRoot: true, // Don't skip the initial scan directory
    );

    return folders;
  }

  Future<void> _scanDirectory(
    Directory dir,
    List<FsFolder> results, {
    required bool recursive,
    required List<String> recursionExclude,
    bool isRoot = false,
  }) async {
    // Check for skip markers.
    // Skip markers mean "don't include this folder AND don't descend into children"
    final skipMarker = !isRoot ? _skipMarkerIn(dir.path, toolBasename) : null;

    if (skipMarker != null) {
      _reportSkip(skipMarker, dir.path, toolBasename);
      // When --all is active, continue into skipped folders instead of returning.
      if (!ignoreSkipMarkers) {
        if (skipMarker == _SkipType.workspaceBoundary) {
          skippedWorkspaces.add(dir.path);
        }
        return;
      }
      stderr.writeln('Ignoring skip file, --no-skip active');
    }

    // No skip marker — add this directory
    results.add(FsFolder(path: dir.path));

    // Recursion semantics:
    // - Non-project directories (containers) are ALWAYS traversed to find
    //   projects. That is the purpose of --scan.
    // - Project directories (a pubspec.yaml, or the project file of any other
    //   language the build tools know: package.json, pyproject.toml, pom.xml,
    //   go.mod, Cargo.toml, a Makefile beside C/C++ sources, ...) are only
    //   recursed into when `recursive` is true. This controls whether nested
    //   projects inside a project (its test fixtures) are discovered.
    final isProjectDir = isProjectFolder(dir.path);
    if (!recursive && isProjectDir) return;

    // A project whose buildkit.yaml says `recursive: false` keeps the walk
    // out of its subfolders.
    if (_hasToolConfigRecursiveFalse(dir.path)) return;

    // Descend into subdirectories
    try {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final name = p.basename(entity.path);

          // Skip hidden directories
          if (name.startsWith('.')) continue;

          // Build outputs, caches, scratch copies (ztmp) and the AI state
          // mount (_ai) never hold projects to process — the same list
          // scanForDartProjects honours.
          if (kAlwaysSkipDirectories.contains(name)) continue;

          // Apply recursion exclusions
          if (_matchesAny(entity.path, name, recursionExclude)) continue;

          await _scanDirectory(
            entity,
            results,
            recursive: recursive,
            recursionExclude: recursionExclude,
          );
        }
      }
    } on FileSystemException {
      // Permission denied or other filesystem error - skip this directory
    }
  }

  /// Whether the folder's project file, `buildkit.yaml` (the one every tool
  /// on tom_build_base reads), says `recursive: false` at its top level: the
  /// project keeps every walk out of its subfolders (its test fixtures,
  /// samples), also with `-r`.
  bool _hasToolConfigRecursiveFalse(String dirPath) {
    final file = File(p.join(dirPath, 'buildkit.yaml'));
    if (!file.existsSync()) return false;
    try {
      final yaml = loadYaml(file.readAsStringSync());
      return yaml is YamlMap && yaml['recursive'] == false;
    } on Exception {
      // A file that does not parse says nothing about recursion; the build
      // commands report it where they read it.
      return false;
    }
  }

  /// Whether a folder at [path] named [name] matches one of the
  /// `--recursion-exclude` [patterns], so the scan does not descend into it.
  static bool matchesRecursionExclude(
    String path,
    String name,
    List<String> patterns,
  ) => _matchesAny(path, name, patterns);

  /// Check if path or name matches any of the patterns.
  ///
  /// Path and pattern are compared with `/` separators in the POSIX context,
  /// so a pattern written with `/` matches a Windows path as it matches a
  /// POSIX one.
  static bool _matchesAny(String rawPath, String name, List<String> patterns) {
    final path = rawPath.replaceAll(r'\', '/');
    for (final rawPattern in patterns) {
      final pattern = rawPattern.replaceAll(r'\', '/');
      // Try glob match on path
      try {
        final glob = Glob(pattern, context: p.posix);
        if (glob.matches(path) || glob.matches(name)) {
          return true;
        }
      } catch (_) {
        // Invalid glob pattern - try simple contains match
        if (path.contains(pattern) || name == pattern) {
          return true;
        }
      }
    }
    return false;
  }
}

/// Finds git repositories under a given root.
class GitRepoFinder {
  /// A finder that skips what project mode ([FolderScanner]) skips: hidden
  /// folders, [kAlwaysSkipDirectories], folders holding `tom_skip.yaml` or
  /// `{toolBasename}_skip.yaml`, and nested workspaces
  /// (`{toolBasename}_master.yaml` below the root). [ignoreSkipMarkers]
  /// (`--no-skip`) walks into the marked folders and nested workspaces.
  GitRepoFinder({
    this.toolBasename = 'buildkit',
    this.ignoreSkipMarkers = false,
  });

  /// Tool name of the tool-specific skip file and workspace marker.
  final String toolBasename;

  /// When true, the skip markers and nested workspaces do not stop the walk
  /// (`--no-skip`); hidden and always-skipped folders still do.
  final bool ignoreSkipMarkers;

  /// The nested workspaces the walks so far passed over, in the order met.
  final skippedWorkspaces = <String>[];

  /// Find all git repositories under [root] recursively. [root] itself is
  /// not checked for skip markers (its own workspace marker is its root).
  Future<List<FsFolder>> findAll(String root) async {
    final repos = <FsFolder>[];
    await _findGitRepos(Directory(root), repos, isRoot: true);
    return repos;
  }

  /// Find git repositories at workspace level (shallow search).
  ///
  /// This matches the behavior of legacy `_findGitRepositories` methods:
  /// - Checks [root] itself
  /// - Checks direct children of [root]
  /// - Checks direct children of [root]/xternal (if exists)
  /// - Checks direct children of [root]/xternal_apps (if exists)
  ///
  /// This is faster than [findAll] and typically what you want for
  /// workspace-level git operations.
  List<String> findWorkspaceRepos(String root) {
    final repos = <String>[];
    final rootDir = Directory(root);

    if (!rootDir.existsSync()) return repos;

    if (_isGitRepo(root)) {
      repos.add(root);
    }

    // Search in root and special directories
    final searchDirs = <String>[root];
    final xternalDir = Directory(p.join(root, 'xternal'));
    if (xternalDir.existsSync()) {
      searchDirs.add(xternalDir.path);
    }
    final xternalAppsDir = Directory(p.join(root, 'xternal_apps'));
    if (xternalAppsDir.existsSync()) {
      searchDirs.add(xternalAppsDir.path);
    }

    for (final searchDir in searchDirs) {
      try {
        for (final entity in Directory(searchDir).listSync()) {
          if (entity is Directory && entity.path != root) {
            if (_isGitRepo(entity.path)) {
              repos.add(entity.path);
            }
          }
        }
      } catch (_) {
        // Permission errors, etc.
      }
    }

    return repos;
  }

  bool _isGitRepo(String path) {
    final gitPath = p.join(path, '.git');
    return Directory(gitPath).existsSync() || File(gitPath).existsSync();
  }

  /// Find the topmost git repository by traversing up from [startPath].
  ///
  /// Traverses up the directory tree from [startPath] to the filesystem root,
  /// returning the path of the outermost (topmost) git repository found.
  /// Returns null if no git repository is found in the path.
  ///
  /// Example: If startPath is `/a/b/c` and both `/a` and `/a/b` are git repos,
  /// this returns `/a` (the topmost one).
  String? findTopRepo(String startPath) {
    var current = p.normalize(p.absolute(startPath));
    String? topRepo;

    while (true) {
      // Check if this is a git repo
      final gitDir = Directory(p.join(current, '.git'));
      final gitFile = File(p.join(current, '.git'));

      if (gitDir.existsSync() || gitFile.existsSync()) {
        topRepo = current;
      }

      // Move to parent directory
      final parent = p.dirname(current);
      if (parent == current) {
        // Reached root
        break;
      }
      current = parent;
    }

    return topRepo;
  }

  Future<void> _findGitRepos(
    Directory dir,
    List<FsFolder> results, {
    bool isRoot = false,
  }) async {
    if (!dir.existsSync()) return;
    // A marked folder, or a nested workspace, is neither listed nor entered
    // (as in project mode), a marked repository included.
    final skipMarker = isRoot ? null : _skipMarkerIn(dir.path, toolBasename);
    if (skipMarker != null) {
      _reportSkip(skipMarker, dir.path, toolBasename);
      if (!ignoreSkipMarkers) {
        if (skipMarker == _SkipType.workspaceBoundary) {
          skippedWorkspaces.add(dir.path);
        }
        return;
      }
      stderr.writeln('Ignoring skip file, --no-skip active');
    }

    // Check if this is a git repo
    final gitDir = Directory(p.join(dir.path, '.git'));
    final gitFile = File(p.join(dir.path, '.git'));

    if (gitDir.existsSync() || gitFile.existsSync()) {
      results.add(FsFolder(path: dir.path));
    }

    // Continue searching subdirectories
    try {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue; // Skip hidden
          if (kAlwaysSkipDirectories.contains(name)) continue;
          await _findGitRepos(entity, results);
        }
      }
    } on FileSystemException {
      // Permission denied - skip
    }
  }
}
