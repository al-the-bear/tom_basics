/// The release binaries (buildkit_ws_commands.md § 1.9, decisions WSC-13,
/// -21, -22): what tom_binaries tracks in `tom/<platform>/`.
///
/// The set is the sum of two declarations, an entry in both is fine:
///
/// - a project's `buildkit.yaml`: `compiler: executables:`, the name with
///   `{release: true}`, per executable it compiles (the name it is written as, without
///   `.exe`);
/// - the workspace's `buildkit_master.yaml`: a `binaries:` list naming any
///   project's executable, what no project compiles (bundled applications and
///   libraries, binaries another tool builds), the short names and the
///   platforms an entry exists on.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// How a release binary gets into tom_binaries.
enum ReleaseKind {
  /// A project's `:compiler` writes it.
  compiled,

  /// Another tool builds it (`built-by:`).
  external,

  /// Put there by hand, never built.
  bundled,
}

/// A short name of a release binary.
class ReleaseShortName {
  const ReleaseShortName(this.name, [this.target]);
  final String name;

  /// What it points to, relative to the folder; null: the binary itself.
  final String? target;
}

/// One release binary.
class ReleaseBinary {
  ReleaseBinary(this.name);

  /// The file or folder name in its folder (an executable without `.exe`).
  final String name;
  ReleaseKind kind = ReleaseKind.compiled;

  /// The project folder whose `:compiler` writes it (absolute), when compiled.
  String? projectDir;

  /// That project's path from the workspace root.
  String? project;

  /// buildkit_master.yaml names a project that is not there.
  bool projectMissing = false;

  /// The project opts out of being compiled by buildkit (buildkit itself):
  /// compiled to a temporary name and swapped in.
  bool selfBuilt = false;
  String? builtBy;

  /// The folder in tom_binaries, when not `tom/<platform>`; `%{platform}`.
  String? path;
  final files = <String>[];
  final shortNames = <ReleaseShortName>[];
  bool windowsHardLink = false;

  /// The platforms it exists on; null: every one.
  List<String>? platforms;
  String? notes;

  /// Where it is declared, relative to the workspace root.
  final declaredIn = <String>[];

  bool onPlatform(String platform) =>
      platforms == null || platforms!.contains(platform);

  /// Its folder in [binaries] for [platform].
  String folder(String binaries, String platform) => p.join(
    binaries,
    p.joinAll(
      (path ?? 'tom/%{platform}')
          .replaceAll('%{platform}', platform)
          .split('/'),
    ),
  );

  /// The file it is written as on [platform].
  String fileName(String platform) =>
      kind == ReleaseKind.compiled && platform.startsWith('win32')
      ? '$name.exe'
      : name;

  /// The files a build writes for it (relative to its folder): the binary,
  /// its `.buildkit.json` stamp when the compiler wrote one, its other files.
  List<String> builtFiles(String platform) => [fileName(platform), ...files];

  /// The files its short names are on [platform].
  List<String> shortFiles(String platform) => [
    for (final s in shortNames)
      if (platform.startsWith('win32')) ...[
        s.name,
        '${s.name}.cmd',
        if (windowsHardLink) '${s.name}.exe',
      ] else
        s.name,
  ];

  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind.name,
    'project': project,
    'builtBy': builtBy,
    'path': path,
    'files': files,
    'short': [
      for (final s in shortNames) {'name': s.name, 'target': s.target},
    ],
    'windowsHardLink': windowsHardLink,
    'platforms': platforms,
    'selfBuilt': selfBuilt,
    'declaredIn': declaredIn,
    if (notes != null) 'notes': notes,
  };
}

/// The release set of a workspace.
class ReleaseSet {
  ReleaseSet(this.root, this.binaries, this.problems);

  /// The workspace root (the folder of buildkit_master.yaml).
  final String root;

  /// Every release binary, by name, in declaration order.
  final List<ReleaseBinary> binaries;

  /// What does not add up (a project that is not there, an entry that says
  /// neither how it is built nor that it is bundled).
  final List<String> problems;

  /// The binaries of [platform].
  List<ReleaseBinary> forPlatform(String platform) => [
    for (final b in binaries)
      if (b.onPlatform(platform)) b,
  ];

  /// Reads both declarations below [root].
  static ReleaseSet load(String root) {
    final problems = <String>[];
    final byName = <String, ReleaseBinary>{};
    final projects = releaseProjects(root);

    ReleaseBinary entry(String name) =>
        byName.putIfAbsent(name, () => ReleaseBinary(name));

    // The projects' release flags.
    for (final dir in projects) {
      final yaml = _readYaml(p.join(dir, 'buildkit.yaml'));
      final compiler = yaml?['compiler'];
      if (compiler is! Map) continue;
      final executables = compiler['executables'];
      if (executables is! Map) continue;
      final rel = _rel(root, p.join(dir, 'buildkit.yaml'));
      for (final e in executables.entries) {
        final v = e.value;
        if (v is! Map || v['release'] != true) continue;
        entry('${e.key}')
          ..projectDir = dir
          ..project = _rel(root, dir)
          ..selfBuilt = compiler['skip-compile-with-buildkit'] == true
          ..declaredIn.add(rel);
      }
    }

    // The master list.
    final master = _readYaml(p.join(root, 'buildkit_master.yaml'));
    final list = master?['binaries'];
    if (list is List) {
      for (final raw in list) {
        if (raw is! Map || raw['name'] == null) {
          problems.add('buildkit_master.yaml: a binaries entry without a name');
          continue;
        }
        final b = entry('${raw['name']}')
          ..declaredIn.add('buildkit_master.yaml');
        final project = raw['project'] as String?;
        if (project != null) {
          final dir = _findProject(root, projects, project);
          if (dir == null) {
            b.projectMissing = true;
            problems.add(
              'buildkit_master.yaml: ${b.name}: no project $project under the '
              'workspace',
            );
          } else {
            final compiler = _readYaml(
              p.join(dir, 'buildkit.yaml'),
            )?['compiler'];
            b
              ..projectDir = dir
              ..project = _rel(root, dir)
              ..selfBuilt =
                  compiler is Map &&
                  compiler['skip-compile-with-buildkit'] == true;
          }
        }
        if (raw['built-by'] != null) {
          b
            ..kind = ReleaseKind.external
            ..builtBy = '${raw['built-by']}';
        }
        if (raw['bundled'] == true) b.kind = ReleaseKind.bundled;
        if (raw['path'] != null) b.path = '${raw['path']}';
        if (raw['notes'] != null) b.notes = '${raw['notes']}';
        if (raw['windows-hard-link'] == true) b.windowsHardLink = true;
        for (final f in (raw['files'] as List?) ?? const []) {
          if (!b.files.contains('$f')) b.files.add('$f');
        }
        for (final s in (raw['short'] as List?) ?? const []) {
          final short = s is Map
              ? ReleaseShortName('${s['name']}', s['target'] as String?)
              : ReleaseShortName('$s');
          if (!b.shortNames.any((x) => x.name == short.name)) {
            b.shortNames.add(short);
          }
        }
        final platforms = raw['platforms'];
        if (platforms is List) b.platforms = [for (final x in platforms) '$x'];
      }
    }

    for (final b in byName.values) {
      if (b.kind == ReleaseKind.compiled &&
          b.projectDir == null &&
          !b.projectMissing) {
        problems.add(
          '${b.name}: neither a project that compiles it, nor built-by, nor '
          'bundled (${b.declaredIn.join(', ')})',
        );
      }
    }
    return ReleaseSet(root, byName.values.toList(), problems);
  }
}

/// Folders a project scan never enters.
const _skipped = {
  'node_modules',
  'build',
  'ztmp',
  'test',
  'example',
  'tom_binaries',
  '_ai',
  'Pods',
};

/// Every project folder (one holding a `buildkit.yaml`) below [root]: not
/// inside a hidden, build, scratch, test or example folder, a `zom_` fixture
/// or a folder marked `buildkit_skip.yaml` / `tom_skip.yaml`; links are not
/// followed.
List<String> releaseProjects(String root) {
  final out = <String>[];
  void walk(Directory dir) {
    if (File(p.join(dir.path, 'buildkit_skip.yaml')).existsSync() ||
        File(p.join(dir.path, 'tom_skip.yaml')).existsSync()) {
      return;
    }
    if (dir.path != root &&
        File(p.join(dir.path, 'buildkit.yaml')).existsSync()) {
      out.add(dir.path);
    }
    List<FileSystemEntity> children;
    try {
      children = dir.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final c in children) {
      if (c is! Directory) continue;
      final name = p.basename(c.path);
      if (name.startsWith('.') ||
          name.startsWith('zom_') ||
          _skipped.contains(name)) {
        continue;
      }
      walk(c);
    }
  }

  walk(Directory(root));
  out.sort();
  return out;
}

String? _findProject(String root, List<String> projects, String id) {
  final byPath = p.normalize(p.join(root, id));
  for (final d in projects) {
    if (d == byPath) return d;
  }
  for (final d in projects) {
    if (p.basename(d) == id) return d;
  }
  return null;
}

Map? _readYaml(String file) {
  final f = File(file);
  if (!f.existsSync()) return null;
  try {
    final y = loadYaml(f.readAsStringSync());
    return y is Map ? y : null;
  } on YamlException {
    return null;
  }
}

String _rel(String root, String path) =>
    p.relative(path, from: root).replaceAll(r'\', '/');

/// The workspace root at or above [start]: the folder of buildkit_master.yaml.
String? releaseWorkspaceRoot(String start) {
  var dir = p.normalize(p.absolute(start));
  while (true) {
    if (File(p.join(dir, 'buildkit_master.yaml')).existsSync()) return dir;
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}
