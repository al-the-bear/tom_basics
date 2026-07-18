// Copyright (c) 2026. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Command executors for the `analyzer_cache_gc` CLI.
library;

import 'package:tom_build_base/tom_build_base_v2.dart';

import '../summary/analyzer_cache_gc.dart';

/// Registers the executors for [analyzerCacheGcTool]'s commands.
Map<String, CommandExecutor> createAnalyzerCacheGcExecutors() => {
      'list': ListPartitionsExecutor(),
      'clean': CleanPartitionsExecutor(),
    };

/// The value-bearing options a caller passed for the active command.
///
/// Value-bearing command options (e.g. `--older-than 30`, `--root <dir>`) are
/// routed by the v2 parser into the per-command options map
/// ([CliArgs.commandArgs]), *not* the top-level [CliArgs.extraOptions]. Both
/// commands here are global (a single active command), so folding every
/// per-command option map over [CliArgs.extraOptions] gives a flat view that is
/// robust to whether the parser used the canonical name or an alias as the key.
Map<String, dynamic> _options(CliArgs args) => {
      ...args.extraOptions,
      for (final cmd in args.commandArgs.values) ...cmd.options,
    };

/// Resolves the collector from an optional `--root` override, else the shared
/// tool-cache location for the current directory.
AnalyzerCacheGarbageCollector _resolveCollector(CliArgs args) {
  final root = (_options(args)['root'] as String?) ?? args.root;
  if (root != null && root.isNotEmpty) {
    return AnalyzerCacheGarbageCollector(root);
  }
  return AnalyzerCacheGarbageCollector.resolve();
}

/// Formats a byte count as a right-sized MB string.
String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';

/// A short local timestamp (`YYYY-MM-DD HH:MM`) for a partition's last-used time.
String _stamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

/// `list` — print every partition with last-used time, size and summary count.
class ListPartitionsExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    // Global command — never traversed.
    return ItemResult.failure(
      path: context.path,
      name: context.name,
      error: 'analyzer_cache_gc list is a global command',
    );
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final gc = _resolveCollector(args);
    final partitions = await gc.listPartitions();
    final currentKey = AnalyzerCacheGarbageCollector.currentPartitionKey();

    print('Analyzer summary cache: ${gc.cacheRoot}');
    print('Current toolchain partition: $currentKey');
    print('');

    if (partitions.isEmpty) {
      print('No partitions found (cache is empty or absent).');
      return const ToolResult.success();
    }

    var totalBytes = 0;
    print('  ${'PARTITION'.padRight(22)}'
        '${'SUMMARIES'.padRight(11)}'
        '${'SIZE'.padRight(12)}LAST USED');
    for (final part in partitions) {
      totalBytes += part.sizeBytes;
      final marker = part.key == currentKey ? '*' : ' ';
      final suffix = part.key == currentKey ? '  (current)' : '';
      print('$marker ${part.key.padRight(22)}'
          '${part.summaryCount.toString().padRight(11)}'
          '${_mb(part.sizeBytes).padRight(12)}'
          '${_stamp(part.lastUsed)}$suffix');
    }
    print('');
    print('Total: ${partitions.length} partition(s), ${_mb(totalBytes)}');
    return const ToolResult.success();
  }
}

/// `clean` — delete partitions older than `--older-than` days.
class CleanPartitionsExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    // Global command — never traversed.
    return ItemResult.failure(
      path: context.path,
      name: context.name,
      error: 'analyzer_cache_gc clean is a global command',
    );
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final opts = _options(args);
    final rawDays = opts['older-than'] as String? ?? '90';
    final days = int.tryParse(rawDays);
    if (days == null || days < 0) {
      print('Error: --older-than must be a non-negative integer (got '
          '"$rawDays").');
      return const ToolResult.failure('invalid --older-than value');
    }

    // `--dry-run` is a global navigation flag (captured on [CliArgs.dryRun]),
    // whereas `--include-current` is a command-scoped flag.
    final dryRun = args.dryRun;
    final includeCurrent = opts['include-current'] == true;
    final gc = _resolveCollector(args);
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: days));
    final currentKey = AnalyzerCacheGarbageCollector.currentPartitionKey();
    final keep = includeCurrent ? const <String>{} : {currentKey};

    print('Analyzer summary cache: ${gc.cacheRoot}');
    print('Cutoff: partitions last used before ${_stamp(cutoff)} '
        '(older than $days day(s))');
    print(includeCurrent
        ? 'Current partition NOT protected (--include-current): $currentKey'
        : 'Protected (current): $currentKey');
    print('');

    final removed = await gc.collect(
      cutoff: cutoff,
      keep: keep,
      dryRun: dryRun,
    );

    if (removed.isEmpty) {
      print('Nothing to reclaim — no partition is older than the cutoff.');
      return const ToolResult.success();
    }

    var reclaimed = 0;
    print(dryRun ? 'Would delete:' : 'Deleted:');
    for (final part in removed) {
      reclaimed += part.sizeBytes;
      print('  ${part.key}  (${_mb(part.sizeBytes)}, last used '
          '${_stamp(part.lastUsed)})');
    }
    print('');
    final verb = dryRun ? 'Would reclaim' : 'Reclaimed';
    print('$verb ${_mb(reclaimed)} across ${removed.length} partition(s).');
    return const ToolResult.success();
  }
}
