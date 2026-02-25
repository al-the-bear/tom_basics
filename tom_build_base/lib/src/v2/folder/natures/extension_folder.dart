import 'dart:io';

import '../run_folder.dart';

/// VS Code extension nature.
///
/// Detected when folder contains `package.json` with VS Code extension fields.
class VsCodeExtensionFolder extends RunFolder {
  /// Extension name from package.json.
  final String extensionName;

  /// Extension version.
  final String? version;

  /// Extension display name.
  final String? displayName;

  VsCodeExtensionFolder(
    super.fsFolder, {
    required this.extensionName,
    this.version,
    this.displayName,
  });

  /// Check if a folder is a VS Code extension.
  static bool isVsCodeExtension(String dirPath) {
    final packageJson = File('$dirPath/package.json');
    if (!packageJson.existsSync()) return false;
    // Basic check - real detection should parse JSON
    final content = packageJson.readAsStringSync();
    return content.contains('"engines"') && content.contains('"vscode"');
  }

  @override
  String toString() => 'VsCodeExtensionFolder($path, name: $extensionName)';
}

/// TypeScript project nature.
///
/// Detected when folder contains `tsconfig.json`.
class TypeScriptFolder extends RunFolder {
  /// Project name from package.json.
  final String? projectName;

  /// Whether this is a Node.js project.
  final bool isNodeProject;

  TypeScriptFolder(
    super.fsFolder, {
    this.projectName,
    this.isNodeProject = false,
  });

  /// Check if a folder is a TypeScript project.
  static bool isTypeScriptProject(String dirPath) {
    return File('$dirPath/tsconfig.json').existsSync();
  }

  @override
  String toString() => 'TypeScriptFolder($path, name: $projectName)';
}
