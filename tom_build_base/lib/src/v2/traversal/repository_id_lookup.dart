import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Lookup helper for repository IDs.
///
/// Reads metadata from `tom_repository.yaml` files in the workspace and
/// resolves repository IDs to repository names and folders for module
/// filtering.
class RepositoryIdLookup {
  static const _metadataFileName = 'tom_repository.yaml';

  static final Map<String, Map<String, _Repository>> _cacheByRoot = {};

  /// Resolves a repository ID (case-insensitive) to the repository's
  /// configured `name:` (else its folder name); any other [value] is returned
  /// unchanged. The configured name may differ from the folder name
  /// (`webwork` in `app_webwork`); [resolveToFolder] gives the folder.
  static String resolveToName(String value, {String? executionRoot}) {
    final repository = _load(executionRoot)[value.toUpperCase()];
    // Not an ID: return unchanged, it is already a name or path.
    return repository?.name ?? value;
  }

  /// The folder of the repository whose ID, or else configured `name:`, is
  /// [value] (both case-insensitive): the folder holding its
  /// `tom_repository.yaml`. Null when no repository has that ID or name.
  static String? resolveToFolder(String value, {String? executionRoot}) {
    final repositories = _load(executionRoot);
    final byId = repositories[value.toUpperCase()];
    if (byId != null) return byId.folder;
    final name = value.toLowerCase();
    for (final repository in repositories.values) {
      if (repository.name.toLowerCase() == name) return repository.folder;
    }
    return null;
  }

  /// Check if a value matches a repository ID (case-insensitive).
  static bool isRepositoryId(String value, {String? executionRoot}) {
    return _load(executionRoot).containsKey(value.toUpperCase());
  }

  /// Get all known repository IDs.
  static List<String> allIds({String? executionRoot}) {
    return _load(executionRoot).keys.toList();
  }

  /// Get all known repository names.
  static List<String> allNames({String? executionRoot}) {
    return _load(executionRoot).values.map((r) => r.name).toList();
  }

  /// Clears cached repository metadata lookups.
  ///
  /// Intended for tests or environments where metadata files changed during
  /// runtime and should be reloaded.
  static void clearCache({String? executionRoot}) {
    if (executionRoot == null) {
      _cacheByRoot.clear();
      return;
    }
    final rootKey = _normalizeRoot(executionRoot);
    _cacheByRoot.remove(rootKey);
  }

  static String _normalizeRoot(String root) => p.normalize(p.absolute(root));

  static Map<String, _Repository> _load(String? executionRoot) {
    final rootPath = _normalizeRoot(executionRoot ?? Directory.current.path);

    final cached = _cacheByRoot[rootPath];
    if (cached != null) {
      return cached;
    }

    final map = <String, _Repository>{};
    final rootDir = Directory(rootPath);
    if (!rootDir.existsSync()) {
      _cacheByRoot[rootPath] = map;
      return map;
    }

    final metadataFiles = _discoverMetadataFiles(rootDir);
    for (final file in metadataFiles) {
      _registerMetadata(file, map);
    }

    _cacheByRoot[rootPath] = map;
    return map;
  }

  static List<File> _discoverMetadataFiles(Directory rootDir) {
    final result = <File>[];

    try {
      final entities = rootDir.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is! File) continue;
        if (p.basename(entity.path) != _metadataFileName) continue;
        if (_isInIgnoredPath(entity.path)) continue;
        result.add(entity);
      }
    } on FileSystemException {
      // Ignore scan failures and fall back to whatever was discovered.
    }

    return result;
  }

  static bool _isInIgnoredPath(String filePath) {
    final normalizedPath = p.normalize(filePath);
    final parts = p.split(normalizedPath).map((x) => x.toLowerCase()).toList();

    const ignored = {
      '.git',
      '.dart_tool',
      'build',
      'node_modules',
      '.pub-cache',
      '.pub',
      '__pycache__',
      // Workspace-wide scratch dir (gitignored) — never holds shippable repos.
      'ztmp',
    };

    for (final part in parts) {
      if (ignored.contains(part)) {
        return true;
      }
    }

    return false;
  }

  static void _registerMetadata(
    File metadataFile,
    Map<String, _Repository> map,
  ) {
    try {
      final raw = loadYaml(metadataFile.readAsStringSync());
      if (raw is! YamlMap) return;

      final id = raw['repository_id']?.toString().trim();
      if (id == null || id.isEmpty) return;

      final configuredName = raw['name']?.toString().trim();
      final folder = p.normalize(p.absolute(p.dirname(metadataFile.path)));
      final fallbackName = p.basename(folder);
      final resolvedName = (configuredName == null || configuredName.isEmpty)
          ? fallbackName
          : configuredName;

      map[id.toUpperCase()] = (name: resolvedName, folder: folder);
    } catch (_) {
      // Invalid yaml or unreadable file -> ignore this metadata file.
    }
  }
}

/// A repository of the workspace: its configured name and its folder.
typedef _Repository = ({String name, String folder});
