// Copyright (c) 2024-2026. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the **Tom tool-cache directory** — a *workspace-local* location for
/// build artefacts that can be reused across the projects and tools of a single
/// workspace.
///
/// Analyzer summaries are the first (and today the only) artefact stored here,
/// but the directory is deliberately generic so other Tom build tools can share
/// it for their own reusable outputs. Consumers should write their artefacts
/// into a named sub-directory of the resolved root (the analyzer summary cache
/// uses `analyzer-cache/`) so different artefact kinds never collide.
///
/// ## Resolution order
///
/// The first branch that applies wins:
///
/// 1. **`TOM_TOOL_CACHE` environment variable.** When set to a non-empty value
///    it is used verbatim (normalised to an absolute path). This is the explicit
///    override — point it at a fast disk, a shared CI cache, or a RAM-backed
///    directory.
/// 2. **The workspace-root `.tom` directory.** Walking up from [resolve]'s
///    `startDirectory`, the first ancestor that is a **workspace root** — a
///    directory containing one of the [workspaceRootMarkers] (`tom_workspace.yaml`
///    or `.tom_metadata/tom_master.yaml`) — wins, and its `.tom` sub-directory is
///    the cache root. This deliberately identifies the *workspace* root rather
///    than the nearest `.tom`, so nested project-level `.tom` directories never
///    fragment the cache: every tool in the tree shares the one
///    `<workspace>/.tom/analyzer-cache/`.
/// 3. **Workspace-local fallback.** When no workspace-root ancestor is found the
///    cache root is `<startDirectory>/.tom`. The resolver **never** falls back to
///    a machine-global location such as `~/.config/dart` — the cache is always
///    inside the workspace tree.
///
/// [resolve] only *reads* the filesystem (existence checks for branch 2); it
/// never creates a directory. Callers create the resolved directory lazily the
/// first time they write to it.
abstract final class ToolCacheLocator {
  /// Environment variable that overrides the tool-cache location (branch 1).
  static const String envVariable = 'TOM_TOOL_CACHE';

  /// Name of the cache-root sub-directory inside a workspace root (branch 2) and
  /// of the workspace-local fallback directory (branch 3).
  static const String workspaceCacheDirName = '.tom';

  /// Marker files whose presence in a directory identifies it as a **workspace
  /// root** (branch 2). Any one of them is sufficient. Both are committed at the
  /// Tom workspace root, so the search reliably resolves to the workspace's
  /// `.tom` cache and skips nested project-level `.tom` directories.
  static const List<String> workspaceRootMarkers = <String>[
    'tom_workspace.yaml',
    '.tom_metadata/tom_master.yaml',
  ];

  /// Resolves the tool-cache root directory.
  ///
  /// [startDirectory] is where the ancestor search (branch 2) begins; it
  /// defaults to the current working directory. Pass a project or workspace
  /// root to find that tree's workspace `.tom` cache.
  ///
  /// [environment] overrides the process environment — primarily for tests.
  /// Defaults to [Platform.environment].
  static String resolve({
    String? startDirectory,
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;

    // 1. Explicit environment override.
    final override = env[envVariable];
    if (override != null && override.trim().isNotEmpty) {
      return p.normalize(p.absolute(override.trim()));
    }

    final start =
        p.normalize(p.absolute(startDirectory ?? Directory.current.path));

    // 2. Nearest ancestor workspace root → its `.tom`.
    final workspaceRoot = _findWorkspaceRoot(start);
    if (workspaceRoot != null) {
      return p.join(workspaceRoot, workspaceCacheDirName);
    }

    // 3. Workspace-local fallback — always inside the tree, never a
    //    machine-global directory.
    return p.join(start, workspaceCacheDirName);
  }

  /// Walks up from [startDirectory] returning the first ancestor that contains a
  /// [workspaceRootMarkers] entry, or `null` if none exists up to the filesystem
  /// root.
  static String? _findWorkspaceRoot(String startDirectory) {
    var dir = startDirectory;
    while (true) {
      for (final marker in workspaceRootMarkers) {
        final markerPath = p.join(dir, marker);
        if (FileSystemEntity.typeSync(markerPath) !=
            FileSystemEntityType.notFound) {
          return dir;
        }
      }
      final parent = p.dirname(dir);
      if (parent == dir) return null; // Reached the filesystem root.
      dir = parent;
    }
  }
}
