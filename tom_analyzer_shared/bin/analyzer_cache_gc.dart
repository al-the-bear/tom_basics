// Copyright (c) 2026. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// `analyzer_cache_gc` — opt-in maintenance CLI for the shared analyzer cache.
///
/// Enumerates and prunes orphaned `<analyzer-major>/<dart-sdk-version>` cache
/// partitions left behind by retired toolchains. See the package README and
/// `src/summary/analyzer_cache_gc.dart` for motivation.
///
/// Run `analyzer_cache_gc --help` for usage information.
library;

import 'package:tom_analyzer_shared/src/cli/analyzer_cache_gc_executors.dart';
import 'package:tom_analyzer_shared/src/cli/analyzer_cache_gc_tool.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main(List<String> args) async {
  // Normalize non-standard -help / -version to --help / --version, matching the
  // other Tom CLIs, then run inside the shared console_markdown zone so
  // help/version/output render consistently with buildkit and testkit.
  final normalizedArgs = ToolRunner.normalizeArgs(args);
  await runWithConsoleMarkdown(() async {
    final runner = ToolRunner(
      tool: analyzerCacheGcTool,
      executors: createAnalyzerCacheGcExecutors(),
    );
    await runner.runToCompletion(normalizedArgs);
  });
}
