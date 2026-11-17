#!/usr/bin/env dart

/// wssetup: set up the directory tree after a checkout, from repos.yaml.
///
/// Run with `--help` for usage; `buildkit :wssetup` runs the same.
library;

import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/src/wssetup/wssetup_tool.dart';

Future<void> main(List<String> args) async {
  await ToolRunner(
    tool: wssetupTool,
    executors: {'default': WssetupExecutor()},
  ).runToCompletion(args);
}
