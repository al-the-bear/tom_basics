// Copyright (c) 2026. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// `analyzer_cache_gc` — opt-in maintenance CLI for the shared analyzer cache.
///
/// Built on the tom_build_base v2 tool framework so it behaves consistently
/// with the other Tom CLIs (help/version formatting, arg parsing). Both
/// commands are global (no project traversal): they operate on the machine's
/// shared `analyzer-cache` root, not on the current project.
library;

import 'package:tom_build_base/tom_build_base_v2.dart';

/// `--root` — override the resolved `analyzer-cache` root (mainly for CI/tests).
const _rootOption = OptionDefinition.option(
  name: 'root',
  description:
      'Analyzer-cache root to operate on (default: resolved from the Tom tool '
      'cache for the current directory)',
  valueName: 'dir',
);

/// Options for the `list` command.
const listOptions = <OptionDefinition>[_rootOption];

/// Options for the `clean` command.
///
/// `--dry-run` is intentionally not declared here: it is a global navigation
/// flag (surfaced via [NavigationFeatures.dryRun]) and read from
/// [CliArgs.dryRun], so declaring it again as a command option would be a
/// redundant duplicate in the help output.
const cleanOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'older-than',
    description:
        'Delete partitions unused for more than this many days (default: 90)',
    valueName: 'days',
    defaultValue: '90',
  ),
  OptionDefinition.flag(
    name: 'include-current',
    description:
        "Also delete the current toolchain's partition if it is old enough "
        '(by default the live partition is always protected)',
  ),
  _rootOption,
];

/// `list` — enumerate cache partitions with last-used time and size.
const listCommand = CommandDefinition(
  name: 'list',
  aliases: ['ls'],
  description: 'List analyzer-cache partitions with last-used time and size',
  options: listOptions,
  requiresTraversal: false,
  supportsProjectTraversal: false,
  examples: [
    'analyzer_cache_gc list',
    'analyzer_cache_gc list --root /path/to/.tom/analyzer-cache',
  ],
);

/// `clean` — delete partitions older than a caller-supplied threshold.
const cleanCommand = CommandDefinition(
  name: 'clean',
  aliases: ['gc'],
  description:
      'Delete cache partitions unused for longer than --older-than days',
  options: cleanOptions,
  requiresTraversal: false,
  supportsProjectTraversal: false,
  examples: [
    'analyzer_cache_gc clean --older-than 90',
    'analyzer_cache_gc clean --older-than 30 --dry-run',
    'analyzer_cache_gc clean --older-than 180 --include-current',
  ],
);

/// Tool version — tracks the `tom_analyzer_shared` pubspec version.
///
/// Bump in lockstep with `pubspec.yaml` when publishing.
const analyzerCacheGcVersion = '0.7.3';

/// The `analyzer_cache_gc` tool definition (multi-command, both global).
final analyzerCacheGcTool = ToolDefinition(
  name: 'analyzercachegc',
  description:
      'Opt-in garbage collector for the shared analyzer summary cache',
  version: analyzerCacheGcVersion,
  versionString: 'Analyzer Cache GC $analyzerCacheGcVersion',
  mode: ToolMode.multiCommand,
  defaultCommand: 'list',
  features: const NavigationFeatures(
    projectTraversal: false,
    gitTraversal: false,
    recursiveScan: false,
    interactiveMode: false,
    dryRun: true,
    jsonOutput: false,
    verbose: true,
  ),
  commands: const [listCommand, cleanCommand],
  helpFooter: '''
The analyzer summary cache is partitioned by <analyzer-major>/<dart-sdk-version>
so a toolchain change starts from a fresh partition. Retired partitions are
never reclaimed automatically because the cache is shared across every project
on the machine. This tool lets a human or CI reclaim that space deliberately:

  analyzer_cache_gc list                      # inspect partitions
  analyzer_cache_gc clean --older-than 90     # prune stale partitions

The live partition is always protected unless --include-current is given.
''',
);
