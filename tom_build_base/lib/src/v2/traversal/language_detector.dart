import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../folder/fs_folder.dart';
import '../folder/natures/language_folders.dart';
import 'project_files.dart';

/// Detects the non-Dart language natures of a folder from its project files
/// ([LanguageProjectFolder] and its subtypes, TypeScript excepted: the
/// [NatureDetector] creates that one with the VS Code natures).
class LanguageDetector {
  /// The language natures of [folder]: at most one per language.
  List<LanguageProjectFolder> detect(FsFolder folder) {
    final dir = folder.path;
    final natures = <LanguageProjectFolder>[];

    final packageJson = File(p.join(dir, 'package.json'));
    if (packageJson.existsSync() &&
        !File(p.join(dir, 'tsconfig.json')).existsSync()) {
      final json = readPackageJson(packageJson);
      natures.add(
        JavaScriptFolder(
          folder,
          projectName: json['name'] as String?,
          version: json['version'] as String?,
          scripts: packageScripts(json),
        ),
      );
    }

    for (final file in const ['pyproject.toml', 'setup.py', 'setup.cfg']) {
      if (!File(p.join(dir, file)).existsSync()) continue;
      final identity = file == 'pyproject.toml'
          ? pyprojectIdentity(File(p.join(dir, file)).readAsStringSync())
          : (name: null, version: null);
      natures.add(
        PythonFolder(
          folder,
          projectFile: file,
          projectName: identity.name,
          version: identity.version,
        ),
      );
      break;
    }

    final pom = File(p.join(dir, 'pom.xml'));
    if (pom.existsSync()) {
      final identity = pomIdentity(pom.readAsStringSync());
      natures.add(
        JavaFolder(
          folder,
          buildTool: JavaBuildTool.maven,
          projectFile: 'pom.xml',
          projectName: identity.name,
          version: identity.version,
        ),
      );
    } else {
      for (final file in const ['build.gradle.kts', 'build.gradle']) {
        if (!File(p.join(dir, file)).existsSync()) continue;
        natures.add(
          JavaFolder(
            folder,
            buildTool: JavaBuildTool.gradle,
            projectFile: file,
          ),
        );
        break;
      }
    }

    final goMod = File(p.join(dir, 'go.mod'));
    if (goMod.existsSync()) {
      natures.add(
        GoFolder(folder, modulePath: goModulePath(goMod.readAsStringSync())),
      );
    }

    final cargo = File(p.join(dir, 'Cargo.toml'));
    if (cargo.existsSync()) {
      final identity = cargoIdentity(cargo.readAsStringSync());
      natures.add(
        RustFolder(
          folder,
          projectName: identity.name,
          version: identity.version,
        ),
      );
    }

    final native = _nativeNature(folder);
    if (native != null) natures.add(native);

    return natures;
  }

  /// A C or C++ nature when the folder has a make or CMake build file and the
  /// sources beside it say which language: any C++ source makes it C++, C
  /// sources alone make it C, no sources (a docs `Makefile`) make it neither.
  NativeProjectFolder? _nativeNature(FsFolder folder) {
    final dir = folder.path;
    String? buildFile;
    NativeBuildSystem? system;
    for (final file in const ['Makefile', 'makefile', 'GNUmakefile']) {
      if (File(p.join(dir, file)).existsSync()) {
        buildFile = file;
        system = NativeBuildSystem.make;
        break;
      }
    }
    if (buildFile == null && File(p.join(dir, 'CMakeLists.txt')).existsSync()) {
      buildFile = 'CMakeLists.txt';
      system = NativeBuildSystem.cmake;
    }
    if (buildFile == null || system == null) return null;

    final languages = nativeSourceLanguages(dir);
    if (languages.contains('cpp')) {
      return CppFolder(folder, buildSystem: system, projectFile: buildFile);
    }
    if (languages.contains('c')) {
      return CFolder(folder, buildSystem: system, projectFile: buildFile);
    }
    return null;
  }
}

/// The JSON object of a `package.json`, or an empty map when it does not
/// parse.
Map<String, dynamic> readPackageJson(File file) {
  try {
    final json = jsonDecode(file.readAsStringSync());
    return json is Map<String, dynamic> ? json : const {};
  } catch (_) {
    return const {};
  }
}

/// The `scripts` of a `package.json` object.
Map<String, String> packageScripts(Map<String, dynamic> json) {
  final scripts = json['scripts'];
  if (scripts is! Map) return const {};
  return {for (final e in scripts.entries) '${e.key}': '${e.value}'};
}
