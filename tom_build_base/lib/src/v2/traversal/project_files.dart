import 'dart:io';

import 'package:path/path.dart' as p;

/// A project's name and version as its project file states them.
typedef ProjectIdentity = ({String? name, String? version});

/// The string values of one table of a TOML document (`[project]`,
/// `[package]`, `[tool.poetry]`): `key = "value"` / `key = 'value'` lines,
/// comments and other value types ignored. Enough for a project file's name
/// and version; not a TOML parser.
Map<String, String> tomlTableStrings(String text, String table) {
  final values = <String, String>{};
  String? current;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final header = RegExp(r'^\[\[?\s*([^\]]+?)\s*\]\]?').firstMatch(line);
    if (header != null) {
      current = header.group(1);
      continue;
    }
    if (current != table) continue;
    final kv = RegExp(
      r'''^([A-Za-z0-9_.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
    ).firstMatch(line);
    if (kv != null) values[kv.group(1)!] = kv.group(2) ?? kv.group(3)!;
  }
  return values;
}

/// Name and version of a `pyproject.toml`: `[project]`, else
/// `[tool.poetry]`.
ProjectIdentity pyprojectIdentity(String text) {
  for (final table in const ['project', 'tool.poetry']) {
    final values = tomlTableStrings(text, table);
    if (values.containsKey('name') || values.containsKey('version')) {
      return (name: values['name'], version: values['version']);
    }
  }
  return (name: null, version: null);
}

/// Name and version of a `Cargo.toml`'s `[package]`.
ProjectIdentity cargoIdentity(String text) {
  final values = tomlTableStrings(text, 'package');
  return (name: values['name'], version: values['version']);
}

/// The module path of a `go.mod`.
String? goModulePath(String text) =>
    RegExp(r'^module\s+(\S+)', multiLine: true).firstMatch(text)?.group(1);

/// The sections of a `pom.xml` whose `<artifactId>` / `<version>` are not the
/// project's own.
const _pomNestedSections = [
  'parent',
  'dependencies',
  'dependencyManagement',
  'build',
  'reporting',
  'profiles',
  'plugins',
  'pluginManagement',
  'extensions',
];

/// [pom] with every nested section blanked out to spaces of the same length,
/// so an offset found in the result is an offset in [pom].
String _pomOwnLevel(String pom) {
  var masked = pom.replaceAllMapped(
    RegExp(r'<!--.*?-->', dotAll: true),
    (m) => ' ' * m.group(0)!.length,
  );
  for (final section in _pomNestedSections) {
    masked = masked.replaceAllMapped(
      RegExp('<$section(\\s[^>]*)?>.*?</$section>', dotAll: true),
      (m) => ' ' * m.group(0)!.length,
    );
  }
  return masked;
}

RegExpMatch? _pomElement(String pom, String element) => RegExp(
  '<$element>\\s*([^<]*?)\\s*</$element>',
).firstMatch(_pomOwnLevel(pom));

/// The project's own `<artifactId>` and `<version>` of a `pom.xml`.
ProjectIdentity pomIdentity(String text) => (
  name: _pomElement(text, 'artifactId')?.group(1),
  version: _pomElement(text, 'version')?.group(1),
);

/// File extensions of C++ sources and headers.
const _cppExtensions = {'.cpp', '.cc', '.cxx', '.c++', '.hpp', '.hxx', '.hh'};

/// Directories never searched for sources.
const _sourceSkipDirs = {
  '.git',
  'build',
  'target',
  'node_modules',
  'dist',
  '.dart_tool',
  'ztmp',
};

/// The native languages whose sources lie in [dir] or up to three levels
/// below it: `c` for `.c` files, `cpp` for C++ sources and headers. A `.h`
/// header says neither.
Set<String> nativeSourceLanguages(String dir) {
  final found = <String>{};
  void walk(Directory d, int depth) {
    List<FileSystemEntity> entries;
    try {
      entries = d.listSync(followLinks: false);
    } catch (_) {
      return;
    }
    for (final entry in entries) {
      final name = p.basename(entry.path);
      if (entry is Directory) {
        if (depth < 3 && !_sourceSkipDirs.contains(name)) {
          walk(entry, depth + 1);
        }
        continue;
      }
      final ext = p.extension(name).toLowerCase();
      if (ext == '.c') found.add('c');
      if (_cppExtensions.contains(ext)) found.add('cpp');
      if (found.length == 2) return;
    }
  }

  walk(Directory(dir), 0);
  return found;
}

/// The version field of a project file: read it, and write a new one with
/// the rest of the file as it was.
///
/// One per format that has a version: `pubspec.yaml`, `package.json`,
/// `pyproject.toml`, `Cargo.toml`, `pom.xml`. Go modules and C / C++ make or
/// CMake projects state no version in their project file.
abstract class ProjectVersionFile {
  /// The file, relative to the project folder.
  String get fileName;

  /// The version in [text], or null when the file states none.
  String? read(String text);

  /// [text] with its version replaced by [version]; [text] unchanged when it
  /// states none.
  String write(String text, String version);

  /// The version file of the project in [projectDir], by the first project
  /// file present in the order Dart, Node, Python, Rust, Java; null when it
  /// has none of them.
  static ProjectVersionFile? of(String projectDir) {
    for (final file in _all) {
      if (File(p.join(projectDir, file.fileName)).existsSync()) return file;
    }
    return null;
  }

  static final _all = <ProjectVersionFile>[
    _PubspecVersion(),
    _PackageJsonVersion(),
    _TomlVersion('pyproject.toml', const ['project', 'tool.poetry']),
    _TomlVersion('Cargo.toml', const ['package']),
    _PomVersion(),
  ];
}

class _PubspecVersion extends ProjectVersionFile {
  static final _line = RegExp(r'^version:\s*(\S+)', multiLine: true);

  @override
  String get fileName => 'pubspec.yaml';

  @override
  String? read(String text) =>
      _line.firstMatch(text)?.group(1)?.replaceAll(RegExp('''['"]'''), '');

  @override
  String write(String text, String version) =>
      text.replaceFirst(_line, 'version: $version');
}

class _PackageJsonVersion extends ProjectVersionFile {
  // The first "version" key: package.json names its own version at the top,
  // and dependencies are keyed by package name, not by "version".
  static final _key = RegExp(r'"version"\s*:\s*"([^"]*)"');

  @override
  String get fileName => 'package.json';

  @override
  String? read(String text) => _key.firstMatch(text)?.group(1);

  @override
  String write(String text, String version) {
    final m = _key.firstMatch(text);
    if (m == null) return text;
    final whole = m.group(0)!;
    final replaced = whole.replaceFirst('"${m.group(1)}"', '"$version"', 9);
    return text.replaceRange(m.start, m.end, replaced);
  }
}

class _TomlVersion extends ProjectVersionFile {
  @override
  final String fileName;
  final List<String> tables;

  _TomlVersion(this.fileName, this.tables);

  @override
  String? read(String text) {
    for (final table in tables) {
      final version = tomlTableStrings(text, table)['version'];
      if (version != null) return version;
    }
    return null;
  }

  @override
  String write(String text, String version) {
    final lines = text.split('\n');
    for (final table in tables) {
      String? current;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        final header = RegExp(r'^\[\[?\s*([^\]]+?)\s*\]\]?').firstMatch(line);
        if (header != null) {
          current = header.group(1);
          continue;
        }
        if (current != table) continue;
        final m = RegExp(
          r'''^(\s*version\s*=\s*)(["'])[^"']*\2''',
        ).firstMatch(lines[i]);
        if (m == null) continue;
        lines[i] = lines[i].replaceRange(
          m.start,
          m.end,
          '${m.group(1)}${m.group(2)}$version${m.group(2)}',
        );
        return lines.join('\n');
      }
    }
    return text;
  }
}

class _PomVersion extends ProjectVersionFile {
  @override
  String get fileName => 'pom.xml';

  @override
  String? read(String text) => _pomElement(text, 'version')?.group(1);

  @override
  String write(String text, String version) {
    final m = _pomElement(text, 'version');
    if (m == null) return text;
    final valueStart = text.indexOf(m.group(1)!, m.start);
    return text.replaceRange(
      valueStart,
      valueStart + m.group(1)!.length,
      version,
    );
  }
}

/// Project files that make a folder a project in one of the non-Dart
/// languages, apart from C / C++ (see [isProjectFolder]).
const languageProjectFiles = [
  'package.json',
  'tsconfig.json',
  'pyproject.toml',
  'setup.py',
  'setup.cfg',
  'pom.xml',
  'build.gradle',
  'build.gradle.kts',
  'go.mod',
  'Cargo.toml',
];

/// Whether [dir] is a project folder of any language the build tools know:
/// a `pubspec.yaml`, one of [languageProjectFiles], or a make / CMake file
/// beside C or C++ sources.
bool isProjectFolder(String dir) {
  if (File(p.join(dir, 'pubspec.yaml')).existsSync()) return true;
  for (final file in languageProjectFiles) {
    if (File(p.join(dir, file)).existsSync()) return true;
  }
  const nativeBuildFiles = [
    'Makefile',
    'makefile',
    'GNUmakefile',
    'CMakeLists.txt',
  ];
  if (nativeBuildFiles.any((f) => File(p.join(dir, f)).existsSync())) {
    return nativeSourceLanguages(dir).isNotEmpty;
  }
  return false;
}
