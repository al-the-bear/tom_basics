/// Minimal example of a tool built with `tom_build_base`.
///
/// Defines a multi-command tool with two commands (`hello` and `list`)
/// and runs it via [ToolRunner].
library;

import 'dart:io';

import 'package:tom_build_base/tom_build_base.dart';

/// Tool definition — declared once, immutable.
const exampleTool = ToolDefinition(
  name: 'example',
  description: 'Example tool demonstrating tom_build_base',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.projectTool,
  commands: [
    CommandDefinition(
      name: 'hello',
      description: 'Print a greeting for each project',
      aliases: ['hi'],
    ),
    CommandDefinition(
      name: 'list',
      description: 'List discovered Dart projects',
      aliases: ['ls'],
      requiredNatures: {DartProjectFolder},
    ),
  ],
);

void main(List<String> args) async {
  final runner = ToolRunner(
    tool: exampleTool,
    executors: {
      'hello': CallbackExecutor(
        onExecute: (context, args) async {
          print('Hello from ${context.name}!');
          return ItemResult.success(path: context.path, name: context.name);
        },
      ),
      'list': CallbackExecutor(
        onExecute: (context, args) async {
          final dart = context.getNature<DartProjectFolder>();
          print('  ${dart.projectName} v${dart.version}');
          return ItemResult.success(path: context.path, name: context.name);
        },
      ),
    },
  );

  final result = await runner.run(args);
  exit(result.success ? 0 : 1);
}
