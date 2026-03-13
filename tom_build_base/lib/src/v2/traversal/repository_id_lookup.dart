import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Lookup helper for repository IDs.
///
/// Reads metadata from `tom_repository.yaml` files in the workspace and
/// resolves repository IDs to repository names for module filtering.
class RepositoryIdLookup {
  static const _metadataFileName = 'tom_repository.yaml';

  static final Map<String, Map<String, String>> _cacheByRoot = {};

  /// Resolves a repository ID or name to the actual folder name.
  ///
  /// Returns [value] unchanged if not found as an ID.
  /// Resolution order:
  /// 1. Check if value is a repository ID from `tom_repository.yaml`
  /// 2. Return value unchanged (assume it's already a name)
  static String resolveToName(String value, {String? executionRoot}) {
    final idToName = _loadIdToNameMap(executionRoot);
    final upperValue = value.toUpperCase();
    if (idToName.containsKey(upperValue)) {
      return idToName[upperValue]!;
    }
    // Return unchanged - assume it's already a name or path
    return value;
  }

  /// Check if a value matches a repository ID (case-insensitive).
  static bool isRepositoryId(String value, {String? executionRoot}) {
    final idToName = _loadIdToNameMap(executionRoot);
    return idToName.containsKey(value.toUpperCase());
  }

  /// Get all known repository IDs.
  static List<String> allIds({String? executionRoot}) {
    final idToName = _loadIdToNameMap(executionRoot);
    return idToName.keys.toList();
  }

  /// Get all known repository names.
  static List<String> allNames({String? executionRoot}) {
    final idToName = _loadIdToNameMap(executionRoot);
    return idToName.values.toList();
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

  static String _normalizeRoot(String root) =>
      p.normalize(p.absolute(root));

  static Map<String, String> _loadIdToNameMap(String? executionRoot) {
    final rootPath = _normalizeRoot(executionRoot ?? Directory.current.path);

    final cached = _cacheByRoot[rootPath];
    if (cached != null) {
      return cached;
    }

    final map = <String, String>{};
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
    };

    for (final part in parts) {
      if (ignored.contains(part)) {
        return true;
      }
    }

    return false;
  }

  static void _registerMetadata(File metadataFile, Map<String, String> map) {
    try {
      final raw = loadYaml(metadataFile.readAsStringSync());
      if (raw is! YamlMap) return;

      final id = raw['repository_id']?.toString().trim();
      if (id == null || id.isEmpty) return;

      final configuredName = raw['name']?.toString().trim();
      final fallbackName = p.basename(p.dirname(metadataFile.path));
      final resolvedName =
          (configuredName == null || configuredName.isEmpty)
              ? fallbackName
              : configuredName;

      map[id.toUpperCase()] = resolvedName;
    } catch (_) {
      // Invalid yaml or unreadable file -> ignore this metadata file.
    }
  }
}
