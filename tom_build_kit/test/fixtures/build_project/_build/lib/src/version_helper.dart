// Version helper for tools built from _build project
// This provides a centralized version display for tools that don't
// have their own version generation.

import 'version.versioner.dart';

/// Display version information for a tool
void printToolVersion(String toolName) {
  print('$toolName ${TomToolsVersionInfo.versionLong}');
}

/// Get version string for a tool
String getToolVersion() {
  return TomToolsVersionInfo.versionLong;
}

/// Check if version argument is present
bool isVersionRequest(List<String> args) {
  return args.contains('version') || 
         args.contains('-v') || 
         args.contains('--version') ||
         args.contains('-version');
}
