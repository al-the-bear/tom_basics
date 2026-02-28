import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../execute_placeholder.dart';
import '../folder/fs_folder.dart';
import '../traversal/build_base.dart';
import '../traversal/command_context.dart';
import 'binary_helpers.dart';
import 'cli_arg_parser.dart';
import 'pipeline_config.dart';
import 'tool_definition.dart';

class PipelineOptionResolver {
  static Map<String, String> resolveEffectiveOptions({
    required Map<String, String> pipelineOptions,
    required Map<String, String> invocationOptions,
    required Map<String, String> commandOptions,
  }) {
    return <String, String>{
      ...pipelineOptions,
      ...invocationOptions,
      ...commandOptions,
    };
  }

  static bool hasDisqualifyingTraversalOptions(CliArgs cliArgs) {
    if (cliArgs.root != null) return true;
    if (cliArgs.projectPatterns.isNotEmpty) return true;
    if (cliArgs.excludePatterns.isNotEmpty) return true;
    if (cliArgs.excludeProjects.isNotEmpty) return true;
    return false;
  }
}

class ToolPipelineExecutor {
  final ToolDefinition tool;
  final StringSink output;
  final bool verbose;

  final Set<String> _visitedPipelines = <String>{};
  final List<String> _stack = <String>[];

  ToolPipelineExecutor({
    required this.tool,
    required this.output,
    this.verbose = false,
  });

  Future<bool> executeInvocation({
    required String pipelineName,
    required ToolPipelineConfig config,
    required CliArgs cliArgs,
  }) async {
    final workspaceRoot = p.dirname(config.sourcePath);

    final success = await _executePipelineInWorkspace(
      pipelineName: pipelineName,
      config: config,
      workspaceDir: workspaceRoot,
      cliArgs: cliArgs,
    );
    if (!success) return false;

    final nestedWorkspaces = _discoverNestedWorkspaces(
      rootDir: workspaceRoot,
      masterFileName: '${tool.name}_master.yaml',
    );
    if (nestedWorkspaces.isEmpty) return true;

    final disqualified =
        PipelineOptionResolver.hasDisqualifyingTraversalOptions(cliArgs);
    for (final wsDir in nestedWorkspaces) {
      if (disqualified) {
        output.writeln(
          'Skipped workspace: ${p.basename(wsDir)}, global traversal option specified.',
        );
        continue;
      }

      final delegatedArgs = <String>[
        if (cliArgs.verbose) '--verbose',
        if (cliArgs.dryRun) '--dry-run',
        pipelineName,
      ];

      if (cliArgs.dryRun || verbose) {
        output.writeln(
          '[PIPELINE] Delegate workspace ${p.basename(wsDir)}: '
          '${tool.name} ${delegatedArgs.join(' ')}',
        );
      }

      if (cliArgs.dryRun) continue;

      final result = await runBinary(tool.name, delegatedArgs, wsDir);
      if (result.stdout.toString().trim().isNotEmpty) {
        output.writeln(result.stdout.toString().trimRight());
      }
      if (result.stderr.toString().trim().isNotEmpty) {
        output.writeln(result.stderr.toString().trimRight());
      }
      if (result.exitCode != 0) {
        output.writeln(
          'Pipeline delegation failed in ${p.basename(wsDir)} '
          '(exit code ${result.exitCode}).',
        );
        return false;
      }
    }

    return true;
  }

  Future<bool> _executePipelineInWorkspace({
    required String pipelineName,
    required ToolPipelineConfig config,
    required String workspaceDir,
    required CliArgs cliArgs,
  }) async {
    final definition = config.pipelines[pipelineName];
    if (definition == null) {
      output.writeln('Unknown pipeline: $pipelineName');
      return false;
    }
    if (_stack.isEmpty && !definition.executable) {
      output.writeln('Pipeline "$pipelineName" is not executable.');
      return false;
    }

    if (_visitedPipelines.contains(pipelineName)) return true;
    if (_stack.contains(pipelineName)) {
      output.writeln(
        'Circular pipeline dependency: ${_stack.join(' -> ')} -> $pipelineName',
      );
      return false;
    }

    _stack.add(pipelineName);
    try {
      for (final before in definition.runBefore) {
        final ok = await _executePipelineInWorkspace(
          pipelineName: before,
          config: config,
          workspaceDir: workspaceDir,
          cliArgs: cliArgs,
        );
        if (!ok) return false;
      }

      final invocationOptions = _invocationOptions(cliArgs);

      final sections = <List<PipelineStepConfig>>[
        definition.precore,
        definition.core,
        definition.postcore,
      ];

      for (final steps in sections) {
        for (final step in steps) {
          for (final command in step.commands) {
            final ok = await _executeCommand(
              command: command,
              workspaceDir: workspaceDir,
              cliArgs: cliArgs,
              pipelineOptions: definition.globalOptions,
              invocationOptions: invocationOptions,
            );
            if (!ok) return false; // fail-fast
          }
        }
      }

      for (final after in definition.runAfter) {
        final ok = await _executePipelineInWorkspace(
          pipelineName: after,
          config: config,
          workspaceDir: workspaceDir,
          cliArgs: cliArgs,
        );
        if (!ok) return false;
      }

      _visitedPipelines.add(pipelineName);
      return true;
    } finally {
      _stack.removeLast();
    }
  }

  Future<bool> _executeCommand({
    required PipelineCommandSpec command,
    required String workspaceDir,
    required CliArgs cliArgs,
    required Map<String, String> pipelineOptions,
    required Map<String, String> invocationOptions,
  }) async {
    switch (command.prefix) {
      case PipelineCommandPrefix.shell:
        return _runShell(command.body, workspaceDir, cliArgs.dryRun);
      case PipelineCommandPrefix.shellScan:
        return _runShellScan(command.body, workspaceDir, cliArgs);
      case PipelineCommandPrefix.stdin:
        return _runStdin(command.body, workspaceDir, cliArgs.dryRun);
      case PipelineCommandPrefix.tool:
        return _runToolCommand(
          command.body,
          workspaceDir,
          cliArgs,
          pipelineOptions,
          invocationOptions,
        );
    }
  }

  Future<bool> _runShell(String body, String workspaceDir, bool dryRun) async {
    final command = body.trim();
    if (command.isEmpty) {
      output.writeln('Invalid empty shell command.');
      return false;
    }

    if (dryRun || verbose) {
      output.writeln('[PIPELINE:shell] $command');
    }
    if (dryRun) return true;

    final result = await _runShellProcess(command, workspaceDir);
    if (result.stdout.toString().trim().isNotEmpty) {
      output.writeln(result.stdout.toString().trimRight());
    }
    if (result.stderr.toString().trim().isNotEmpty) {
      output.writeln(result.stderr.toString().trimRight());
    }
    return result.exitCode == 0;
  }

  Future<bool> _runStdin(String body, String workspaceDir, bool dryRun) async {
    // body format: first line is the shell command, remaining lines are stdin
    // content that will be piped to that command.
    final newlineIdx = body.indexOf('\n');
    final command = (newlineIdx == -1 ? body : body.substring(0, newlineIdx))
        .trim();
    final stdinContent =
        newlineIdx == -1 ? '' : body.substring(newlineIdx + 1);

    if (command.isEmpty) {
      output.writeln('Invalid empty stdin command.');
      return false;
    }

    if (dryRun || verbose) {
      output.writeln('[PIPELINE:stdin] $command');
      if (stdinContent.isNotEmpty) {
        for (final line in stdinContent.split('\n')) {
          output.writeln('  | $line');
        }
      }
    }
    if (dryRun) return true;

    final String executable;
    final List<String> args;
    if (Platform.isWindows) {
      executable = 'cmd';
      args = ['/c', command];
    } else {
      executable = '/bin/bash';
      args = ['-lc', command];
    }

    final process = await Process.start(
      executable,
      args,
      workingDirectory: workspaceDir,
    );
    if (stdinContent.isNotEmpty) {
      process.stdin.write(stdinContent);
    }
    await process.stdin.close();

    final stdoutFuture =
        process.stdout.transform(utf8.decoder).join();
    final stderrFuture =
        process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;
    final out = await stdoutFuture;
    final err = await stderrFuture;

    if (out.trimRight().isNotEmpty) {
      output.writeln(out.trimRight());
    }
    if (err.trimRight().isNotEmpty) {
      output.writeln(err.trimRight());
    }
    return exitCode == 0;
  }

  Future<bool> _runShellScan(
    String body,
    String workspaceDir,
    CliArgs cliArgs,
  ) async {
    final command = body.trim();
    if (command.isEmpty) {
      output.writeln('Invalid empty shell-scan command.');
      return false;
    }

    final traversal = cliArgs.toProjectTraversalInfo(
      executionRoot: workspaceDir,
    );

    final result = await BuildBase.traverse(
      info: traversal,
      requiredNatures: const {FsFolder},
      run: (CommandContext context) async {
        final placeholderCtx = ExecutePlaceholderContext.fromCommandContext(
          context,
          workspaceDir,
        );
        final resolved = ExecutePlaceholderResolver.resolveCommand(
          command,
          placeholderCtx,
          skipUnknown: true,
        );

        if (cliArgs.dryRun || verbose) {
          output.writeln(
            '[PIPELINE:shell-scan] ${context.relativePath}: $resolved',
          );
        }
        if (cliArgs.dryRun) return true;

        final proc = await _runShellProcess(resolved, context.path);
        if (proc.stdout.toString().trim().isNotEmpty) {
          output.writeln(proc.stdout.toString().trimRight());
        }
        if (proc.stderr.toString().trim().isNotEmpty) {
          output.writeln(proc.stderr.toString().trimRight());
        }
        return proc.exitCode == 0;
      },
      verbose: verbose,
    );

    return result.allSucceeded;
  }

  Future<bool> _runToolCommand(
    String body,
    String workspaceDir,
    CliArgs cliArgs,
    Map<String, String> pipelineOptions,
    Map<String, String> invocationOptions,
  ) async {
    final tokens = _tokenize(body);
    if (tokens.isEmpty) {
      output.writeln('Invalid empty tool-prefixed pipeline command.');
      return false;
    }

    final commandLevelOptions = _extractLongOptions(tokens);
    final mergedOptions = PipelineOptionResolver.resolveEffectiveOptions(
      pipelineOptions: pipelineOptions,
      invocationOptions: invocationOptions,
      commandOptions: commandLevelOptions,
    );

    final prepended = _optionsToArgs(mergedOptions, existingTokens: tokens);
    final argv = <String>[...prepended, ...tokens];

    if (cliArgs.dryRun || verbose) {
      output.writeln(
        '[PIPELINE:${tool.pipelineName}] ${tool.name} ${argv.join(' ')}',
      );
    }
    if (cliArgs.dryRun) return true;

    final result = await runBinary(tool.name, argv, workspaceDir);
    if (result.stdout.toString().trim().isNotEmpty) {
      output.writeln(result.stdout.toString().trimRight());
    }
    if (result.stderr.toString().trim().isNotEmpty) {
      output.writeln(result.stderr.toString().trimRight());
    }
    return result.exitCode == 0;
  }

  Map<String, String> _invocationOptions(CliArgs cliArgs) {
    final map = <String, String>{
      if (cliArgs.verbose) 'verbose': 'true',
      if (cliArgs.dryRun) 'dry-run': 'true',
      if (cliArgs.root != null) 'root': cliArgs.root!,
      if (cliArgs.scan != null) 'scan': cliArgs.scan!,
      if (cliArgs.recursive) 'recursive': 'true',
      if (cliArgs.notRecursive) 'not-recursive': 'true',
    };
    return map;
  }

  List<String> _optionsToArgs(
    Map<String, String> options, {
    required List<String> existingTokens,
  }) {
    final existingKeys = existingTokens
        .where((t) => t.startsWith('--'))
        .map((t) => t.substring(2).split('=').first)
        .toSet();

    final keys = options.keys.toList()..sort();
    final args = <String>[];
    for (final key in keys) {
      if (existingKeys.contains(key)) continue;
      final value = options[key] ?? 'true';
      if (value == 'true') {
        args.add('--$key');
      } else {
        args.add('--$key=$value');
      }
    }
    return args;
  }

  Map<String, String> _extractLongOptions(List<String> tokens) {
    final options = <String, String>{};
    for (var index = 0; index < tokens.length; index++) {
      final token = tokens[index];
      if (!token.startsWith('--')) continue;
      final withoutPrefix = token.substring(2);
      if (withoutPrefix.contains('=')) {
        final parts = withoutPrefix.split('=');
        options[parts.first] = parts.skip(1).join('=');
      } else {
        final next = index + 1 < tokens.length ? tokens[index + 1] : null;
        if (next != null && !next.startsWith('-')) {
          options[withoutPrefix] = next;
        } else {
          options[withoutPrefix] = 'true';
        }
      }
    }
    return options;
  }

  List<String> _tokenize(String input) {
    final matches = RegExp(r'''("[^"]*"|'[^']*'|\S+)''').allMatches(input);
    return matches.map((m) => m.group(0)!).map((s) {
      if ((s.startsWith('"') && s.endsWith('"')) ||
          (s.startsWith("'") && s.endsWith("'"))) {
        return s.substring(1, s.length - 1);
      }
      return s;
    }).toList();
  }

  Future<ProcessResult> _runShellProcess(String command, String dir) {
    if (Platform.isWindows) {
      return Process.run('cmd', ['/c', command], workingDirectory: dir);
    }
    return Process.run('/bin/bash', ['-lc', command], workingDirectory: dir);
  }

  List<String> _discoverNestedWorkspaces({
    required String rootDir,
    required String masterFileName,
  }) {
    final result = <String>[];
    final root = Directory(rootDir);
    if (!root.existsSync()) return result;

    void walk(Directory dir) {
      try {
        for (final entity in dir.listSync(followLinks: false)) {
          if (entity is! Directory) continue;
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue;

          final master = File(p.join(entity.path, masterFileName));
          if (master.existsSync()) {
            result.add(entity.path);
            continue;
          }
          walk(entity);
        }
      } catch (_) {}
    }

    walk(root);
    return result;
  }
}
