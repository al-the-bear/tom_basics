/// Incremental steps: a step that declares its inputs is skipped in a
/// project whose inputs did not change since the step last succeeded there.
///
/// **The inputs** of a step in a project are hashed into one fingerprint:
/// - the project's files: those git lists (tracked, plus untracked ones not
///   ignored), or every file outside `.dart_tool`, `build` and hidden folders
///   when the project is not in a git work tree;
/// - `pubspec.lock` and `pubspec_overrides.yaml` (a library's lock is
///   gitignored, so it is added by name);
/// - the files of every path dependency the lock names (`source: path`);
/// - the step's configuration ([DeclaresStepInputs.stepConfiguration]):
///   its options on the command line, the workspace's `buildkit_master.yaml`
///   and what else the step reads;
/// - the buildkit version and the Dart SDK version.
///
/// **The state** is `<project>/.dart_tool/buildkit/steps.json`: per step the
/// hash of the fingerprint taken right after its last successful run, so the
/// files the step itself wrote count as its inputs and the next run finds
/// them unchanged. A failed run removes the entry. `.dart_tool` is gitignored,
/// and deleting it (`dart pub get` does not, `flutter clean` does) makes every
/// step run again.
///
/// `--force` runs the step anyway (and records the new state). A dry run
/// skips an up-to-date project and records nothing. A step that does not
/// implement [DeclaresStepInputs] always runs.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:yaml/yaml.dart';

import '../../version.versioner.dart';
import '../dart_sdk_version.dart';

/// A step executor that declares what its result depends on.
mixin DeclaresStepInputs on CommandExecutor {
  /// The step's name, the key of its entry in the state file.
  String get stepName;

  /// Whether the step works on [context]'s project in this run with inputs
  /// it can name. False lets the step run as it would without this mixin
  /// (and hashes nothing): a project it does not apply to, or a mode that is
  /// not a build (e.g. `build_runner watch`).
  bool tracksInputs(CommandContext context, CliArgs args);

  /// What, besides the project's files, the step's result depends on, as
  /// text: its options, the configuration it reads. Equal text means equal
  /// configuration.
  String stepConfiguration(CommandContext context, CliArgs args);
}

/// The message of a project skipped because its inputs did not change.
const String upToDateMessage = 'up to date';

/// Runs [inner] in a project unless its inputs are unchanged since its last
/// successful run there.
class IncrementalStep extends CommandExecutor {
  IncrementalStep(this.inner);

  /// The step that declares its inputs.
  final DeclaresStepInputs inner;

  @override
  bool get handlesListMode => inner.handlesListMode;

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) =>
      inner.executeWithoutTraversal(args);

  @override
  Future<ItemResult?> afterTraversal(List<ItemResult> results, CliArgs args) =>
      inner.afterTraversal(results, args);

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    if (args.listOnly ||
        args.dumpConfig ||
        !inner.tracksInputs(context, args)) {
      return inner.execute(context, args);
    }
    final state = StepState(context.path);
    final step = inner.stepName;
    final force = args.force || args.optionsFor(step)['force'] == true;
    if (!force) {
      final recorded = state.read(step);
      if (recorded != null && recorded == await _fingerprint(context, args)) {
        print(
          '  ${context.name}: :$step $upToDateMessage (inputs unchanged; '
          '--force runs it)',
        );
        return ItemResult.skipped(
          path: context.path,
          name: context.name,
          message: upToDateMessage,
        );
      }
    }
    final result = await inner.execute(context, args);
    if (args.dryRun) return result;
    if (result.success && !result.skipped) {
      state.write(step, await _fingerprint(context, args));
    } else if (!result.success) {
      state.remove(step);
    }
    return result;
  }

  Future<String> _fingerprint(CommandContext context, CliArgs args) async =>
      stepFingerprint(
        projectPath: context.path,
        step: inner.stepName,
        configuration: inner.stepConfiguration(context, args),
      );
}

/// The hash of everything a step's result in [projectPath] depends on (see
/// the library comment).
Future<String> stepFingerprint({
  required String projectPath,
  required String step,
  required String configuration,
}) async {
  final sink = _HashSink();
  final input = sha256.startChunkedConversion(sink);
  void add(String line) => input.add(utf8.encode('$line\n'));

  add('buildkit ${BuildkitVersionInfo.version}');
  add('dart ${await dartSdkVersion() ?? '?'}');
  add('step $step');
  add('configuration ${configuration.length}');
  add(configuration);
  _addFiles(add, 'project', projectPath);
  for (final name in const ['pubspec.lock', 'pubspec_overrides.yaml']) {
    add('$name ${_fileHash(File(p.join(projectPath, name)))}');
  }
  for (final dep in pathDependencies(projectPath)) {
    _addFiles(add, 'dependency ${dep.name}', dep.path);
  }
  input.close();
  return sink.value.toString();
}

void _addFiles(void Function(String) add, String label, String dir) {
  final files = projectFiles(dir);
  add('$label ${files.length}');
  for (final rel in files) {
    add('$rel ${_fileHash(File(p.join(dir, rel)))}');
  }
}

String _fileHash(File file) {
  try {
    return sha256.convert(file.readAsBytesSync()).toString();
  } on FileSystemException {
    return 'missing';
  }
}

/// The files of [dir], relative to it with `/`, sorted: what git lists
/// (tracked, plus untracked files not ignored), else (outside a git work
/// tree, or in a folder git ignores) every file outside `.dart_tool`,
/// `build` and hidden folders.
List<String> projectFiles(String dir) {
  final git = Process.runSync(
    'git',
    ['ls-files', '-z', '--cached', '--others', '--exclude-standard'],
    workingDirectory: dir,
    stdoutEncoding: utf8,
    runInShell: Platform.isWindows,
  );
  var files = <String>[];
  if (git.exitCode == 0) {
    files = (git.stdout as String)
        .split('\x00')
        .where((f) => f.isNotEmpty && !f.startsWith('.dart_tool/'))
        .toSet()
        .toList();
  }
  // Not in a git work tree, or in a folder git ignores (git lists nothing).
  if (files.isEmpty) {
    files = [
      for (final entity in _walk(Directory(dir)))
        p.relative(entity.path, from: dir).replaceAll(r'\', '/'),
    ];
  }
  return files..sort();
}

Iterable<File> _walk(Directory dir) sync* {
  final List<FileSystemEntity> entries;
  try {
    entries = dir.listSync(followLinks: false);
  } on FileSystemException {
    return;
  }
  for (final entity in entries) {
    final name = p.basename(entity.path);
    if (entity is File) {
      yield entity;
    } else if (entity is Directory &&
        !name.startsWith('.') &&
        name != 'build') {
      yield* _walk(entity);
    }
  }
}

/// The path dependencies [projectPath]'s `pubspec.lock` names
/// (`source: path`), with absolute paths, sorted by name. Empty without a
/// readable lock.
List<({String name, String path})> pathDependencies(String projectPath) {
  final lock = File(p.join(projectPath, 'pubspec.lock'));
  if (!lock.existsSync()) return const [];
  try {
    final packages =
        (loadYaml(lock.readAsStringSync()) as YamlMap?)?['packages'];
    if (packages is! YamlMap) return const [];
    final deps = <({String name, String path})>[];
    for (final entry in packages.entries) {
      final value = entry.value;
      if (value is! YamlMap || value['source'] != 'path') continue;
      final description = value['description'];
      final path = description is YamlMap ? description['path'] : null;
      if (path is! String) continue;
      deps.add((
        name: entry.key.toString(),
        path: p.normalize(p.join(projectPath, path)),
      ));
    }
    return deps..sort((a, b) => a.name.compareTo(b.name));
  } on Exception {
    return const [];
  }
}

/// The text of the workspace's `buildkit_master.yaml` above [projectPath],
/// or '' when there is none; part of every step's configuration.
String masterConfiguration(String projectPath) {
  final root = findWorkspaceRootOrNull(projectPath);
  if (root == null) return '';
  final file = File(p.join(root, 'buildkit_master.yaml'));
  return file.existsSync() ? file.readAsStringSync() : '';
}

/// [options] as stable text: sorted keys, `force` left out (it decides
/// whether to skip, not what the step does).
String optionsText(Map<String, dynamic> options) {
  final keys = options.keys.where((k) => k != 'force').toList()..sort();
  return [for (final k in keys) '$k=${options[k]}'].join('\n');
}

/// The recorded fingerprints of a project's steps,
/// `<project>/.dart_tool/buildkit/steps.json`.
class StepState {
  StepState(String projectPath)
    : file = File(p.join(projectPath, '.dart_tool', 'buildkit', 'steps.json'));

  /// The state file.
  final File file;

  Map<String, dynamic> _load() {
    if (!file.existsSync()) return {};
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      return {};
    }
  }

  /// The fingerprint recorded for [step], or null.
  String? read(String step) {
    final value = _load()[step];
    return value is String ? value : null;
  }

  /// Records [fingerprint] for [step].
  void write(String step, String fingerprint) =>
      _save(_load()..[step] = fingerprint);

  /// Forgets [step].
  void remove(String step) {
    final state = _load();
    if (state.remove(step) != null) _save(state);
  }

  void _save(Map<String, dynamic> state) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(state)}\n',
    );
  }
}

class _HashSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
