import 'package:path/path.dart' as p;

/// Checks if [targetPath] is contained within [basePath].
/// Both paths are normalized to absolute paths for comparison.
bool isPathContained(String targetPath, String basePath) {
  final normalizedTarget = p.normalize(p.absolute(targetPath));
  final normalizedBase = p.normalize(p.absolute(basePath));
  return normalizedTarget == normalizedBase ||
      normalizedTarget.startsWith('$normalizedBase${p.separator}');
}

/// Validates that path-related options are contained within the given base path.
/// 
/// Returns an error message if validation fails, or null if valid.
/// 
/// [project] - Optional project path to validate
/// [projects] - List of project glob patterns to validate
/// [scan] - Optional scan path to validate
/// [config] - Optional config file path to validate
/// [basePath] - The base path that all other paths must be within
String? validatePathContainment({
  String? project,
  List<String> projects = const [],
  String? scan,
  String? config,
  required String basePath,
}) {
  final normalizedBase = p.normalize(p.absolute(basePath));

  // Validate project path
  if (project != null) {
    if (!isPathContained(project, normalizedBase)) {
      return 'project path "$project" must be within "$normalizedBase"';
    }
  }

  // Validate projects patterns
  for (final pattern in projects) {
    // Absolute paths outside base are not allowed
    if (p.isAbsolute(pattern) && !isPathContained(pattern, normalizedBase)) {
      return 'projects pattern "$pattern" must be within "$normalizedBase"';
    }
    // Patterns starting with .. are not allowed
    if (pattern.startsWith('..')) {
      return 'projects pattern "$pattern" cannot reference parent directories';
    }
  }

  // Validate scan path
  if (scan != null) {
    if (!isPathContained(scan, normalizedBase)) {
      return 'scan path "$scan" must be within "$normalizedBase"';
    }
  }

  // Validate config path
  if (config != null) {
    if (!isPathContained(config, normalizedBase)) {
      return 'config path "$config" must be within "$normalizedBase"';
    }
  }

  return null; // Valid
}
