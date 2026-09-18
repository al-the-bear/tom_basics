import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// A tool that declares it has no dry-run mode (`NavigationFeatures.projectTool`
/// sets `dryRun: false`, as do `minimal` and `gitTool`).
const noDryRunTool = ToolDefinition(
  name: 'nodrytool',
  description: 'Tool without a dry-run mode',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.projectTool,
  commands: [
    CommandDefinition(
      name: 'write',
      description: 'Writes a file',
      requiresTraversal: false,
    ),
  ],
);

/// A tool that declares a real dry-run mode.
const dryRunTool = ToolDefinition(
  name: 'drytool',
  description: 'Tool with a dry-run mode',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.all,
  commands: [
    CommandDefinition(
      name: 'write',
      description: 'Writes a file',
      requiresTraversal: false,
    ),
  ],
);

/// Writes a real file when it runs. [honoursDryRun] models a tool that has
/// actually implemented the flag; the default models every tool that has not.
class WritingExecutor extends CommandExecutor {
  final String path;
  final bool honoursDryRun;
  bool ran = false;

  WritingExecutor(this.path, {this.honoursDryRun = false});

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.success(path: context.path, name: context.name);

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    ran = true;
    if (honoursDryRun && args.dryRun) return const ToolResult.success();
    File(path).writeAsStringSync('WRITTEN');
    return const ToolResult.success();
  }
}

void main() {
  late Directory tmp;
  late String outPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bb_dryrun_');
    outPath = '${tmp.path}/written.txt';
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('dry-run contract', () {
    for (final flag in ['-n', '--dry-run']) {
      test('BB-DRYRUN-1/$flag: a tool declaring dryRun:false refuses $flag and '
          'writes nothing [2026-09-18]', () async {
        final ex = WritingExecutor(outPath);
        final out = StringBuffer();
        final result = await ToolRunner(
          tool: noDryRunTool,
          output: out,
          executors: {'write': ex},
        ).run([flag, ':write']);

        expect(
          result.success,
          isFalse,
          reason: 'asking a tool with no dry-run mode for one must fail',
        );
        expect(ex.ran, isFalse, reason: 'no executor may run');
        expect(
          File(outPath).existsSync(),
          isFalse,
          reason: 'a refused dry run must not touch the filesystem',
        );
      });
    }

    test('BB-DRYRUN-2: the refusal names the tool and says it has no dry-run '
        'mode [2026-09-18]', () async {
      final out = StringBuffer();
      final result = await ToolRunner(
        tool: noDryRunTool,
        output: out,
        executors: {'write': WritingExecutor(outPath)},
      ).run(['-n', ':write']);

      final text = '${out.toString()}\n${result.errorMessage ?? ''}';
      expect(text, contains('nodrytool'));
      expect(text.toLowerCase(), contains('dry-run'));
    });

    test(
      'BB-DRYRUN-3: the guard does not fire for a tool that supports dry-run '
      '[2026-09-18]',
      () async {
        final ex = WritingExecutor(outPath, honoursDryRun: true);
        final result = await ToolRunner(
          tool: dryRunTool,
          executors: {'write': ex},
        ).run(['-n', ':write']);

        expect(result.success, isTrue);
        expect(ex.ran, isTrue, reason: 'the tool implements the flag itself');
        expect(
          File(outPath).existsSync(),
          isFalse,
          reason: 'the executor honoured the flag',
        );
      },
    );

    test('BB-DRYRUN-4: without the flag the same tool still runs normally '
        '[2026-09-18]', () async {
      final ex = WritingExecutor(outPath);
      final result = await ToolRunner(
        tool: noDryRunTool,
        executors: {'write': ex},
      ).run([':write']);

      expect(result.success, isTrue);
      expect(ex.ran, isTrue);
      expect(File(outPath).existsSync(), isTrue);
    });

    test('BB-DRYRUN-5: -n with --help still shows help rather than refusing '
        '[2026-09-18]', () async {
      final out = StringBuffer();
      final result = await ToolRunner(
        tool: noDryRunTool,
        output: out,
      ).run(['-n', '--help']);

      expect(result.success, isTrue);
      expect(out.toString(), contains('nodrytool'));
    });
  });

  group('help follows the feature flag', () {
    test('BB-DRYRUN-6: a tool with no dry-run mode does not advertise the flag '
        '[2026-09-18]', () async {
      final out = StringBuffer();
      await ToolRunner(tool: noDryRunTool, output: out).run(['--help']);

      expect(
        out.toString(),
        isNot(contains('--dry-run')),
        reason: 'a tool that ignores -n must not promise it',
      );
    });

    test('BB-DRYRUN-7: a tool with a dry-run mode still advertises the flag '
        '[2026-09-18]', () async {
      final out = StringBuffer();
      await ToolRunner(tool: dryRunTool, output: out).run(['--help']);

      expect(out.toString(), contains('--dry-run'));
    });

    test(
      'BB-DRYRUN-13: command-scoped help follows the flag too [2026-09-18]',
      () async {
        // Separate code path from tool-level help: `generateCommandHelp`
        // writes its own Common Options block.
        final direct = HelpGenerator.generateCommandHelp(
          noDryRunTool.commands.first,
          tool: noDryRunTool,
        );
        expect(direct, isNot(contains('--dry-run')));

        expect(
          HelpGenerator.generateCommandHelp(
            dryRunTool.commands.first,
            tool: dryRunTool,
          ),
          contains('--dry-run'),
        );

        for (final args in [
          ['--help', ':write'],
          [':write', '--help'],
        ]) {
          final out = StringBuffer();
          await ToolRunner(tool: noDryRunTool, output: out).run(args);
          expect(
            out.toString(),
            isNot(contains('--dry-run')),
            reason: 'command help for ${args.join(' ')} must not promise it',
          );
        }
      },
    );

    test('BB-DRYRUN-8: allGlobalOptions omits dry-run when the feature is off '
        '[2026-09-18]', () {
      final names = noDryRunTool.allGlobalOptions.map((o) => o.name);
      expect(names, isNot(contains('dry-run')));
      expect(
        dryRunTool.allGlobalOptions.map((o) => o.name),
        contains('dry-run'),
      );
    });
  });

  group('nested tools', () {
    test(
      'BB-DRYRUN-9: --dry-run is not forwarded to a nested tool that does not '
      'support it [2026-09-18]',
      () {
        final args = NestedToolExecutor.buildNestedArgs(
          hostArgs: const CliArgs(dryRun: true),
          hostCommandName: 'gen',
          nestedCommand: 'gen',
          isStandalone: true,
          nestedSupportsDryRun: false,
        );

        expect(
          args,
          isNot(contains('--dry-run')),
          reason: 'forwarding it makes the nested tool write for real',
        );
      },
    );

    test(
      'BB-DRYRUN-10: --dry-run is forwarded to a nested tool that supports it '
      '[2026-09-18]',
      () {
        final args = NestedToolExecutor.buildNestedArgs(
          hostArgs: const CliArgs(dryRun: true),
          hostCommandName: 'gen',
          nestedCommand: 'gen',
          isStandalone: true,
          nestedSupportsDryRun: true,
        );

        expect(args, contains('--dry-run'));
      },
    );

    test('BB-DRYRUN-11: a host dry run reports a non-supporting nested tool '
        'instead of running it [2026-09-18]', () async {
      // The binary does not exist, so a success here can only mean the
      // spawn was skipped -- if the executor tried to run it, it would fail.
      const missingBinary = 'definitely-not-a-real-binary-sce27';
      final executor = NestedToolExecutor(
        binary: missingBinary,
        hostCommandName: 'gen',
        isStandalone: true,
        supportsDryRun: false,
      );

      final result = await executor.execute(
        CommandContext(
          fsFolder: FsFolder(path: tmp.path),
          natures: const [],
          executionRoot: tmp.path,
        ),
        const CliArgs(dryRun: true),
      );

      expect(
        result.success,
        isTrue,
        reason: 'skipping an unsupported step is not a failure',
      );
      expect(result.message, contains('[DRY RUN]'));
      expect(result.message, contains(missingBinary));
    });

    test('BB-DRYRUN-12: a nested tool that supports dry-run is still run '
        '[2026-09-18]', () async {
      const missingBinary = 'definitely-not-a-real-binary-sce27';
      final executor = NestedToolExecutor(
        binary: missingBinary,
        hostCommandName: 'gen',
        isStandalone: true,
        supportsDryRun: true,
      );

      Object? error;
      try {
        await executor.execute(
          CommandContext(
            fsFolder: FsFolder(path: tmp.path),
            natures: const [],
            executionRoot: tmp.path,
          ),
          const CliArgs(dryRun: true),
        );
      } catch (e) {
        error = e;
      }

      expect(
        error,
        isA<ProcessException>(),
        reason: 'it was spawned rather than skipped',
      );
      expect(
        (error as ProcessException).toString(),
        contains('--dry-run'),
        reason: 'and the flag was forwarded, because it can honour it',
      );
    });
  });
}
