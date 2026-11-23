/// The code generators buildkit runs as nested tools (`:d4rtgen`,
/// `:reflectiongenerator`, `:reflector`) as incremental steps: a project
/// whose inputs did not change since the generator last succeeded there (or
/// on another host, step_inputs.dart's shared records) is skipped without
/// starting the generator.
///
/// **A generator applies** to a project with its section in `buildkit.yaml`
/// (`d4rtgen:`, `tom_reflection_generator:`, `tom_reflector:`); the
/// reflection generator also to one with a `build.yaml`, which it reads when
/// the section is missing. Elsewhere it runs as wired (and decides itself).
///
/// **Its configuration** is its options on the command line, the
/// workspace's `buildkit_master.yaml` and the generator's own `--version`
/// (a new generator build generates again). The files it writes into the
/// project are inputs of the next run, and it records the project as the run
/// leaves it ([DeclaresStepInputs.recordsFinalState]).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart' show hasTomBuildConfig;
import 'package:tom_build_base/tom_build_base_v2.dart';

import 'step_inputs.dart';

/// Whether the generator wired as a command applies to a project, by command.
final Map<String, bool Function(String projectPath)> generatorApplies = {
  'd4rtgen': (path) => hasTomBuildConfig(path, 'd4rtgen'),
  'reflectiongenerator': (path) =>
      hasTomBuildConfig(path, 'tom_reflection_generator') ||
      File(p.join(path, 'build.yaml')).existsSync(),
  'reflector': (path) => hasTomBuildConfig(path, 'tom_reflector'),
};

/// The [ToolRunner.wiredExecutorWrapper] of buildkit: a wired generator
/// ([generatorApplies]) runs as an [IncrementalStep]; every other wired
/// command as it is.
CommandExecutor wrapWiredGenerator(String command, CommandExecutor executor) {
  final applies = generatorApplies[command];
  return applies == null
      ? executor
      : IncrementalStep(GeneratorStep(command, executor, applies));
}

/// A wired generator that declares its inputs (see the library comment).
class GeneratorStep extends CommandExecutor with DeclaresStepInputs {
  GeneratorStep(this.stepName, this.generator, this.applies);

  @override
  final String stepName;

  /// The wired executor that runs the generator.
  final CommandExecutor generator;

  /// Whether the generator applies to a project.
  final bool Function(String projectPath) applies;

  @override
  bool get recordsFinalState => true;

  @override
  bool get handlesListMode => generator.handlesListMode;

  @override
  bool tracksInputs(CommandContext context, CliArgs args) =>
      applies(context.path);

  @override
  String stepConfiguration(CommandContext context, CliArgs args) =>
      '${optionsText(args.optionsFor(stepName))}\n'
      'generator ${_generatorVersion()}\n'
      '${masterConfiguration(context.path)}';

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) =>
      generator.execute(context, args);

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) =>
      generator.executeWithoutTraversal(args);

  @override
  Future<ItemResult?> afterTraversal(List<ItemResult> results, CliArgs args) =>
      generator.afterTraversal(results, args);

  /// The generator's `--version` output, by binary, asked once per run.
  static final Map<String, String> _versions = {};

  String _generatorVersion() {
    final executor = generator;
    if (executor is! NestedToolExecutor) return '';
    return _versions[executor.binary] ??= generatorVersion(executor.binary);
  }
}

/// What [binary] answers to `--version`, or `?` when it does not answer.
String generatorVersion(String binary) {
  try {
    final result = Process.runSync(resolveBinary(binary), const [
      '--version',
    ], runInShell: Platform.isWindows);
    return result.exitCode == 0 ? '${result.stdout}'.trim() : '?';
  } on ProcessException {
    return '?';
  }
}
