/// `:build`, `:test` and `:clean`: one action, run in every selected project
/// with the language's own tool.
///
/// Each project's primary nature picks the default (cargo, go, make, npm /
/// tsc, python, mvn / gradle, dart / flutter); an entry of the action's name
/// in the project's `buildkit.yaml` replaces it:
///
/// ```yaml
/// test: ./run_tests.sh               # one command
/// build:                             # several, in order
///   - npm install
///   - npx tsc -p .
/// clean: false                       # nothing to do
/// ```
library;

import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart'
    show ProcessRunner, TomBuildConfig;
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:yaml/yaml.dart';

/// The actions that behave the same in every language.
enum ProjectAction {
  /// Produce the project's outputs (or, for code without a build step, check
  /// that it compiles).
  build,

  /// Run the project's tests.
  test,

  /// Remove what [build] and [test] produced.
  clean,
}

/// What one action does in one project: shell [commands] run in order in the
/// project folder, then [deletes] (paths or globs relative to it) removed.
/// Both empty: nothing to do.
class ActionStep {
  /// Shell commands, run in order; the first failure stops the step.
  final List<String> commands;

  /// Paths or globs, relative to the project, removed after [commands].
  final List<String> deletes;

  /// Where the step comes from: `buildkit.yaml`, or the nature's default.
  final String origin;

  const ActionStep({
    this.commands = const [],
    this.deletes = const [],
    required this.origin,
  });

  /// Whether the step does nothing.
  bool get isEmpty => commands.isEmpty && deletes.isEmpty;

  /// The step as one line, for listings and dry runs.
  String describe() => [
    ...commands,
    if (deletes.isNotEmpty) 'delete ${deletes.join(' ')}',
  ].join(' && ');
}

/// The nature that decides a project's defaults, when it has several: Dart
/// first, then the other languages.
RunFolder? primaryNature(List<RunFolder> natures) {
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

/// The step of [action] for the project at [projectPath] with [natures]:
/// its `buildkit.yaml` entry when there is one, else the default of its
/// primary nature; null when the project has no nature the action knows.
ActionStep? actionStepFor(
  ProjectAction action,
  String projectPath,
  List<RunFolder> natures,
) {
  final configured = _configuredStep(action, projectPath);
  if (configured != null) return configured;
  final nature = primaryNature(natures);
  if (nature == null) return null;
  return _defaultStep(action, nature, projectPath);
}

/// The `build:` / `test:` / `clean:` entry of the project's buildkit.yaml.
ActionStep? _configuredStep(ProjectAction action, String projectPath) {
  final file = File(p.join(projectPath, TomBuildConfig.projectFilename));
  if (!file.existsSync()) return null;
  final Object? yaml;
  try {
    yaml = loadYaml(file.readAsStringSync());
  } catch (_) {
    return null;
  }
  if (yaml is! YamlMap || !yaml.containsKey(action.name)) return null;
  const origin = 'buildkit.yaml';
  final entry = yaml[action.name];
  if (entry == false || entry == null) return const ActionStep(origin: origin);
  if (entry is String) return ActionStep(commands: [entry], origin: origin);
  if (entry is YamlList) {
    return ActionStep(commands: [for (final c in entry) '$c'], origin: origin);
  }
  throw FormatException(
    '${action.name}: in ${file.path} must be a command, a list of commands, '
    'or false',
  );
}

/// The default step of [action] for a project whose primary nature is
/// [nature].
ActionStep _defaultStep(
  ProjectAction action,
  RunFolder nature,
  String projectPath,
) {
  final origin = 'default (${_natureLabel(nature)})';
  ActionStep run(List<String> commands, [List<String> deletes = const []]) =>
      ActionStep(commands: commands, deletes: deletes, origin: origin);

  switch (nature) {
    case FlutterProjectFolder():
      return switch (action) {
        ProjectAction.build => run(['flutter analyze']),
        ProjectAction.test => run(['flutter test']),
        ProjectAction.clean => run(['flutter clean']),
      };
    case DartProjectFolder():
      return switch (action) {
        ProjectAction.build => run(['dart analyze']),
        ProjectAction.test => run(['dart test']),
        ProjectAction.clean => run(const [], ['build']),
      };
    case TypeScriptFolder(:final scripts):
      final install = _npmInstall(projectPath);
      return switch (action) {
        ProjectAction.build => run([
          ...install,
          scripts.containsKey('build') ? 'npm run build' : 'npx tsc -p .',
        ]),
        ProjectAction.test => run([
          ...install,
          if (scripts.containsKey('test')) 'npm test',
        ]),
        ProjectAction.clean =>
          scripts.containsKey('clean')
              ? run(['npm run clean'])
              : run(const [], ['dist']),
      };
    case JavaScriptFolder(:final scripts):
      final install = _npmInstall(projectPath);
      return switch (action) {
        ProjectAction.build => run([
          if (scripts.containsKey('build')) ...[...install, 'npm run build'],
        ]),
        ProjectAction.test => run([
          ...install,
          scripts.containsKey('test') ? 'npm test' : 'node --test',
        ]),
        ProjectAction.clean => run([
          if (scripts.containsKey('clean')) 'npm run clean',
        ]),
      };
    case PythonFolder():
      return switch (action) {
        ProjectAction.build => run([
          'python3 -m compileall -q -x "(^|/)(\\.|build|dist)" .',
        ]),
        ProjectAction.test => run(['python3 -m pytest -q']),
        ProjectAction.clean => run(const [], [
          'build',
          'dist',
          '*.egg-info',
          '**/__pycache__',
        ]),
      };
    case JavaFolder(:final buildTool):
      if (buildTool == JavaBuildTool.maven) {
        return switch (action) {
          ProjectAction.build => run(['mvn -q -B package -DskipTests']),
          ProjectAction.test => run(['mvn -q -B test']),
          ProjectAction.clean => run(['mvn -q -B clean']),
        };
      }
      final gradle = File(p.join(projectPath, 'gradlew')).existsSync()
          ? './gradlew'
          : 'gradle';
      return switch (action) {
        ProjectAction.build => run(['$gradle build -x test']),
        ProjectAction.test => run(['$gradle test']),
        ProjectAction.clean => run(['$gradle clean']),
      };
    case GoFolder():
      return switch (action) {
        ProjectAction.build => run(['go build ./...']),
        ProjectAction.test => run(['go test ./...']),
        ProjectAction.clean => run(['go clean ./...']),
      };
    case RustFolder():
      return switch (action) {
        ProjectAction.build => run(['cargo build']),
        ProjectAction.test => run(['cargo test']),
        ProjectAction.clean => run(['cargo clean']),
      };
    case NativeProjectFolder(:final buildSystem):
      if (buildSystem == NativeBuildSystem.make) {
        return switch (action) {
          ProjectAction.build => run(['make']),
          ProjectAction.test => run(['make test']),
          ProjectAction.clean => run(['make clean']),
        };
      }
      return switch (action) {
        ProjectAction.build => run([
          'cmake -S . -B build',
          'cmake --build build',
        ]),
        ProjectAction.test => run(['ctest --test-dir build']),
        ProjectAction.clean => run(const [], ['build']),
      };
    default:
      return ActionStep(origin: origin);
  }
}

/// `npm install` first when the project declares dependencies and has no
/// `node_modules` yet.
List<String> _npmInstall(String projectPath) {
  if (Directory(p.join(projectPath, 'node_modules')).existsSync()) return [];
  final json = readPackageJson(File(p.join(projectPath, 'package.json')));
  final hasDeps =
      (json['dependencies'] as Map?)?.isNotEmpty == true ||
      (json['devDependencies'] as Map?)?.isNotEmpty == true;
  return hasDeps ? ['npm install'] : [];
}

String _natureLabel(RunFolder nature) => switch (nature) {
  FlutterProjectFolder() => 'flutter',
  DartProjectFolder() => 'dart',
  LanguageProjectFolder(:final language) => language,
  _ => nature.runtimeType.toString(),
};

/// Executor of one [ProjectAction] in every selected project.
class ProjectActionExecutor extends CommandExecutor {
  /// The action this executor runs.
  final ProjectAction action;

  ProjectActionExecutor(this.action);

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final ActionStep? step;
    try {
      step = actionStepFor(action, context.path, context.natures);
    } on FormatException catch (e) {
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error: e.message,
      );
    }
    if (step == null) {
      return ItemResult.success(
        path: context.path,
        name: context.name,
        message: 'no ${action.name} for this project',
      );
    }
    if (step.isEmpty) {
      print('  ${action.name}: nothing to do (${step.origin})');
      return ItemResult.success(
        path: context.path,
        name: context.name,
        message: 'nothing to ${action.name}',
      );
    }
    if (args.listOnly || args.dryRun) {
      print('  ${action.name}: ${step.describe()}   [${step.origin}]');
      return ItemResult.success(
        path: context.path,
        name: context.name,
        message: args.dryRun ? 'dry run' : 'listed',
      );
    }

    for (final command in step.commands) {
      print('  \$ $command');
      final code = await ProcessRunner.runStreaming(
        Platform.isWindows ? 'cmd' : 'sh',
        Platform.isWindows ? ['/c', command] : ['-c', command],
        workingDirectory: context.path,
      );
      if (code != 0) {
        return ItemResult.failure(
          path: context.path,
          name: context.name,
          error:
              '${action.name} failed: `$command` exited with $code'
              '${code == 127 ? ' (command not found: is the toolchain on PATH?)' : ''}',
          exitCode: 1,
        );
      }
    }
    for (final pattern in step.deletes) {
      _delete(context.path, pattern);
    }
    return ItemResult.success(
      path: context.path,
      name: context.name,
      message: '${action.name} ok',
    );
  }

  void _delete(String projectPath, String pattern) {
    final direct = p.join(projectPath, pattern);
    final type = FileSystemEntity.typeSync(direct, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      print('  delete $pattern');
      _remove(direct, type);
      return;
    }
    if (!pattern.contains('*')) return;
    final matches =
        Glob(pattern)
            .listSync(root: projectPath, followLinks: false)
            .map((e) => e.path)
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    for (final path in matches) {
      final t = FileSystemEntity.typeSync(path, followLinks: false);
      if (t == FileSystemEntityType.notFound) continue;
      print('  delete ${p.relative(path, from: projectPath)}');
      _remove(path, t);
    }
  }

  void _remove(String path, FileSystemEntityType type) {
    if (type == FileSystemEntityType.directory) {
      Directory(path).deleteSync(recursive: true);
    } else {
      File(path).deleteSync();
    }
  }
}
