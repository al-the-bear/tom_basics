/// Lookup table for repository IDs.
///
/// Maps repository short IDs to their folder names for filtering.
/// Values sourced from _copilot_guidelines/projects_and_repos.md.
class RepositoryIdLookup {
  /// Repository ID to folder name mapping.
  ///
  /// Keys are uppercase short IDs, values are the folder/submodule names.
  static const Map<String, String> _idToName = {
    // Main repository
    'TOM': 'tom',
    // External modules
    'BSC': 'tom_module_basics',
    'D4': 'tom_module_d4rt',
    'RFL': 'tom_module_reflection',
    'DIST': 'tom_module_distributed',
    'VSC': 'tom_module_vscode',
    // Apps
    'PASS': 'tom_app_tompass',
    'WW': 'tom_app_webwork',
  };

  /// Resolves a repository ID or name to the actual folder name.
  ///
  /// Returns [value] unchanged if not found as an ID.
  /// Resolution order:
  /// 1. Check if value is a repository ID (case-insensitive)
  /// 2. Return value unchanged (assume it's already a name)
  static String resolveToName(String value) {
    // Check if it's a known ID (case-insensitive)
    final upperValue = value.toUpperCase();
    if (_idToName.containsKey(upperValue)) {
      return _idToName[upperValue]!;
    }
    // Return unchanged - assume it's already a name or path
    return value;
  }

  /// Check if a value matches a repository ID (case-insensitive).
  static bool isRepositoryId(String value) {
    return _idToName.containsKey(value.toUpperCase());
  }

  /// Get all known repository IDs.
  static List<String> get allIds => _idToName.keys.toList();

  /// Get all known repository names.
  static List<String> get allNames => _idToName.values.toList();
}
