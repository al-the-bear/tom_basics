// BB-EXIT / BB-KILL: an item's own exit code (a mutation sweep exits with its
// surviving + invalid count), and killing a process with everything it
// started (a hung test run spawns test VMs of its own).
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

const _tool = ToolDefinition(
  name: 'exittool',
  description: 'Exit code test tool',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.projectTool,
  commands: [
    CommandDefinition(
      name: 'count',
      description: 'Fails with an exit code',
      requiresTraversal: true,
      supportsProjectTraversal: true,
      worksWithNatures: {DartProjectFolder},
    ),
  ],
);

class _CountingExecutor extends CommandExecutor {
  final int code;
  _CountingExecutor(this.code);

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.failure(
        path: context.path,
        name: context.name,
        error: '$code left',
        exitCode: code,
      );
}

ItemResult _failed(String name, [int? code]) =>
    ItemResult.failure(path: name, name: name, error: 'x', exitCode: code);

void main() {
  group('ToolResult.exitCode', () {
    test('BB-EXIT-1: a success is 0, a plain failure 1', () {
      expect(
        ToolResult.fromItems([
          const ItemResult.success(path: 'a', name: 'a'),
        ]).exitCode,
        0,
      );
      expect(ToolResult.fromItems([_failed('a')]).exitCode, 1);
      expect(const ToolResult.failure('broken').exitCode, 1);
    });

    test('BB-EXIT-2: items\' own exit codes add up', () {
      expect(
        ToolResult.fromItems([_failed('a', 3), _failed('b', 4)]).exitCode,
        7,
      );
      expect(
        ToolResult.fromItems([_failed('a', 3), _failed('b')]).exitCode,
        4,
        reason: 'a failure without its own code counts 1',
      );
    });

    test('BB-EXIT-3: capped at 125, so it never wraps round to 0', () {
      // 256 would be read as 0 (exit status is a byte); 126+ have shell
      // meanings.
      expect(
        ToolResult.fromItems([_failed('a', 200), _failed('b', 56)]).exitCode,
        125,
      );
    });

    test('BB-EXIT-4: the runner keeps an executor\'s exit code', () async {
      final root = await Directory.systemTemp.createTemp('bb_exit_');
      final previous = exitCode;
      try {
        for (final name in ['a_proj', 'b_proj']) {
          final dir = Directory('${root.path}/$name')..createSync();
          File('${dir.path}/pubspec.yaml').writeAsStringSync(
            'name: $name\nversion: 1.0.0\nenvironment:\n  sdk: ^3.0.0\n',
          );
        }
        final runner = ToolRunner(
          tool: _tool,
          verbose: false,
          output: StringBuffer(),
          executors: {'count': _CountingExecutor(3)},
        );
        final args = ['--root', root.path, '--scan', root.path, ':count'];
        final result = await runner.run(args);
        expect(result.exitCode, 6);
        expect(result.itemResults.map((i) => i.exitCode), [3, 3]);

        await runner.runToCompletion(args);
        expect(exitCode, 6);
      } finally {
        exitCode = previous;
        root.deleteSync(recursive: true);
      }
    });
  });

  test(
    'BB-KILL-1: killProcessTree stops a process and what it started',
    () async {
      final process = await Process.start('sh', [
        '-c',
        'sleep 300 & sleep 300 & wait',
      ]);
      // Give the shell time to start its children.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final children = Process.runSync('pgrep', ['-P', '${process.pid}']);
      final childPids = '${children.stdout}'.trim().split('\n');
      expect(childPids, hasLength(2));

      await killProcessTree(process.pid);

      await process.exitCode.timeout(const Duration(seconds: 5));
      for (final pid in childPids) {
        final alive = Process.runSync('kill', ['-0', pid]).exitCode == 0;
        expect(alive, isFalse, reason: 'child $pid still runs');
      }
    },
    testOn: 'mac-os || linux',
  );
}
