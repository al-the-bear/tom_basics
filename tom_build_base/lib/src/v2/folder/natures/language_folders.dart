import '../run_folder.dart';

/// A project in one of the SOM runtime languages other than Dart, detected
/// by its project file: TypeScript, JavaScript, Python, Java, Go, Rust, C and
/// C++.
///
/// Dart projects are `DartProjectFolder`s. A command that works on every
/// language project names this type in its natures; the detector creates the
/// concrete subtype.
abstract class LanguageProjectFolder extends RunFolder {
  /// The project's name as its project file states it, if it does.
  final String? projectName;

  /// The project's version as its project file states it, if it does.
  final String? version;

  LanguageProjectFolder(super.fsFolder, {this.projectName, this.version});

  /// The language, named as the SOM runtimes name it: `typescript`,
  /// `javascript`, `python`, `java`, `go`, `rust`, `c`, `cpp`.
  String get language;

  /// The file that marks the project, relative to its folder.
  String get projectFile;

  @override
  String toString() =>
      '$runtimeType($path, name: $projectName, version: $version)';
}

/// JavaScript project nature: a `package.json` without a `tsconfig.json`.
class JavaScriptFolder extends LanguageProjectFolder {
  /// The `scripts` of `package.json` by name.
  final Map<String, String> scripts;

  JavaScriptFolder(
    super.fsFolder, {
    super.projectName,
    super.version,
    this.scripts = const {},
  });

  @override
  String get language => 'javascript';

  @override
  String get projectFile => 'package.json';
}

/// Python project nature: a `pyproject.toml`, `setup.py` or `setup.cfg`.
class PythonFolder extends LanguageProjectFolder {
  @override
  final String projectFile;

  PythonFolder(
    super.fsFolder, {
    required this.projectFile,
    super.projectName,
    super.version,
  });

  @override
  String get language => 'python';
}

/// The build tool of a [JavaFolder].
enum JavaBuildTool {
  /// `pom.xml`.
  maven,

  /// `build.gradle` or `build.gradle.kts`.
  gradle,
}

/// Java project nature: a `pom.xml`, `build.gradle` or `build.gradle.kts`.
class JavaFolder extends LanguageProjectFolder {
  /// Maven or Gradle.
  final JavaBuildTool buildTool;

  @override
  final String projectFile;

  JavaFolder(
    super.fsFolder, {
    required this.buildTool,
    required this.projectFile,
    super.projectName,
    super.version,
  });

  @override
  String get language => 'java';
}

/// Go project nature: a `go.mod`.
class GoFolder extends LanguageProjectFolder {
  /// The module path from `go.mod`'s `module` line.
  final String? modulePath;

  GoFolder(super.fsFolder, {this.modulePath})
    : super(projectName: modulePath?.split('/').last);

  @override
  String get language => 'go';

  @override
  String get projectFile => 'go.mod';
}

/// Rust project nature: a `Cargo.toml`.
class RustFolder extends LanguageProjectFolder {
  RustFolder(super.fsFolder, {super.projectName, super.version});

  @override
  String get language => 'rust';

  @override
  String get projectFile => 'Cargo.toml';
}

/// The build system of a C or C++ project.
enum NativeBuildSystem {
  /// A `Makefile` (or `makefile`, `GNUmakefile`).
  make,

  /// A `CMakeLists.txt`.
  cmake,
}

/// A C or C++ project: a `Makefile` or `CMakeLists.txt` beside the sources
/// that decide the language ([CFolder], [CppFolder]).
abstract class NativeProjectFolder extends LanguageProjectFolder {
  /// Make or CMake.
  final NativeBuildSystem buildSystem;

  @override
  final String projectFile;

  NativeProjectFolder(
    super.fsFolder, {
    required this.buildSystem,
    required this.projectFile,
  });
}

/// C project nature: a `Makefile` / `CMakeLists.txt` with C sources (`.c`)
/// and no C++ sources.
class CFolder extends NativeProjectFolder {
  CFolder(
    super.fsFolder, {
    required super.buildSystem,
    required super.projectFile,
  });

  @override
  String get language => 'c';
}

/// C++ project nature: a `Makefile` / `CMakeLists.txt` with C++ sources
/// (`.cpp`, `.cc`, `.cxx`, `.hpp`, ...).
class CppFolder extends NativeProjectFolder {
  CppFolder(
    super.fsFolder, {
    required super.buildSystem,
    required super.projectFile,
  });

  @override
  String get language => 'cpp';
}
