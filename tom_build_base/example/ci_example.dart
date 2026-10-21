/// A CI tool on `package:tom_build_base/ci.dart`: two stages, each running
/// `dart analyze` or `dart test` in this package, one log per step under
/// `testlog/<timestamp>/`, and one summary line at the end.
///
/// ```sh
/// dart run example/ci_example.dart --help
/// dart run example/ci_example.dart :analyze
/// ```
library;

import 'dart:io';

import 'package:tom_build_base/ci.dart';

const stages = ['analyze', 'test'];
const descriptions = {
  'analyze': 'dart analyze in this package',
  'test': 'dart test in this package',
  'all': 'both, in that order, past a red',
};

Future<void> main(List<String> args) async {
  final root = Directory.current.path;
  final package = CiPackage(
    name: 'tom_build_base',
    directory: root,
    isFlutter: ciIsFlutterPackage(root),
  );
  final tool = ciToolDefinition(
    name: 'ci_example',
    description: 'A two-stage CI, run by hand.',
    version: '1.0.0',
    stages: stages,
    descriptions: descriptions,
    examplePrefix: 'dart run example/ci_example.dart',
  );
  final runner = ciToolRunner(
    tool: tool,
    runStages: (requested, console) => CiRun(
      toolName: 'ci_example',
      repositoryRoot: root,
      lockPath: ciFlutterLockPath(repositoryRoot: root),
      stageDescriptions: descriptions,
      console: console,
      runStage: (run, stage) => run.step(stage, package.name, '$stage.log', [
        run.tool(package, [stage]),
      ], counts: stage == 'test'),
    ).run(resolveCiStages(requested, stages: stages)),
  );
  final result = await runner.run(args);
  exitCode = result.success ? 0 : 1;
}
