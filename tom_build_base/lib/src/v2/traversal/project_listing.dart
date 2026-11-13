import 'package:path/path.dart' as p;

import '../core/cli_arg_parser.dart';
import '../folder/natures/natures.dart';
import '../folder/run_folder.dart';
import 'build_base.dart';
import 'command_context.dart';
import 'traversal_info.dart';

/// The projects of a workspace as every tool built on tom_build_base sees
/// them: the folders a project command visits, with their identity and
/// natures.
///
/// A machine-readable answer for callers outside Dart (the VS Code extension
/// lists projects with it through `buildkit :projects --json`); there is no
/// generated workspace manifest to read instead.
class ListedProject {
  /// `project_id` from the project's `buildkit.yaml`, else [name].
  final String id;

  /// `name` from `buildkit.yaml`, else the name its project file states
  /// (pubspec, package.json, ...), else the folder name.
  final String name;

  /// Path relative to the execution root, with `/` separators.
  final String path;

  /// Absolute path.
  final String absolutePath;

  /// The language of the primary nature ([primaryProjectNature]):
  /// `dart`, `typescript`, `javascript`, `python`, `java`, `go`, `rust`, `c`,
  /// `cpp`.
  final String language;

  /// Name of the primary nature ([natureName]), e.g. `flutter`,
  /// `dart_package`, `python`.
  final String type;

  /// Names of every nature of the folder ([natureName]), in detection order.
  final List<String> natures;

  /// The version the project file states, if it does.
  final String? version;

  /// `description` from `buildkit.yaml`, if it has one.
  final String? description;

  const ListedProject({
    required this.id,
    required this.name,
    required this.path,
    required this.absolutePath,
    required this.language,
    required this.type,
    required this.natures,
    this.version,
    this.description,
  });

  /// The entry for a project command's [context], or null when the folder
  /// has no project nature (a Dart or other language project).
  static ListedProject? fromContext(CommandContext context) {
    final primary = primaryProjectNature(context.natures);
    if (primary == null) return null;
    final buildkit = context.tryGetNature<BuildkitFolder>();
    final String? fileName;
    final String? version;
    final String language;
    switch (primary) {
      case DartProjectFolder(:final projectName, version: final v):
        fileName = projectName;
        version = v;
        language = 'dart';
      case LanguageProjectFolder(:final projectName, version: final v):
        fileName = projectName;
        version = v;
        language = primary.language;
      default:
        return null;
    }
    final name =
        _nonEmpty(buildkit?.projectName) ?? _nonEmpty(fileName) ?? context.name;
    return ListedProject(
      id: _nonEmpty(buildkit?.projectId) ?? name,
      name: name,
      path: context.relativePath.isEmpty ? '.' : context.relativePath,
      absolutePath: p.normalize(p.absolute(context.path)),
      language: language,
      type: natureName(primary),
      natures: [for (final n in context.natures) natureName(n)],
      version: _nonEmpty(version),
      description: _nonEmpty(buildkit?.description),
    );
  }

  /// The JSON object of this entry; absent optional fields are left out.
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'absolutePath': absolutePath,
    'language': language,
    'type': type,
    'natures': natures,
    'version': ?version,
    'description': ?description,
  };

  static String? _nonEmpty(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();
}

/// The nature that decides a project's language and defaults when it has
/// several: Flutter, Dart, then TypeScript, JavaScript, Python, Java, Go,
/// Rust, C++, C. Null when the folder has no project nature.
RunFolder? primaryProjectNature(List<RunFolder> natures) {
  for (final pick in <bool Function(RunFolder)>[
    (n) => n is FlutterProjectFolder,
    (n) => n is DartProjectFolder,
    (n) => n is TypeScriptFolder,
    (n) => n is JavaScriptFolder,
    (n) => n is PythonFolder,
    (n) => n is JavaFolder,
    (n) => n is GoFolder,
    (n) => n is RustFolder,
    (n) => n is CppFolder,
    (n) => n is CFolder,
  ]) {
    for (final n in natures) {
      if (pick(n)) return n;
    }
  }
  return null;
}

/// The short name of a nature in machine-readable output: `flutter`,
/// `dart_console`, `dart_package`, `dart`, the language of a
/// [LanguageProjectFolder] (`typescript`, `python`, ...), `git`, `buildkit`,
/// `build_runner`, `vscode_extension`, `workspace_root`; any other nature by
/// its type name.
String natureName(RunFolder nature) => switch (nature) {
  FlutterProjectFolder() => 'flutter',
  DartConsoleFolder() => 'dart_console',
  DartPackageFolder() => 'dart_package',
  DartProjectFolder() => 'dart',
  LanguageProjectFolder(:final language) => language,
  GitFolder() => 'git',
  BuildkitFolder() => 'buildkit',
  BuildRunnerFolder() => 'build_runner',
  VsCodeExtensionFolder() => 'vscode_extension',
  BuildkitMasterFolder() => 'workspace_root',
  _ => nature.runtimeType.toString(),
};

/// Every project the traversal [info] selects, in its order (build order by
/// default): exactly the folders a command working on Dart and other language
/// projects visits ([BuildBase.traverse]), as [ListedProject]s.
Future<List<ListedProject>> listProjects(ProjectTraversalInfo info) async {
  final projects = <ListedProject>[];
  await BuildBase.traverse(
    info: info,
    worksWithNatures: const {DartProjectFolder, LanguageProjectFolder},
    allowUnmatchedProjectPatterns: true,
    run: (context) async {
      final project = ListedProject.fromContext(context);
      if (project != null) projects.add(project);
      return true;
    },
  );
  return projects;
}

/// [listProjects] for [args] as a tool parsed them, rooted at
/// [executionRoot], with the `navigation:` defaults of the workspace's
/// `buildkit_master.yaml` ([TraversalDefaults.load]) — the selection a
/// project command given the same arguments would make.
///
/// [navigationDefaults] false leaves those defaults out (their `exclude:`
/// patterns keep whole subtrees from the build commands): every project of
/// the tree, as far as skip markers and [args] allow.
Future<List<ListedProject>> listProjectsFor(
  CliArgs args, {
  required String executionRoot,
  bool navigationDefaults = true,
}) => listProjects(
  args.toProjectTraversalInfo(
    executionRoot: executionRoot,
    configDefaults: navigationDefaults
        ? TraversalDefaults.load(executionRoot)
        : null,
  ),
);
