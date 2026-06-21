// Copyright (c) 2024-2026. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the shared **Tom tool-cache directory** — a common location for
/// build artefacts that can be reused across projects and tools.
///
/// Analyzer summaries are the first (and today the only) artefact stored here,
/// but the directory is deliberately generic so other Tom build tools can
/// share it for their own reusable outputs. Consumers should write their
/// artefacts into a named sub-directory of the resolved root (the analyzer
/// summary cache uses `analyzer-cache/`) so different artefact kinds never
/// collide.
///
/// ## Resolution order
///
/// The first branch that applies wins:
///
/// 1. **`TOM_TOOL_CACHE` environment variable.** When set to a non-empty
///    value it is used verbatim (normalised to an absolute path). This is the
///    explicit override — point it at a fast disk, a shared CI cache, or a
///    RAM-backed directory.
/// 2. **An existing `.tom/tom_tool_cache` directory in an ancestor.** Walking
///    up from [resolve]'s `startDirectory` through each parent, the first
///    directory that contains `.tom/tom_tool_cache` wins. A workspace opts
///    into a repo-local shared cache simply by creating that directory.
/// 3. **The Dart tool directory fallback.** A `tom_tool_cache` sub-directory of
///    the platform's default Dart tool directory (see
///    [defaultDartToolDirectory]) — e.g. `~/.config/dart/tom_tool_cache` on
///    Linux. This is the machine-global fallback.
///
/// [resolve] only *reads* the filesystem (existence checks for branch 2); it
/// never creates a directory. Callers create the resolved directory lazily the
/// first time they write to it.
abstract final class ToolCacheLocator {
  /// Environment variable that overrides the tool-cache location (branch 1).
  static const String envVariable = 'TOM_TOOL_CACHE';

  /// Directory name used both for the ancestor marker (`.tom/<name>`, branch 2)
  /// and the Dart-tool-directory fallback sub-directory (branch 3).
  static const String cacheDirName = 'tom_tool_cache';

  /// Resolves the tool-cache root directory.
  ///
  /// [startDirectory] is where the ancestor search (branch 2) begins; it
  /// defaults to the current working directory. Pass a project or workspace
  /// root to find that tree's repo-local cache.
  ///
  /// [environment] overrides the process environment — primarily for tests.
  /// Defaults to [Platform.environment].
  ///
  /// [dartToolDirectory] overrides the branch-3 base directory — primarily for
  /// tests, so they never touch the real per-user Dart tool directory. Defaults
  /// to [defaultDartToolDirectory].
  static String resolve({
    String? startDirectory,
    Map<String, String>? environment,
    String? dartToolDirectory,
  }) {
    final env = environment ?? Platform.environment;

    // 1. Explicit environment override.
    final override = env[envVariable];
    if (override != null && override.trim().isNotEmpty) {
      return p.normalize(p.absolute(override.trim()));
    }

    // 2. Existing `.tom/tom_tool_cache` in an ancestor directory.
    final start = p.normalize(p.absolute(startDirectory ?? Directory.current.path));
    final ancestorHit = _findInAncestors(start);
    if (ancestorHit != null) return ancestorHit;

    // 3. Fallback under the platform's Dart tool directory.
    final toolDir = dartToolDirectory ?? defaultDartToolDirectory(env);
    return p.join(toolDir, cacheDirName);
  }

  /// Walks up from [startDirectory] returning the first existing
  /// `<ancestor>/.tom/tom_tool_cache` directory, or `null` if none exists up to
  /// the filesystem root.
  static String? _findInAncestors(String startDirectory) {
    var dir = startDirectory;
    while (true) {
      final candidate = p.join(dir, '.tom', cacheDirName);
      if (Directory(candidate).existsSync()) return candidate;
      final parent = p.dirname(dir);
      if (parent == dir) return null; // Reached the filesystem root.
      dir = parent;
    }
  }

  /// The platform's default directory for Dart tool data.
  ///
  /// Mirrors the layout used by `package:cli_util`'s
  /// `applicationConfigHome('dart')` without taking the dependency:
  ///
  /// | Platform | Directory |
  /// | -------- | --------- |
  /// | Windows  | `%APPDATA%\dart` |
  /// | macOS    | `~/Library/Application Support/dart` |
  /// | Linux/POSIX | `$XDG_CONFIG_HOME/dart` or `~/.config/dart` |
  ///
  /// When the expected environment variables are absent it falls back to a
  /// `.dart` directory under the current working directory so resolution never
  /// throws.
  static String defaultDartToolDirectory([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;

    if (Platform.isWindows) {
      final appData = env['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, 'dart');
      }
      final userProfile = env['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        return p.join(userProfile, 'AppData', 'Roaming', 'dart');
      }
      return p.join(Directory.current.path, '.dart');
    }

    if (Platform.isMacOS) {
      final home = env['HOME'];
      if (home != null && home.isNotEmpty) {
        return p.join(home, 'Library', 'Application Support', 'dart');
      }
      return p.join(Directory.current.path, '.dart');
    }

    // Linux and other POSIX systems follow the XDG base-directory spec.
    final xdg = env['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.isNotEmpty) {
      return p.join(xdg, 'dart');
    }
    final home = env['HOME'];
    if (home != null && home.isNotEmpty) {
      return p.join(home, '.config', 'dart');
    }
    return p.join(Directory.current.path, '.dart');
  }
}
