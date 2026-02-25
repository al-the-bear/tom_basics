import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../folder/fs_folder.dart';
import '../folder/run_folder.dart';
import '../folder/natures/git_folder.dart';
import '../folder/natures/dart_project_folder.dart';
import '../folder/natures/extension_folder.dart';
import '../folder/natures/buildkit_folder.dart';

/// Detects and creates folder natures based on filesystem markers.
class NatureDetector {
  /// Detect all natures for a folder.
  List<RunFolder> detectNatures(FsFolder folder) {
    final natures = <RunFolder>[];

    if (_isGitFolder(folder.path)) natures.add(_createGitNature(folder));
    if (_isDartProject(folder.path)) natures.add(_createDartNature(folder));
    if (_isVsCodeExtension(folder.path)) {
      natures.add(_createVsCodeNature(folder));
    }
    if (_isTypeScriptProject(folder.path)) {
      natures.add(_createTypeScriptNature(folder));
    }
    if (_hasBuildkitYaml(folder.path)) {
      natures.add(_createBuildkitNature(folder));
    }
    if (_hasBuildYaml(folder.path)) natures.add(BuildRunnerFolder(folder));
    if (_hasTomProjectYaml(folder.path)) {
      natures.add(_createTomProjectNature(folder));
    }
    if (_hasTomMasterYaml(folder.path)) {
      natures.add(TomBuildMasterFolder(folder));
    }

    return natures;
  }

  // Detection methods
  bool _isGitFolder(String path) =>
      Directory(p.join(path, '.git')).existsSync() ||
      File(p.join(path, '.git')).existsSync();

  bool _isDartProject(String path) =>
      File(p.join(path, 'pubspec.yaml')).existsSync();

  bool _isVsCodeExtension(String path) {
    final packageJson = File(p.join(path, 'package.json'));
    if (!packageJson.existsSync()) return false;
    try {
      final content = packageJson.readAsStringSync();
      return content.contains('"engines"') && content.contains('"vscode"');
    } catch (_) {
      return false;
    }
  }

  bool _isTypeScriptProject(String path) =>
      File(p.join(path, 'tsconfig.json')).existsSync();

  bool _hasBuildkitYaml(String path) =>
      File(p.join(path, 'buildkit.yaml')).existsSync();

  bool _hasBuildYaml(String path) =>
      File(p.join(path, 'build.yaml')).existsSync();

  bool _hasTomProjectYaml(String path) =>
      File(p.join(path, 'tom_project.yaml')).existsSync();

  bool _hasTomMasterYaml(String path) =>
      File(p.join(path, 'buildkit_master.yaml')).existsSync();

  // Nature creation methods
  GitFolder _createGitNature(FsFolder folder) {
    final isSubmodule = !Directory(p.join(folder.path, '.git')).existsSync();
    String currentBranch = 'unknown';
    bool hasUncommittedChanges = false;
    bool hasUnpushedCommits = false;
    List<String> remotes = [];
    String? submoduleName;

    try {
      // Get current branch
      final headFile = isSubmodule
          ? _resolveSubmoduleHead(folder.path)
          : File(p.join(folder.path, '.git', 'HEAD'));

      if (headFile.existsSync()) {
        final content = headFile.readAsStringSync().trim();
        if (content.startsWith('ref: refs/heads/')) {
          currentBranch = content.substring('ref: refs/heads/'.length);
        }
      }

      // Get remotes
      final configFile = isSubmodule
          ? _resolveSubmoduleConfig(folder.path)
          : File(p.join(folder.path, '.git', 'config'));

      if (configFile.existsSync()) {
        final content = configFile.readAsStringSync();
        final remoteRegex = RegExp(r'\[remote "([^"]+)"\]');
        remotes = remoteRegex
            .allMatches(content)
            .map((m) => m.group(1)!)
            .toList();
      }
    } catch (_) {
      // Ignore errors reading git info
    }

    // For submodules, extract module name from .git file content or folder name
    if (isSubmodule) {
      submoduleName = _extractSubmoduleName(folder.path);
    }

    return GitFolder(
      folder,
      currentBranch: currentBranch,
      hasUncommittedChanges: hasUncommittedChanges,
      hasUnpushedCommits: hasUnpushedCommits,
      isSubmodule: isSubmodule,
      remotes: remotes,
      submoduleName: submoduleName,
    );
  }

  /// Extract submodule name from the gitdir path or folder name.
  String? _extractSubmoduleName(String path) {
    try {
      final gitFile = File(p.join(path, '.git'));
      if (gitFile.existsSync()) {
        final content = gitFile.readAsStringSync().trim();
        // gitdir: ../.git/modules/<name>
        if (content.startsWith('gitdir: ')) {
          final gitDir = content.substring('gitdir: '.length);
          final modulesIndex = gitDir.indexOf('/modules/');
          if (modulesIndex != -1) {
            return gitDir.substring(modulesIndex + '/modules/'.length);
          }
        }
      }
    } catch (_) {}
    // Fallback: use folder name
    return p.basename(path);
  }

  File _resolveSubmoduleHead(String path) {
    final gitFile = File(p.join(path, '.git'));
    if (!gitFile.existsSync()) return File(p.join(path, '.git', 'HEAD'));
    try {
      final content = gitFile.readAsStringSync().trim();
      if (content.startsWith('gitdir: ')) {
        final gitDir = content.substring('gitdir: '.length);
        return File(p.join(path, gitDir, 'HEAD'));
      }
    } catch (_) {}
    return File(p.join(path, '.git', 'HEAD'));
  }

  File _resolveSubmoduleConfig(String path) {
    final gitFile = File(p.join(path, '.git'));
    if (!gitFile.existsSync()) return File(p.join(path, '.git', 'config'));
    try {
      final content = gitFile.readAsStringSync().trim();
      if (content.startsWith('gitdir: ')) {
        final gitDir = content.substring('gitdir: '.length);
        return File(p.join(path, gitDir, 'config'));
      }
    } catch (_) {}
    return File(p.join(path, '.git', 'config'));
  }

  DartProjectFolder _createDartNature(FsFolder folder) {
    Map<String, dynamic> pubspec = {};
    String projectName = folder.name;
    String? version;
    Map<String, dynamic> dependencies = {};
    Map<String, dynamic> devDependencies = {};

    try {
      final pubspecFile = File(p.join(folder.path, 'pubspec.yaml'));
      final content = pubspecFile.readAsStringSync();
      final yaml = loadYaml(content);
      if (yaml is Map) {
        pubspec = Map<String, dynamic>.from(yaml);
        projectName = pubspec['name'] as String? ?? folder.name;
        version = pubspec['version'] as String?;

        if (pubspec['dependencies'] is Map) {
          dependencies = Map<String, dynamic>.from(
            pubspec['dependencies'] as Map,
          );
        }
        if (pubspec['dev_dependencies'] is Map) {
          devDependencies = Map<String, dynamic>.from(
            pubspec['dev_dependencies'] as Map,
          );
        }
      }
    } catch (_) {
      // Ignore pubspec read errors
    }

    // Determine project type
    final hasFlutter = _hasFlutterSdk(pubspec);
    final hasBin = Directory(p.join(folder.path, 'bin')).existsSync();
    final hasLibSrc = Directory(p.join(folder.path, 'lib', 'src')).existsSync();

    if (hasFlutter) {
      final platforms = _detectFlutterPlatforms(folder.path);
      final isPlugin =
          pubspec.containsKey('flutter') &&
          (pubspec['flutter'] as Map?)?.containsKey('plugin') == true;
      return FlutterProjectFolder(
        folder,
        projectName: projectName,
        version: version,
        dependencies: dependencies,
        devDependencies: devDependencies,
        pubspec: pubspec,
        platforms: platforms,
        isPlugin: isPlugin,
      );
    } else if (hasBin) {
      final executables = _detectExecutables(folder.path);
      return DartConsoleFolder(
        folder,
        projectName: projectName,
        version: version,
        dependencies: dependencies,
        devDependencies: devDependencies,
        pubspec: pubspec,
        executables: executables,
      );
    } else if (hasLibSrc) {
      // Per design spec: DartPackageFolder requires lib/src/
      return DartPackageFolder(
        folder,
        projectName: projectName,
        version: version,
        dependencies: dependencies,
        devDependencies: devDependencies,
        pubspec: pubspec,
        hasLibSrc: hasLibSrc,
      );
    } else {
      // Generic Dart project without bin/ or lib/src/
      return DartProjectFolder(
        folder,
        projectName: projectName,
        version: version,
        dependencies: dependencies,
        devDependencies: devDependencies,
        pubspec: pubspec,
      );
    }
  }

  bool _hasFlutterSdk(Map<String, dynamic> pubspec) {
    final deps = pubspec['dependencies'];
    if (deps is Map) {
      final flutter = deps['flutter'];
      if (flutter is Map && flutter.containsKey('sdk')) {
        return true;
      }
    }
    return false;
  }

  List<String> _detectFlutterPlatforms(String path) {
    final platforms = <String>[];
    if (Directory(p.join(path, 'android')).existsSync()) {
      platforms.add('android');
    }
    if (Directory(p.join(path, 'ios')).existsSync()) platforms.add('ios');
    if (Directory(p.join(path, 'web')).existsSync()) platforms.add('web');
    if (Directory(p.join(path, 'linux')).existsSync()) platforms.add('linux');
    if (Directory(p.join(path, 'macos')).existsSync()) platforms.add('macos');
    if (Directory(p.join(path, 'windows')).existsSync()) {
      platforms.add('windows');
    }
    return platforms;
  }

  List<String> _detectExecutables(String path) {
    final binDir = Directory(p.join(path, 'bin'));
    if (!binDir.existsSync()) return [];

    try {
      return binDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => p.basenameWithoutExtension(f.path))
          .toList();
    } catch (_) {
      return [];
    }
  }

  VsCodeExtensionFolder _createVsCodeNature(FsFolder folder) {
    String extensionName = folder.name;
    String? version;
    String? displayName;

    try {
      final packageJson = File(p.join(folder.path, 'package.json'));
      final content = packageJson.readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;
      extensionName = json['name'] as String? ?? folder.name;
      version = json['version'] as String?;
      displayName = json['displayName'] as String?;
    } catch (_) {}

    return VsCodeExtensionFolder(
      folder,
      extensionName: extensionName,
      version: version,
      displayName: displayName,
    );
  }

  TypeScriptFolder _createTypeScriptNature(FsFolder folder) {
    String? projectName;
    bool isNodeProject = false;

    try {
      final packageJson = File(p.join(folder.path, 'package.json'));
      if (packageJson.existsSync()) {
        final content = packageJson.readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;
        projectName = json['name'] as String?;
        isNodeProject = json.containsKey('main') || json.containsKey('scripts');
      }
    } catch (_) {}

    return TypeScriptFolder(
      folder,
      projectName: projectName,
      isNodeProject: isNodeProject,
    );
  }

  TomBuildFolder _createTomProjectNature(FsFolder folder) {
    String? projectName;
    String? shortId;
    Map<String, dynamic> config = {};

    try {
      final tomProjectFile = File(p.join(folder.path, 'tom_project.yaml'));
      final content = tomProjectFile.readAsStringSync();
      final yaml = loadYaml(content);
      if (yaml is Map) {
        config = Map<String, dynamic>.from(yaml);
        projectName = config['name'] as String?;
        // Support both project_id (underscore) and short-id (hyphen) formats
        shortId =
            config['project_id'] as String? ?? config['short-id'] as String?;
      }
    } catch (_) {}

    return TomBuildFolder(
      folder,
      projectName: projectName,
      shortId: shortId,
      config: config,
    );
  }

  BuildkitFolder _createBuildkitNature(FsFolder folder) {
    String? projectId;
    String? projectName;
    bool recursive = true;
    Map<String, dynamic> config = {};

    try {
      final buildkitFile = File(p.join(folder.path, 'buildkit.yaml'));
      final content = buildkitFile.readAsStringSync();
      final yaml = loadYaml(content);
      if (yaml is Map) {
        config = Map<String, dynamic>.from(yaml);
        projectId = config['project-id'] as String?;
        projectName = config['name'] as String?;
        recursive = config['recursive'] as bool? ?? true;
      }
    } catch (_) {}

    return BuildkitFolder(
      folder,
      projectId: projectId,
      projectName: projectName,
      recursive: recursive,
      config: config,
    );
  }
}
