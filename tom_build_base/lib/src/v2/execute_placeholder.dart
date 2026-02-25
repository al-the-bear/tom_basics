import 'dart:io';

import 'package:path/path.dart' as p;

import 'folder/fs_folder.dart';
import 'folder/run_folder.dart';
import 'folder/natures/dart_project_folder.dart';
import 'folder/natures/git_folder.dart';
import 'folder/natures/extension_folder.dart';
import 'folder/natures/buildkit_folder.dart';
import 'traversal/command_context.dart';

/// Exception thrown when a placeholder cannot be resolved.
class UnresolvedPlaceholderException implements Exception {
  /// The placeholder name that couldn't be resolved.
  final String placeholder;

  /// The folder path where resolution failed.
  final String folderPath;

  /// Optional additional message.
  final String? message;

  UnresolvedPlaceholderException(
    this.placeholder,
    this.folderPath, {
    this.message,
  });

  @override
  String toString() {
    final msg = message != null ? ': $message' : '';
    return 'Unresolved placeholder \${$placeholder} in $folderPath$msg';
  }
}

/// Context for resolving execute command placeholders.
///
/// Holds all information needed to resolve placeholders for a specific folder
/// during workspace traversal.
class ExecutePlaceholderContext {
  /// Workspace root path (absolute).
  final String rootPath;

  /// Current folder being processed.
  final FsFolder folder;

  /// Current platform info.
  final String currentOs;
  final String currentArch;
  final String currentPlatform;

  ExecutePlaceholderContext({
    required this.rootPath,
    required this.folder,
    String? currentOs,
    String? currentArch,
  }) : currentOs = currentOs ?? Platform.operatingSystem,
       currentArch = currentArch ?? _detectArch(),
       currentPlatform =
           '${_normalizeOs(currentOs ?? Platform.operatingSystem)}-'
           '${currentArch ?? _detectArch()}';

  /// Create from a [CommandContext] during traversal.
  ///
  /// Copies natures from the context into the FsFolder so placeholder
  /// resolution can access them.
  factory ExecutePlaceholderContext.fromCommandContext(
    CommandContext context,
    String rootPath,
  ) {
    final folder = context.fsFolder;
    folder.natures.clear();
    folder.natures.addAll(context.natures);
    return ExecutePlaceholderContext(rootPath: rootPath, folder: folder);
  }

  static String _detectArch() {
    final dartExe = Platform.resolvedExecutable;
    if (dartExe.contains('arm64') || dartExe.contains('aarch64')) {
      return 'arm64';
    }
    if (dartExe.contains('arm')) {
      return 'armhf';
    }
    return 'x64';
  }

  static String _normalizeOs(String os) {
    switch (os) {
      case 'macos':
        return 'darwin';
      case 'windows':
        return 'win32';
      default:
        return os;
    }
  }

  /// Folder path (absolute).
  String get folderPath => folder.path;

  /// Folder name (basename).
  String get folderName => folder.name;

  /// Folder path relative to root.
  String get folderRelative => p.relative(folder.path, from: rootPath);

  /// List of detected natures for the folder.
  List<dynamic> get natures => folder.natures;

  /// Get first nature of type T, or null if not found.
  T? getNature<T extends RunFolder>() {
    for (final nature in natures) {
      if (nature is T) return nature;
    }
    return null;
  }

  /// Check if folder has a nature of type T.
  bool hasNature<T extends RunFolder>() => getNature<T>() != null;

  // Nature existence checks
  bool get hasDart => hasNature<DartProjectFolder>();
  bool get hasFlutter => hasNature<FlutterProjectFolder>();
  bool get hasPackage => hasNature<DartPackageFolder>();
  bool get hasConsole => hasNature<DartConsoleFolder>();
  bool get hasGit => hasNature<GitFolder>();
  bool get hasTypeScript => hasNature<TypeScriptFolder>();
  bool get hasVsCodeExtension => hasNature<VsCodeExtensionFolder>();
  bool get hasBuildkit => hasNature<BuildkitFolder>();
  bool get hasTomProject => hasNature<TomBuildFolder>();

  // Nature accessors
  DartProjectFolder? get dart => getNature<DartProjectFolder>();
  FlutterProjectFolder? get flutter => getNature<FlutterProjectFolder>();
  DartPackageFolder? get package => getNature<DartPackageFolder>();
  DartConsoleFolder? get console => getNature<DartConsoleFolder>();
  GitFolder? get git => getNature<GitFolder>();
  TypeScriptFolder? get typescript => getNature<TypeScriptFolder>();
  VsCodeExtensionFolder? get vscodeExtension =>
      getNature<VsCodeExtensionFolder>();
  BuildkitFolder? get buildkit => getNature<BuildkitFolder>();
  TomBuildFolder? get tomProject => getNature<TomBuildFolder>();
}

/// Resolves placeholders in command strings for execute commands.
///
/// Supports:
/// - Path placeholders: `${root}`, `${folder}`, `${folder.name}`, `${folder.relative}`
/// - Platform placeholders: `${current-os}`, `${current-arch}`, `${current-platform}`
/// - Nature existence: `${dart.exists}`, `${flutter.exists}`, etc.
/// - Nature attributes: `${dart.name}`, `${git.branch}`, etc.
/// - Ternary expressions: `${condition?(true-value):(false-value)}`
class ExecutePlaceholderResolver {
  /// All known boolean placeholders that support ternary syntax.
  static const booleanPlaceholders = {
    'dart.exists',
    'flutter.exists',
    'package.exists',
    'console.exists',
    'git.exists',
    'typescript.exists',
    'vscode-extension.exists',
    'buildkit.exists',
    'tom-project.exists',
    'dart.publishable',
    'flutter.isPlugin',
    'git.isSubmodule',
    'git.hasChanges',
  };

  /// Resolve a placeholder value from context.
  ///
  /// Returns the resolved value, or throws [UnresolvedPlaceholderException]
  /// if the placeholder cannot be resolved (e.g., accessing dart.name when
  /// there's no Dart project).
  static String resolvePlaceholder(
    String placeholder,
    ExecutePlaceholderContext ctx,
  ) {
    // Path placeholders
    switch (placeholder) {
      case 'root':
        return ctx.rootPath;
      case 'folder':
        return ctx.folderPath;
      case 'folder.name':
        return ctx.folderName;
      case 'folder.relative':
        return ctx.folderRelative;

      // Platform placeholders
      case 'current-os':
        return ctx.currentOs;
      case 'current-arch':
        return ctx.currentArch;
      case 'current-platform':
        return ctx.currentPlatform;

      // Nature existence (boolean)
      case 'dart.exists':
        return ctx.hasDart.toString();
      case 'flutter.exists':
        return ctx.hasFlutter.toString();
      case 'package.exists':
        return ctx.hasPackage.toString();
      case 'console.exists':
        return ctx.hasConsole.toString();
      case 'git.exists':
        return ctx.hasGit.toString();
      case 'typescript.exists':
        return ctx.hasTypeScript.toString();
      case 'vscode-extension.exists':
        return ctx.hasVsCodeExtension.toString();
      case 'buildkit.exists':
        return ctx.hasBuildkit.toString();
      case 'tom-project.exists':
        return ctx.hasTomProject.toString();

      // Dart attributes
      case 'dart.name':
        final dart = ctx.dart;
        if (dart == null) {
          throw UnresolvedPlaceholderException(
            placeholder,
            ctx.folderPath,
            message: 'not a Dart project',
          );
        }
        return dart.projectName;
      case 'dart.version':
        final dart = ctx.dart;
        if (dart == null) {
          throw UnresolvedPlaceholderException(
            placeholder,
            ctx.folderPath,
            message: 'not a Dart project',
          );
        }
        return dart.version ?? '';
      case 'dart.publishable':
        final dart = ctx.dart;
        if (dart == null) {
          throw UnresolvedPlaceholderException(
            placeholder,
            ctx.folderPath,
            message: 'not a Dart project',
          );
        }
        return dart.isPublishable.toString();

      // Flutter attributes
      case 'flutter.platforms':
        final flutter = ctx.flutter;
        if (flutter == null) {
          throw UnresolvedPlaceholderException(
            placeholder,
            ctx.folderPath,
            message: 'not a Flutter project',
          );
        }
        return flutter.platforms.join(',');
      case 'flutter.isPlugin':
        final flutter = ctx.flutter;
        if (flutter == null) {
          throw UnresolvedPlaceholderException(
            placeholder,
            ctx.folderPath,
            message: 'not a Flutter project',
          );
        }
        return flutter.isPlugin.toString();

      // Git attributes
      case 'git.branch':
        final git = ctx.git;
        if (git == null) {
          throw UnresolvedPlaceholderException(
            placeholder,
            ctx.folderPath,
            message: 'not a git repository',
          );
        }
        return git.currentBranch;
      case 'git.isSubmodule':
        final git = ctx.git;
        if (git == null) {
          throw UnresolvedPlaceholderException(
            placeholder,
            ctx.folderPath,
            message: 'not a git repository',
          );
        }
        return git.isSubmodule.toString();
      case 'git.hasChanges':
        final git = ctx.git;
        if (git == null) {
          throw UnresolvedPlaceholderException(
            placeholder,
            ctx.folderPath,
            message: 'not a git repository',
          );
        }
        return git.hasUncommittedChanges.toString();
      case 'git.remotes':
        final git = ctx.git;
        if (git == null) {
          throw UnresolvedPlaceholderException(
            placeholder,
            ctx.folderPath,
            message: 'not a git repository',
          );
        }
        return git.remotes.join(',');

      // VS Code extension attributes
      case 'vscode.name':
        final vscode = ctx.vscodeExtension;
        if (vscode == null) {
          throw UnresolvedPlaceholderException(
            placeholder,
            ctx.folderPath,
            message: 'not a VS Code extension',
          );
        }
        return vscode.extensionName;
      case 'vscode.version':
        final vscode = ctx.vscodeExtension;
        if (vscode == null) {
          throw UnresolvedPlaceholderException(
            placeholder,
            ctx.folderPath,
            message: 'not a VS Code extension',
          );
        }
        return vscode.version ?? '';

      default:
        throw UnresolvedPlaceholderException(
          placeholder,
          ctx.folderPath,
          message: 'unknown placeholder',
        );
    }
  }

  /// Resolve a boolean placeholder value.
  ///
  /// Returns true/false based on the placeholder, or throws if the placeholder
  /// is not a known boolean placeholder.
  static bool resolveBooleanPlaceholder(
    String placeholder,
    ExecutePlaceholderContext ctx,
  ) {
    final value = resolvePlaceholder(placeholder, ctx);
    return value == 'true';
  }

  /// Check if a placeholder name is a known boolean placeholder.
  static bool isBooleanPlaceholder(String placeholder) {
    return booleanPlaceholders.contains(placeholder);
  }

  /// Regex to match `${placeholder}` (non-ternary).
  static final _simplePlaceholderRegex = RegExp(r'\$\{([a-zA-Z0-9._-]+)\}');

  /// Regex to match `${placeholder?(true):(false)}` (ternary).
  static final _ternaryPlaceholderRegex = RegExp(
    r'\$\{([a-zA-Z0-9._-]+)\?\(([^)]*)\):\(([^)]*)\)\}',
  );

  /// Resolve all placeholders in a command string.
  ///
  /// Throws [UnresolvedPlaceholderException] if any placeholder cannot be
  /// resolved for the current context, unless [skipUnknown] is true.
  ///
  /// When [skipUnknown] is true, unrecognized placeholders are left as-is
  /// in the output string. This is useful when other resolvers will handle
  /// remaining placeholders (e.g., compiler-specific `${file}` placeholders).
  static String resolveCommand(
    String command,
    ExecutePlaceholderContext ctx, {
    bool skipUnknown = false,
  }) {
    var result = command;

    // First, resolve ternary expressions
    result = result.replaceAllMapped(_ternaryPlaceholderRegex, (match) {
      final placeholder = match.group(1)!;
      final trueValue = match.group(2)!;
      final falseValue = match.group(3)!;

      // Check if it's a boolean placeholder
      if (!isBooleanPlaceholder(placeholder)) {
        if (skipUnknown) return match.group(0)!;
        throw UnresolvedPlaceholderException(
          placeholder,
          ctx.folderPath,
          message: 'not a boolean placeholder (cannot use ternary syntax)',
        );
      }

      final boolValue = resolveBooleanPlaceholder(placeholder, ctx);
      return boolValue ? trueValue : falseValue;
    });

    // Then, resolve simple placeholders
    result = result.replaceAllMapped(_simplePlaceholderRegex, (match) {
      final placeholder = match.group(1)!;
      try {
        return resolvePlaceholder(placeholder, ctx);
      } on UnresolvedPlaceholderException {
        if (skipUnknown) return match.group(0)!;
        rethrow;
      }
    });

    return result;
  }

  /// Check if a condition placeholder is satisfied.
  ///
  /// The [condition] should be a boolean placeholder name without `${}` wrapper.
  /// Returns true if the condition is satisfied, false otherwise.
  /// Throws [UnresolvedPlaceholderException] if not a valid boolean placeholder.
  static bool checkCondition(String condition, ExecutePlaceholderContext ctx) {
    if (!isBooleanPlaceholder(condition)) {
      throw UnresolvedPlaceholderException(
        condition,
        ctx.folderPath,
        message: 'not a boolean placeholder (invalid condition)',
      );
    }
    return resolveBooleanPlaceholder(condition, ctx);
  }

  /// Get list of all available placeholders with descriptions.
  static Map<String, String> getPlaceholderHelp() {
    return {
      // Path
      'root': 'Workspace root (absolute)',
      'folder': 'Current folder (absolute)',
      'folder.name': 'Folder basename',
      'folder.relative': 'Folder relative to root',

      // Platform
      'current-os': 'Operating system (linux, macos, windows)',
      'current-arch': 'Architecture (x64, arm64)',
      'current-platform': 'Platform string (darwin-arm64, linux-x64, etc.)',

      // Nature existence (boolean)
      'dart.exists': 'true if Dart project (pubspec.yaml)',
      'flutter.exists': 'true if Flutter project',
      'package.exists': 'true if Dart package (lib/src/)',
      'console.exists': 'true if Dart console app (bin/)',
      'git.exists': 'true if git repository',
      'typescript.exists': 'true if TypeScript project',
      'vscode-extension.exists': 'true if VS Code extension',
      'buildkit.exists': 'true if has buildkit.yaml',
      'tom-project.exists': 'true if has tom_project.yaml',

      // Dart/Flutter attributes
      'dart.name': 'Project name from pubspec',
      'dart.version': 'Version from pubspec',
      'dart.publishable': 'true if publishable to pub.dev',
      'flutter.platforms': 'Comma-separated platform list',
      'flutter.isPlugin': 'true if Flutter plugin',

      // Git attributes
      'git.branch': 'Current branch name',
      'git.isSubmodule': 'true if git submodule',
      'git.hasChanges': 'true if uncommitted changes',
      'git.remotes': 'Comma-separated remote list',

      // VS Code extension attributes
      'vscode.name': 'Extension name',
      'vscode.version': 'Extension version',
    };
  }
}
