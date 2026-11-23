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
/// them unchanged. A failed run removes the entry.
///
/// **Outputs.** A step that writes files outside the project names them
/// ([DeclaresStepInputs.stepOutputs]; `:compiler` its binaries). They are
/// kept in the state with the fingerprint, and each gets a record beside it
/// (`<output>.buildkit.json`, output_records.dart). An up-to-date project
/// still runs when one of them is missing or is not the one its record and
/// the fingerprint describe ([staleOutputReason]). `.dart_tool` is gitignored,
/// and deleting it (`dart pub get` does not, `flutter clean` does) makes every
/// step run again.
///
/// **Shared records.** A workspace that takes its tools from a binaries
/// layer (its `buildkit_master.yaml` names it, `required-environment:
/// binaryPath: $TOM_BINARY_PATH`) also writes every recorded state to
/// `<binaries>/.buildkit/steps/<project>.json` ([SharedStepRecords];
/// `<project>` the project's path from the run's root (`-R`) or else the
/// outermost workspace root). A step that builds for the host's platform
/// (`:compiler`) keeps its record per platform instead, in
/// `<binaries>/<platform>/.buildkit/steps/` (`<platform>` e.g.
/// `darwin-arm64`); the others (`:versioner`, the generators: code committed
/// with the project) are shared by every platform. The binaries layer
/// commits the records with the binaries, so another host or clone that
/// pulled both finds the step's state for the same inputs there and skips
/// the step, reporting `up to date (fingerprint)`; the project's own
/// `steps.json` stays the fast path and is filled from it. Nothing in a record names a host: the fingerprint hashes
/// relative paths and the step's configuration without absolute paths, and
/// an output under the step's output folder
/// ([DeclaresStepInputs.outputsRoot]; `:compiler` `TOM_BINARY_PATH`) is
/// recorded relative to it. With the binaries path unset or empty, or for a
/// project in a scratch folder (`.dart_tool`, `ztmp`: a test's fixture),
/// only `steps.json` is used. A failed run removes the project's own entry,
/// not the shared one.
///
/// **The project's final state.** A step whose result does not depend on
/// what later steps of the run write into the project
/// ([DeclaresStepInputs.recordsFinalState]: `:versioner`, the generators)
/// is recorded again with the project as the run leaves it. Otherwise a
/// generator that rewrites files after `:versioner` would make the next run
/// (here, or on the host that pulled the result) see changed inputs and
/// stamp a new build.
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

import '../../platform_utils.dart';
import '../../version.versioner.dart';
import '../dart_sdk_version.dart';
import 'output_records.dart';

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

  /// The files outside [context]'s project the step's last [execute] there
  /// wrote (absolute paths); none by default.
  List<String> stepOutputs(CommandContext context) => const [];

  /// The folder the step's outputs go to (absolute), or null. An output in
  /// it is recorded relative to it, so a record read on another host, or
  /// after the folder moved, names the output where it is now.
  String? outputsRoot(CommandContext context) => null;

  /// Whether the step's result differs from platform to platform (`:compiler`
  /// builds the host's binaries). Its shared record is kept per platform;
  /// another step's (a generator's, `:versioner`'s: code committed with the
  /// project) is shared by every platform. False by default.
  bool get platformSpecific => false;

  /// Whether the step's state is recorded again with the project as the run
  /// leaves it (see the library comment). False by default: a later step
  /// that rewrites one of its inputs makes it run once more.
  bool get recordsFinalState => false;
}

/// The message of a project skipped because its inputs did not change.
const String upToDateMessage = 'up to date';

/// The message of a project skipped by a shared record: its inputs are
/// those of a run on another host or in another clone.
const String upToDateByFingerprintMessage = 'up to date (fingerprint)';

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
  Future<ItemResult?> afterTraversal(
    List<ItemResult> results,
    CliArgs args,
  ) async {
    final extra = await inner.afterTraversal(results, args);
    await renewFinalStates();
    return extra;
  }

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    _executions++;
    if (args.listOnly ||
        args.dumpConfig ||
        !inner.tracksInputs(context, args)) {
      return inner.execute(context, args);
    }
    final local = StepState(context.path);
    final shared = SharedStepRecords.forProject(
      context.path,
      platformSpecific: inner.platformSpecific,
    );
    final label = sharedProjectLabel(context.path, root: args.root);
    final root = inner.outputsRoot(context);
    final step = inner.stepName;
    final configuration = inner.stepConfiguration(context, args);
    final force = args.force || args.optionsFor(step)['force'] == true;
    if (!force) {
      final sources = [
        (state: local, byFingerprint: false),
        if (shared != null) (state: shared.of(label), byFingerprint: true),
      ];
      String? fingerprint;
      for (final source in sources) {
        final recorded = source.state.read(step);
        if (recorded == null) continue;
        fingerprint ??= await stepFingerprint(
          projectPath: context.path,
          step: step,
          configuration: configuration,
        );
        if (recorded.fingerprint != fingerprint) continue;
        final outputs = resolveOutputs(recorded.outputs, root);
        final stale = [
          for (final output in outputs)
            ?staleOutputReason(output, recorded.fingerprint),
        ];
        if (stale.isNotEmpty) {
          print(
            '  ${context.name}: :$step runs again, inputs unchanged but '
            '${stale.join('; ')}',
          );
          break;
        }
        if (source.byFingerprint) {
          print(
            '  ${context.name}: :$step $upToDateByFingerprintMessage '
            '(inputs as recorded in ${shared!.dir}; --force runs it)',
          );
          if (!args.dryRun) {
            local.write(step, fingerprint, outputs: recorded.outputs);
          }
        } else {
          print(
            '  ${context.name}: :$step $upToDateMessage (inputs unchanged; '
            '--force runs it)',
          );
        }
        if (!args.dryRun) {
          _rememberFinalState(
            context.path,
            label,
            configuration,
            recorded.outputs,
          );
        }
        return ItemResult.skipped(
          path: context.path,
          name: context.name,
          message: source.byFingerprint
              ? upToDateByFingerprintMessage
              : upToDateMessage,
        );
      }
    }
    final result = await inner.execute(context, args);
    if (args.dryRun) return result;
    if (result.success && !result.skipped) {
      final fingerprint = await stepFingerprint(
        projectPath: context.path,
        step: step,
        configuration: configuration,
      );
      // An output inside the project is one of its inputs already (hashed
      // into the fingerprint); a record there would change the next one.
      final outputs = [
        for (final output in inner.stepOutputs(context))
          if (!p.isWithin(context.path, output) && File(output).existsSync())
            output,
      ];
      for (final output in outputs) {
        writeOutputRecord(
          binary: output,
          project: _projectLabel(context.path),
          buildkitVersion: BuildkitVersionInfo.version,
          fingerprint: fingerprint,
        );
      }
      final recorded = recordedOutputs(outputs, root);
      local.write(step, fingerprint, outputs: recorded);
      if (shared != null && recorded.every((o) => !p.isAbsolute(o))) {
        shared.of(label).write(step, fingerprint, outputs: recorded);
      }
      _rememberFinalState(context.path, label, configuration, recorded);
    } else if (!result.success) {
      local.remove(step);
    }
    return result;
  }

  /// The steps to record again with the project as the run leaves it, by
  /// project and step.
  static final Map<String, _FinalState> _finalStates = {};

  /// Steps executed in this run, and the count at the last renewal.
  static int _executions = 0;
  static int _renewedAt = -1;

  void _rememberFinalState(
    String projectPath,
    String label,
    String configuration,
    List<String> outputs,
  ) {
    if (!inner.recordsFinalState) return;
    final path = p.normalize(p.absolute(projectPath));
    _finalStates['$path\n${inner.stepName}'] = (
      projectPath: path,
      label: label,
      step: inner.stepName,
      platformSpecific: inner.platformSpecific,
      configuration: configuration,
      outputs: outputs,
    );
  }

  /// Records every step of this run that [DeclaresStepInputs.recordsFinalState]
  /// again, with the fingerprint of its project as it is now (see the library
  /// comment). Called after each step's traversal: the last call sees the
  /// project as the run leaves it.
  static Future<void> renewFinalStates() async {
    // The steps' afterTraversal hooks follow one another after the
    // traversal: once is enough unless a step ran in between (a run that
    // goes command by command).
    if (_finalStates.isEmpty || _renewedAt == _executions) return;
    _renewedAt = _executions;
    final inputs = <String, String>{};
    for (final state in _finalStates.values) {
      final shared = SharedStepRecords.forProject(
        state.projectPath,
        platformSpecific: state.platformSpecific,
      );
      final fingerprint = await stepFingerprint(
        projectPath: state.projectPath,
        step: state.step,
        configuration: state.configuration,
        inputsHash: inputs[state.projectPath] ??= projectInputsHash(
          state.projectPath,
        ),
      );
      StepState(
        state.projectPath,
      ).write(state.step, fingerprint, outputs: state.outputs);
      if (shared != null && state.outputs.every((o) => !p.isAbsolute(o))) {
        shared
            .of(state.label)
            .write(state.step, fingerprint, outputs: state.outputs);
      }
    }
  }

  /// The project as a record names it: its path from the workspace root
  /// (the run's context name is `.` for the project the run started in).
  static String _projectLabel(String projectPath) {
    final root = findWorkspaceRootOrNull(projectPath);
    return root == null || !p.isWithin(root, projectPath)
        ? p.basename(projectPath)
        : p.relative(projectPath, from: root).replaceAll(r'\', '/');
  }
}

typedef _FinalState = ({
  String projectPath,
  String label,
  bool platformSpecific,
  String step,
  String configuration,
  List<String> outputs,
});

/// [outputs] as a state records them: relative to [root] (with `/`) when in
/// it, else absolute.
List<String> recordedOutputs(List<String> outputs, String? root) => [
  for (final output in outputs)
    root != null && p.isWithin(root, output)
        ? p.relative(output, from: root).replaceAll(r'\', '/')
        : output,
];

/// The recorded [outputs] as paths on this host: a relative one under
/// [root]. A relative output without a root names no file (a record whose
/// output folder is not set here), and is reported missing.
List<String> resolveOutputs(List<String> outputs, String? root) => [
  for (final output in outputs)
    p.isAbsolute(output)
        ? output
        : p.normalize(p.join(root ?? '<no output folder>', output)),
];

/// The project's path, with `/`, from [root] (the run's `-R`) or else the
/// outermost workspace root above it: the name of its shared record, the same
/// in every clone and in a nested workspace's own run. Its folder name
/// outside a workspace. Two projects of one name share a record file but
/// never a fingerprint (it hashes the project's files): a clash costs a
/// rebuild, it never skips one.
String sharedProjectLabel(String projectPath, {String? root}) {
  final path = p.normalize(p.absolute(projectPath));
  if (root != null) {
    final base = p.normalize(p.absolute(root));
    if (p.isWithin(base, path)) {
      return p.relative(path, from: base).replaceAll(r'\', '/');
    }
  }
  String? outermost;
  for (
    var at = findWorkspaceRootOrNull(path);
    at != null;
    at = findWorkspaceRootOrNull(p.dirname(at))
  ) {
    outermost = at;
    if (p.dirname(at) == at) break;
  }
  return outermost == null || !p.isWithin(outermost, path)
      ? p.basename(path)
      : p.relative(path, from: outermost).replaceAll(r'\', '/');
}

/// The shared step records in the binaries layer: `<binaries>/.buildkit/steps/`,
/// and `<binaries>/<platform>/.buildkit/steps/` for a step whose result is the
/// host platform's (see the library comment).
class SharedStepRecords {
  SharedStepRecords(this.dir);

  /// The records of [projectPath]'s binaries layer, of this host's platform
  /// when [platformSpecific], or null: outside a workspace, in a workspace
  /// that names no binaries layer ([binariesLayer]), or in a scratch folder
  /// (see the library comment).
  static SharedStepRecords? forProject(
    String projectPath, {
    required bool platformSpecific,
  }) {
    final path = p.normalize(p.absolute(projectPath));
    final root = findWorkspaceRootOrNull(path);
    if (root == null) return null;
    if (p
        .split(p.relative(path, from: root))
        .any((segment) => segment == '.dart_tool' || segment == 'ztmp')) {
      return null;
    }
    final binaries = binariesLayer(root);
    if (binaries == null) return null;
    return SharedStepRecords(
      p.joinAll([
        binaries,
        if (platformSpecific) PlatformUtils.getCurrentPlatform(),
        '.buildkit',
        'steps',
      ]),
    );
  }

  /// The folder of the records.
  final String dir;

  /// The record of the project labelled [label] ([sharedProjectLabel]).
  StepState of(String label) => StepState.at(File(p.join(dir, '$label.json')));
}

/// The binaries layer [workspaceRoot]'s `buildkit_master.yaml` names
/// (`required-environment: binaryPath:`, `$VAR`, `${VAR}` and `$[VAR]`
/// expanded), or null when it names none or it expands to nothing.
String? binariesLayer(String workspaceRoot) {
  final file = File(p.join(workspaceRoot, 'buildkit_master.yaml'));
  if (!file.existsSync()) return null;
  try {
    final yaml = loadYaml(file.readAsStringSync());
    final required = yaml is YamlMap ? yaml['required-environment'] : null;
    final raw = required is YamlMap ? required['binaryPath'] : null;
    if (raw is! String) return null;
    final expanded = raw
        .replaceAllMapped(
          RegExp(r'\$\[(\w+)\]|\$\{(\w+)\}|\$(\w+)'),
          (m) =>
              Platform.environment[m.group(1) ?? m.group(2) ?? m.group(3)] ??
              '',
        )
        .trim();
    return expanded.isEmpty ? null : expanded;
  } on Exception {
    return null;
  }
}

/// The hash of everything a step's result in [projectPath] depends on (see
/// the library comment).
/// [inputsHash] is [projectInputsHash] of [projectPath] when the caller has
/// it already.
Future<String> stepFingerprint({
  required String projectPath,
  required String step,
  required String configuration,
  String? inputsHash,
}) async => _hashLines([
  'buildkit ${BuildkitVersionInfo.version}',
  'dart ${await dartSdkVersion() ?? '?'}',
  'step $step',
  'configuration ${configuration.length}',
  configuration,
  'inputs ${inputsHash ?? projectInputsHash(projectPath)}',
]);

/// The hash of [projectPath]'s files, its `pubspec.lock` and
/// `pubspec_overrides.yaml`, and the files of its path dependencies: what a
/// step's result depends on in the project itself (see the library comment).
/// Relative paths only, so the same project in another clone hashes the same.
String projectInputsHash(String projectPath) {
  final lines = <String>[];
  _addFiles(lines.add, 'project', projectPath);
  for (final name in const ['pubspec.lock', 'pubspec_overrides.yaml']) {
    lines.add('$name ${_fileHash(File(p.join(projectPath, name)))}');
  }
  for (final dep in pathDependencies(projectPath)) {
    _addFiles(lines.add, 'dependency ${dep.name}', dep.path);
  }
  return _hashLines(lines);
}

String _hashLines(Iterable<String> lines) {
  final sink = _HashSink();
  final input = sha256.startChunkedConversion(sink);
  for (final line in lines) {
    input.add(utf8.encode('$line\n'));
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

  /// The state kept in [file] (a shared record, [SharedStepRecords]).
  StepState.at(this.file);

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

  /// What is recorded for [step]: the fingerprint and the outputs it wrote,
  /// or null.
  ({String fingerprint, List<String> outputs})? read(String step) {
    final value = _load()[step];
    if (value is String) return (fingerprint: value, outputs: const []);
    if (value is Map && value['fingerprint'] is String) {
      final outputs = value['outputs'];
      return (
        fingerprint: value['fingerprint'] as String,
        outputs: [
          if (outputs is List)
            for (final o in outputs)
              if (o is String) o,
        ],
      );
    }
    return null;
  }

  /// Records [fingerprint] for [step], and the files outside the project
  /// the run wrote ([outputs]).
  void write(
    String step,
    String fingerprint, {
    List<String> outputs = const [],
  }) {
    final state = _load();
    final entry = outputs.isEmpty
        ? fingerprint
        : {'fingerprint': fingerprint, 'outputs': outputs};
    // Unchanged: left alone, so a shared record is not rewritten.
    if (jsonEncode(state[step]) == jsonEncode(entry)) return;
    _save(state..[step] = entry);
  }

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
