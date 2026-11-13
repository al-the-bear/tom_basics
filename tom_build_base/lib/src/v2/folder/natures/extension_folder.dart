import 'dart:io';

import '../run_folder.dart';
import 'language_folders.dart';

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
class TypeScriptFolder extends LanguageProjectFolder {
  /// Whether this is a Node.js project (`main` or `scripts` in package.json).
  final bool isNodeProject;

  /// The `scripts` of `package.json` by name.
  final Map<String, String> scripts;

  TypeScriptFolder(
    super.fsFolder, {
    super.projectName,
    super.version,
    this.isNodeProject = false,
    this.scripts = const {},
  });

  /// Check if a folder is a TypeScript project.
  static bool isTypeScriptProject(String dirPath) {
    return File('$dirPath/tsconfig.json').existsSync();
  }

  @override
  String get language => 'typescript';

  @override
  String get projectFile => 'tsconfig.json';
}
