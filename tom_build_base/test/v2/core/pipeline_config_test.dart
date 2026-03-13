import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('PipelineCommandPrefixParser', () {
    test('BB-PLC-1: parses strict tool prefix', () {
      final parsed = PipelineCommandPrefixParser.parse(
        'buildkit :versioner --project foo',
        toolPrefix: 'buildkit',
      );

      expect(parsed, isNotNull);
      expect(parsed!.prefix, PipelineCommandPrefix.tool);
      expect(parsed.body, ':versioner --project foo');
    });

    test('BB-PLC-2: parses shell prefix', () {
      final parsed = PipelineCommandPrefixParser.parse(
        'shell pwd',
        toolPrefix: 'buildkit',
      );

      expect(parsed, isNotNull);
      expect(parsed!.prefix, PipelineCommandPrefix.shell);
      expect(parsed.body, 'pwd');
    });

    test('BB-PLC-3: parses shell-scan prefix', () {
      final parsed = PipelineCommandPrefixParser.parse(
        'shell-scan dart test',
        toolPrefix: 'buildkit',
      );

      expect(parsed, isNotNull);
      expect(parsed!.prefix, PipelineCommandPrefix.shellScan);
      expect(parsed.body, 'dart test');
    });

    test('BB-PLC-4: rejects non-strict tool alias prefix', () {
      final parsed = PipelineCommandPrefixParser.parse(
        'bk :versioner',
        toolPrefix: 'buildkit',
      );

      expect(parsed, isNull);
    });

    test('BB-PLC-10: parses print prefix', () {
      final parsed = PipelineCommandPrefixParser.parse(
        'print hello world',
        toolPrefix: 'buildkit',
      );

      expect(parsed, isNotNull);
      expect(parsed!.prefix, PipelineCommandPrefix.print);
      expect(parsed.body, 'hello world');
    });
  });

  group('ToolPipelineConfigLoader', () {
    late Directory tempRoot;
    late Directory workspace;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('bb_pipeline_cfg_');
      workspace = Directory(p.join(tempRoot.path, 'ws'))..createSync();
    });

    tearDown(() async {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('BB-PLC-5: eligibility requires multiCommand + master file', () {
      final tool = const ToolDefinition(
        name: 'buildkit',
        description: 'Build tool',
        mode: ToolMode.multiCommand,
      );

      expect(
        ToolPipelineConfigLoader.isEligible(
          tool: tool,
          fromDirectory: workspace.path,
        ),
        isFalse,
      );

      File(p.join(workspace.path, 'buildkit_master.yaml'))
        ..createSync()
        ..writeAsStringSync('required-environment:\n  pipelines: {}\n');

      expect(
        ToolPipelineConfigLoader.isEligible(
          tool: tool,
          fromDirectory: workspace.path,
        ),
        isTrue,
      );
    });

    test('BB-PLC-6: ineligible for singleCommand even with master file', () {
      final tool = const ToolDefinition(
        name: 'buildkit',
        description: 'Build tool',
        mode: ToolMode.singleCommand,
      );

      File(p.join(workspace.path, 'buildkit_master.yaml'))
        ..createSync()
        ..writeAsStringSync('required-environment:\n  pipelines: {}\n');

      expect(
        ToolPipelineConfigLoader.isEligible(
          tool: tool,
          fromDirectory: workspace.path,
        ),
        isFalse,
      );
      expect(
        ToolPipelineConfigLoader.load(
          tool: tool,
          fromDirectory: workspace.path,
        ),
        isNull,
      );
    });

    test(
      'BB-PLC-7: loads required-environment pipelines and parses prefixes',
      () {
        final tool = const ToolDefinition(
          name: 'buildkit',
          description: 'Build tool',
          mode: ToolMode.multiCommand,
          pipelineName: 'buildkit',
        );

        File(p.join(workspace.path, 'buildkit_master.yaml'))
          ..createSync()
          ..writeAsStringSync('''
required-environment:
  pipelines:
    setup:
      executable: true
      core:
        - commands:
            - print setup
            - shell-scan dart pub get
            - buildkit :versioner --project tom_build_base
''');

        final loaded = ToolPipelineConfigLoader.load(
          tool: tool,
          fromDirectory: workspace.path,
        );

        expect(loaded, isNotNull);
        expect(loaded!.pipelines.containsKey('setup'), isTrue);
        final setup = loaded.pipelines['setup']!;
        expect(setup.core, isNotEmpty);
        expect(setup.core.first.commands, hasLength(3));
        expect(
          setup.core.first.commands[0].prefix,
          PipelineCommandPrefix.print,
        );
        expect(
          setup.core.first.commands[1].prefix,
          PipelineCommandPrefix.shellScan,
        );
        expect(setup.core.first.commands[2].prefix, PipelineCommandPrefix.tool);
      },
    );

    test('BB-PLC-8: throws on unsupported prefix', () {
      final tool = const ToolDefinition(
        name: 'buildkit',
        description: 'Build tool',
        mode: ToolMode.multiCommand,
      );

      File(p.join(workspace.path, 'buildkit_master.yaml'))
        ..createSync()
        ..writeAsStringSync('''
required-environment:
  pipelines:
    setup:
      core:
        - commands:
            - bk :versioner
''');

      expect(
        () => ToolPipelineConfigLoader.load(
          tool: tool,
          fromDirectory: workspace.path,
        ),
        throwsFormatException,
      );
    });

    test('BB-PLC-9: loads pipelines from tool section layout', () {
      final tool = const ToolDefinition(
        name: 'buildkit',
        description: 'Build tool',
        mode: ToolMode.multiCommand,
      );

      File(p.join(workspace.path, 'buildkit_master.yaml'))
        ..createSync()
        ..writeAsStringSync('''
buildkit:
  pipelines:
    ci:
      executable: true
      core:
        - commands:
            - print ci
''');

      final loaded = ToolPipelineConfigLoader.load(
        tool: tool,
        fromDirectory: workspace.path,
      );

      expect(loaded, isNotNull);
      expect(loaded!.pipelines.containsKey('ci'), isTrue);
      expect(
        loaded.pipelines['ci']!.core.first.commands.first.prefix,
        PipelineCommandPrefix.print,
      );
    });
  });
}
