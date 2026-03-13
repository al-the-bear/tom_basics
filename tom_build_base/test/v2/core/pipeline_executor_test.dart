import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('PipelineOptionResolver', () {
    test('BB-PLX-1: command options override invocation and pipeline', () {
      final resolved = PipelineOptionResolver.resolveEffectiveOptions(
        pipelineOptions: const {'scan': '.', 'verbose': 'false'},
        invocationOptions: const {'verbose': 'true', 'root': '/tmp/ws'},
        commandOptions: const {'verbose': 'false', 'project': 'tom_build_base'},
      );

      expect(resolved['scan'], '.');
      expect(resolved['root'], '/tmp/ws');
      expect(resolved['project'], 'tom_build_base');
      expect(resolved['verbose'], 'false');
    });

    test('BB-PLX-2: disqualifying traversal options are detected', () {
      const args = CliArgs(root: '/tmp/ws', projectPatterns: ['tom_*']);
      expect(
        PipelineOptionResolver.hasDisqualifyingTraversalOptions(args),
        isTrue,
      );
    });

    test('BB-PLX-3: verbose and dry-run alone are not disqualifying', () {
      const args = CliArgs(verbose: true, dryRun: true);
      expect(
        PipelineOptionResolver.hasDisqualifyingTraversalOptions(args),
        isFalse,
      );
    });

    test(
      'BB-PLX-3b: pipeline-only invocation delegates by default [2026-03-11]',
      () {
        const args = CliArgs();
        expect(
          PipelineOptionResolver.shouldDelegateToNestedWorkspaces(
            args,
            pipelineOnlyInvocation: true,
          ),
          isTrue,
        );
      },
    );

    test(
      'BB-PLX-3c: mixed invocation requires workspace-recursion [2026-03-11]',
      () {
        const mixedArgs = CliArgs(commands: ['pubget']);
        expect(
          PipelineOptionResolver.shouldDelegateToNestedWorkspaces(
            mixedArgs,
            pipelineOnlyInvocation: false,
          ),
          isFalse,
        );

        const mixedRecursiveArgs = CliArgs(
          commands: ['pubget'],
          workspaceRecursion: true,
        );
        expect(
          PipelineOptionResolver.shouldDelegateToNestedWorkspaces(
            mixedRecursiveArgs,
            pipelineOnlyInvocation: false,
          ),
          isTrue,
        );
      },
    );

    test(
      'BB-PLX-4: delegated tool argv honors precedence and command tokens',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp('bb_plx_argv_');
        final workspace = Directory('${tempRoot.path}/ws')..createSync();
        final master = File('${workspace.path}/testtool_master.yaml')
          ..createSync()
          ..writeAsStringSync('required-environment:\n  pipelines: {}\n');

        final tool = ToolDefinition(
          name: 'testtool',
          description: 'Test tool',
          version: '1.0.0',
          mode: ToolMode.multiCommand,
        );
        final config = ToolPipelineConfig(
          sourcePath: master.path,
          pipelines: {
            'ci': PipelineDefinition(
              executable: true,
              globalOptions: const {
                'scan': '.',
                'project': 'pipeline-proj',
                'verbose': 'false',
              },
              core: const [
                PipelineStepConfig(
                  commands: [
                    PipelineCommandSpec(
                      raw:
                          'testtool --project=cmd-proj --root=/cmd-root :simple',
                      prefix: PipelineCommandPrefix.tool,
                      body: '--project=cmd-proj --root=/cmd-root :simple',
                    ),
                  ],
                ),
              ],
            ),
          },
        );

        final output = StringBuffer();
        final executor = ToolPipelineExecutor(tool: tool, output: output);
        const args = CliArgs(
          dryRun: true,
          verbose: true,
          root: '/inv-root',
          scan: 'inv-scan',
        );

        final ok = await executor.executeInvocation(
          pipelineName: 'ci',
          config: config,
          cliArgs: args,
        );

        expect(ok, isTrue);
        final out = output.toString();
        expect(
          out,
          contains(
            '[PIPELINE:testtool] testtool --dry-run --scan=inv-scan --verbose '
            '--project=cmd-proj --root=/cmd-root :simple',
          ),
        );

        if (tempRoot.existsSync()) {
          await tempRoot.delete(recursive: true);
        }
      },
    );

    test('BB-PLX-5: print command outputs message once', () async {
      final tempRoot = await Directory.systemTemp.createTemp('bb_plx_print_');
      final workspace = Directory('${tempRoot.path}/ws')..createSync();
      final master = File('${workspace.path}/testtool_master.yaml')
        ..createSync()
        ..writeAsStringSync('required-environment:\n  pipelines: {}\n');

      final tool = ToolDefinition(
        name: 'testtool',
        description: 'Test tool',
        version: '1.0.0',
        mode: ToolMode.multiCommand,
      );

      final config = ToolPipelineConfig(
        sourcePath: master.path,
        pipelines: {
          'notify': PipelineDefinition(
            executable: true,
            core: const [
              PipelineStepConfig(
                commands: [
                  PipelineCommandSpec(
                    raw: 'print hello once',
                    prefix: PipelineCommandPrefix.print,
                    body: 'hello once',
                  ),
                ],
              ),
            ],
          ),
        },
      );

      final output = StringBuffer();
      final executor = ToolPipelineExecutor(tool: tool, output: output);

      final ok = await executor.executeInvocation(
        pipelineName: 'notify',
        config: config,
        cliArgs: const CliArgs(verbose: true),
      );

      expect(ok, isTrue);
      final out = output.toString();
      expect('hello once'.allMatches(out).length, equals(1));

      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });
  });
}
