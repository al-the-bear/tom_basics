/// Native v2 executor for the compiler command.
///
/// Cross-platform Dart compilation with pre/post-compile command sequences,
/// placeholder resolution, platform filtering, and multi-target compilation.
///
/// Reuses existing utility files for config parsing, platform detection,
/// and built-in command dispatch.
library;

import 'dart:io';

import 'package:dcli/dcli.dart' as dcli;
import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart'
    show findWorkspaceRoot, ProcessRunner;
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:yaml/yaml.dart';

import '../../compiler_config.dart';
import '../../platform_utils.dart';
import '../../script_utils.dart' as script_utils;

// =============================================================================
// CompilerConfig (v2 version)
// =============================================================================

/// Configuration for the compiler tool, merging workspace + project configs.
class _CompilerConfig {
  final List<String> targetFilter;
  final List<String> executableFilter;
  final List<CommandSection> precompileSections;
  final List<CompileSection> compileSections;
  final List<CommandSection> postcompileSections;

  const _CompilerConfig({
    this.targetFilter = const [],
    this.executableFilter = const [],
    this.precompileSections = const [],
    this.compileSections = const [],
    this.postcompileSections = const [],
  });

  /// Load compile sections from buildkit.yaml compiler section.
  static _CompilerConfig? loadFromYaml(String dir) {
    final file = File('$dir/buildkit.yaml');
    if (!file.existsSync()) return null;

    try {
      final content = file.readAsStringSync();
      final yaml = loadYaml(content) as YamlMap?;
      if (yaml == null) return null;

      final compilerYaml = yaml['compiler'] as YamlMap?;
      if (compilerYaml == null) return null;

      final precompile = <CommandSection>[];
      final preRaw = compilerYaml['precompile'];
      if (preRaw is List) {
        for (final item in preRaw) {
          precompile.add(CommandSection.fromJson(item));
        }
      }

      final compiles = <CompileSection>[];
      final compilesRaw = compilerYaml['compiles'];
      if (compilesRaw is List) {
        for (final item in compilesRaw) {
          compiles.add(CompileSection.fromJson(item));
        }
      }

      final postcompile = <CommandSection>[];
      final postRaw = compilerYaml['postcompile'];
      if (postRaw is List) {
        for (final item in postRaw) {
          postcompile.add(CommandSection.fromJson(item));
        }
      }

      return _CompilerConfig(
        precompileSections: precompile,
        compileSections: compiles,
        postcompileSections: postcompile,
      );
    } catch (_) {
      return null;
    }
  }

  _CompilerConfig merge(_CompilerConfig other) {
    return _CompilerConfig(
      targetFilter: other.targetFilter.isNotEmpty
          ? other.targetFilter
          : targetFilter,
      executableFilter: other.executableFilter.isNotEmpty
          ? other.executableFilter
          : executableFilter,
      precompileSections: other.precompileSections.isNotEmpty
          ? other.precompileSections
          : precompileSections,
      compileSections: other.compileSections.isNotEmpty
          ? other.compileSections
          : compileSections,
      postcompileSections: other.postcompileSections.isNotEmpty
          ? other.postcompileSections
          : postcompileSections,
    );
  }
}

// =============================================================================
// Executor
// =============================================================================

/// Native v2 executor for the `:compiler` command.
class CompilerExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final projectPath = context.path;

    // Check if project has compiler config
    if (!_hasCompilerConfig(projectPath)) {
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'skipped (no compiler config)',
      );
    }

    // List mode: just print project path
    if (args.listOnly) {
      print('  ${p.relative(projectPath, from: context.executionRoot)}');
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'listed',
      );
    }

    // Dump config mode: show compiler configuration
    if (args.dumpConfig) {
      final config = _CompilerConfig.loadFromYaml(projectPath);
      print('  ${context.name}:');
      if (config != null) {
        if (config.compileSections.isNotEmpty) {
          print('    compiles: ${config.compileSections.length} sections');
          for (final section in config.compileSections) {
            final desc = section.files.isNotEmpty
                ? section.files.join(', ')
                : section.pipelineCommands.join(', ');
            final tgt = section.targets.isNotEmpty
                ? ' → ${section.targets.join(', ')}'
                : '';
            print('      - $desc$tgt');
          }
        }
        if (config.precompileSections.isNotEmpty) {
          print('    precompile: ${config.precompileSections.length} sections');
        }
        if (config.postcompileSections.isNotEmpty) {
          print(
            '    postcompile: ${config.postcompileSections.length} sections',
          );
        }
      } else {
        print('    compiler: (no config)');
      }
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'config shown',
      );
    }

    // Honour an explicit opt-out: a project can set
    //   compiler:
    //     skip-compile-with-buildkit: true
    // in its buildkit.yaml to avoid being compiled by a running buildkit. This
    // resolves the Windows self-overwrite file lock (buildkit/tom_bs cannot
    // overwrite their own in-use .exe) — such a project is built by a bootstrap
    // step instead. A configured skip is a SUCCESS, never a failure, so the
    // self-lock case no longer counts against the run's exit code. See
    // tool_run_analysis §b.5 / §b.7.
    if (_skipsCompileWithBuildkit(projectPath)) {
      print('  ${context.name}: $compileSkippedMessage');
      return ItemResult.skipped(
        path: projectPath,
        name: context.name,
        message: compileSkippedMessage,
      );
    }

    final cmdOpts = _getCmdOpts(args);
    final compileAllPlatforms = cmdOpts['all-platforms'] == true;

    // Parse target filter from CLI
    final targetFilter = <String>[];
    final targetsArg = cmdOpts['targets'];
    if (targetsArg is String) {
      targetFilter.addAll(targetsArg.split(',').map((s) => s.trim()));
    } else if (targetsArg is List) {
      for (final t in targetsArg) {
        targetFilter.addAll(t.toString().split(',').map((s) => s.trim()));
      }
    }

    // Parse executable filter from CLI
    final executableFilter = <String>[];
    final executableArg = cmdOpts['executable'];
    if (executableArg is String) {
      executableFilter.addAll(executableArg.split(',').map((s) => s.trim()));
    } else if (executableArg is List) {
      for (final e in executableArg) {
        executableFilter.addAll(e.toString().split(',').map((s) => s.trim()));
      }
    }

    // Load workspace config then merge project config
    var config =
        _CompilerConfig.loadFromYaml(context.executionRoot) ??
        const _CompilerConfig();
    final projectConfig = _CompilerConfig.loadFromYaml(projectPath);
    if (projectConfig != null) {
      config = config.merge(projectConfig);
    }
    if (targetFilter.isNotEmpty) {
      config = config.merge(_CompilerConfig(targetFilter: targetFilter));
    }
    if (executableFilter.isNotEmpty) {
      config = config.merge(
        _CompilerConfig(executableFilter: executableFilter),
      );
    }

    if (config.compileSections.isEmpty) {
      if (args.verbose) print('  No compile sections configured');
      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'no compile sections',
      );
    }

    final currentPlatform = PlatformUtils.getCurrentPlatform();
    if (args.verbose) print('  Current platform: $currentPlatform');

    // Create placeholder context for general placeholder resolution
    // (folder, nature, path placeholders from ExecutePlaceholderResolver).
    final placeholderCtx = ExecutePlaceholderContext.fromCommandContext(
      context,
      findWorkspaceRoot(projectPath),
    );

    final savedDir = Directory.current.path;
    Directory.current = projectPath;

    try {
      var compilationCount = 0;
      // Human-readable descriptions of every phase/file that failed. A
      // non-empty list at the end means the project did not build cleanly and
      // must be reported as a failure (non-zero exit) — see tool_run_analysis
      // §b.5. Phases continue after a failure so the operator sees every
      // problem in one run rather than only the first.
      final failures = <String>[];

      // Precompile
      for (final section in config.precompileSections) {
        final ok = await _runCommandSection(
          section: section,
          currentPlatform: currentPlatform,
          projectPath: projectPath,
          sectionName: 'precompile',
          args: args,
          placeholderCtx: placeholderCtx,
        );
        if (!ok) failures.add('precompile');
      }

      // Compile
      for (final section in config.compileSections) {
        if (section.platforms.isNotEmpty) {
          final matches = section.platforms.any(
            (pl) => PlatformUtils.matchesPlatform(pl, currentPlatform),
          );
          if (!matches) {
            if (args.verbose) {
              print(
                '  Skipping compile section (platform: '
                '${section.platforms.join(', ')})',
              );
            }
            continue;
          }
        }

        final allowedTargets = section.targets.isNotEmpty
            ? _expandTargets(section.targets)
            : [currentPlatform];

        List<String> targets;
        if (config.targetFilter.isNotEmpty) {
          targets = allowedTargets.where((t) {
            return config.targetFilter.any(
              (f) => PlatformUtils.matchesPlatform(f, t),
            );
          }).toList();
          if (targets.isEmpty) {
            if (args.verbose) print('  No targets match filter');
            continue;
          }
        } else if (compileAllPlatforms) {
          targets = allowedTargets;
          if (targets.isEmpty) {
            if (args.verbose) print('  No allowed targets for this section');
            continue;
          }
        } else {
          if (allowedTargets.any(
            (t) => PlatformUtils.matchesPlatform(currentPlatform, t),
          )) {
            targets = [currentPlatform];
          } else {
            if (args.verbose) {
              print(
                '  Skipping compile section: current platform '
                '$currentPlatform not in allowed targets '
                '(${allowedTargets.join(', ')})',
              );
            }
            continue;
          }
        }

        // Get files to compile, applying executable filter
        var files = section.files.toList();
        if (config.executableFilter.isNotEmpty) {
          files = files.where((f) {
            final fileName = p.basename(f);
            return config.executableFilter.any(
              (filter) => fileName == filter || f.endsWith(filter),
            );
          }).toList();
          if (files.isEmpty) {
            if (args.verbose) print('  No files match executable filter');
            continue;
          }
        }

        for (final file in files) {
          for (final target in targets) {
            final success = await _compileFile(
              file: file,
              targetPlatform: target,
              currentPlatform: currentPlatform,
              commandTemplates: section.pipelineCommands,
              args: args,
            );
            if (success) {
              compilationCount++;
            } else {
              failures.add('$file ($target)');
            }
          }
        }
      }

      // Postcompile
      for (final section in config.postcompileSections) {
        final ok = await _runCommandSection(
          section: section,
          currentPlatform: currentPlatform,
          projectPath: projectPath,
          sectionName: 'postcompile',
          args: args,
          placeholderCtx: placeholderCtx,
        );
        if (!ok) failures.add('postcompile');
      }

      if (compilationCount > 0 && args.verbose) {
        print('  Completed $compilationCount compilation(s)');
      }

      // A failed phase/file must surface as a per-item failure so the runner
      // aggregates it into a non-zero exit code and names this project.
      if (failures.isNotEmpty) {
        return ItemResult.failure(
          path: projectPath,
          name: context.name,
          error: 'compilation failed: ${failures.join(', ')}',
        );
      }

      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: '$compilationCount compilations',
      );
    } catch (e) {
      return ItemResult.failure(
        path: projectPath,
        name: context.name,
        error: 'Compilation failed: $e',
      );
    } finally {
      Directory.current = savedDir;
    }
  }

  bool _hasCompilerConfig(String dir) {
    final file = File('$dir/buildkit.yaml');
    if (!file.existsSync()) return false;
    try {
      final yaml = loadYaml(file.readAsStringSync()) as YamlMap?;
      return yaml != null && yaml['compiler'] is YamlMap;
    } catch (_) {
      return false;
    }
  }

  /// Status message reported when a project opts out of buildkit-driven
  /// compilation via `compiler: { skip-compile-with-buildkit: true }`.
  ///
  /// The end-of-run summary renders it as
  /// `<project>: compile skipped as configured in buildkit.yaml`.
  /// See [skipCompileWithBuildkit] and tool_run_analysis §b.5 / §b.7.
  static const String compileSkippedMessage =
      'compile skipped as configured in buildkit.yaml';

  /// Whether [buildkitYamlContent] sets `compiler.skip-compile-with-buildkit:
  /// true`, opting the project out of being compiled by a running buildkit.
  ///
  /// Pure parser (no filesystem) so it is unit-testable. Only an actual YAML
  /// boolean `true` opts out; a missing key, a non-map `compiler` section, a
  /// non-boolean value, or malformed YAML all yield `false` (compile as usual).
  static bool skipCompileWithBuildkit(String buildkitYamlContent) {
    try {
      final yaml = loadYaml(buildkitYamlContent) as YamlMap?;
      final compiler = yaml?['compiler'];
      if (compiler is YamlMap) {
        return compiler['skip-compile-with-buildkit'] == true;
      }
    } catch (_) {
      // Fall through to false on any parse error.
    }
    return false;
  }

  /// Read `[dir]/buildkit.yaml` and report whether it opts out of
  /// buildkit-driven compilation. Missing or unreadable file → not skipped.
  bool _skipsCompileWithBuildkit(String dir) {
    final file = File('$dir/buildkit.yaml');
    if (!file.existsSync()) return false;
    try {
      return skipCompileWithBuildkit(file.readAsStringSync());
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _getCmdOpts(CliArgs args) {
    for (final cmd in args.commands) {
      if (cmd == 'compiler' || cmd == 'c' || cmd == 'comp') {
        final cmdArgs = args.commandArgs[cmd];
        if (cmdArgs != null) return cmdArgs.options;
      }
    }
    return args.extraOptions;
  }

  Future<bool> _runCommandSection({
    required CommandSection section,
    required String currentPlatform,
    required String projectPath,
    required String sectionName,
    required CliArgs args,
    required ExecutePlaceholderContext placeholderCtx,
  }) async {
    if (section.platforms.isNotEmpty) {
      final matches = section.platforms.any(
        (pl) => PlatformUtils.matchesPlatform(pl, currentPlatform),
      );
      if (!matches) {
        if (args.verbose) {
          print(
            '  Skipping $sectionName (platform: '
            '${section.platforms.join(', ')})',
          );
        }
        return true;
      }
    }

    for (final commandTemplate in section.pipelineCommands) {
      // Resolve general placeholders (folder, nature, path, etc.)
      // before compiler-specific platform replacements.
      var command = ExecutePlaceholderResolver.resolveCommand(
        commandTemplate,
        placeholderCtx,
        skipUnknown: true,
      );
      command = command
          .replaceAll(
            r'%{current-os}',
            PlatformUtils.getTargetOS(currentPlatform),
          )
          .replaceAll(
            r'%{current-arch}',
            PlatformUtils.getTargetArch(currentPlatform),
          )
          .replaceAll(
            r'%{current-platform}',
            PlatformUtils.vsCodeToDartTarget(currentPlatform),
          )
          .replaceAll(r'%{current-platform-vs}', currentPlatform);
      _warnMisusedPlaceholders(command, sectionName);
      final success = await _executePipelineCommand(
        rawCommand: _replaceEnvVars(command),
        args: args,
        phaseLabel: sectionName,
      );
      if (!success) {
        print('  Error: $sectionName command failed: $command');
        return false;
      }
    }
    return true;
  }

  Future<bool> _compileFile({
    required String file,
    required String targetPlatform,
    required String currentPlatform,
    required List<String> commandTemplates,
    required CliArgs args,
  }) async {
    final normalizedFilePath = p.normalize(file);
    final filePath = Platform.isWindows
        ? normalizedFilePath.replaceAll('\\', '/')
        : normalizedFilePath;
    final fileName = p.basenameWithoutExtension(filePath);
    final fileBasename = p.basename(filePath);
    final fileExtension = p.extension(filePath);
    final fileDir = p.dirname(filePath);

    final targetOS = PlatformUtils.getTargetOS(targetPlatform);
    final targetArch = PlatformUtils.getTargetArch(targetPlatform);
    final targetDart = PlatformUtils.vsCodeToDartTarget(targetPlatform);
    final currentOS = PlatformUtils.getTargetOS(currentPlatform);
    final currentArch = PlatformUtils.getTargetArch(currentPlatform);

    if (!args.dryRun && args.verbose) {
      print('  Compiling $fileName for $targetPlatform');
    }

    _ensureTargetOutputDirectory(
      targetPlatform: targetPlatform,
      args: args,
    );

    for (final template in commandTemplates) {
      var command = _resolvePlaceholders(
        template,
        filePath: filePath,
        fileName: fileName,
        fileBasename: fileBasename,
        fileExtension: fileExtension,
        fileDir: fileDir,
        targetOS: targetOS,
        targetArch: targetArch,
        targetDart: targetDart,
        targetPlatform: targetPlatform,
        currentOS: currentOS,
        currentArch: currentArch,
        currentPlatform: currentPlatform,
      );
      _warnMisusedPlaceholders(command, 'compile ($targetPlatform)');
      final success = await _executePipelineCommand(
        rawCommand: _replaceEnvVars(command),
        args: args,
        phaseLabel: 'compile ($targetPlatform)',
      );
      if (!success) {
        print('  Error: Compilation failed for $fileName ($targetPlatform)');
        return false;
      }
    }

    return true;
  }

  Future<bool> _executePipelineCommand({
    required String rawCommand,
    required CliArgs args,
    required String phaseLabel,
  }) async {
    final trimmed = rawCommand.trimLeft();
    if (trimmed == 'print' || trimmed.startsWith('print ')) {
      final message = trimmed == 'print' ? '' : trimmed.substring(6);
      print(message);
      return true;
    }

    final parsed = PipelineCommandPrefixParser.parse(
      rawCommand,
      toolPrefix: 'buildkit',
    );

    if (parsed == null) {
      print(
        '  Error: Unsupported command prefix in "$rawCommand". '
        'Use one of: shell, stdin, shell-scan, print, buildkit.',
      );
      return false;
    }

    switch (parsed.prefix) {
      case PipelineCommandPrefix.shell:
        var shellCommand = parsed.body.trim();
        if (Platform.isWindows) {
          final guarded = appendExeToCompileOutput(shellCommand);
          if (guarded != shellCommand) {
            if (args.verbose || args.dryRun) {
              print('  Note: appended .exe to Windows compile output.');
            }
            shellCommand = guarded;
          }
        }
        if (args.dryRun) {
          print('  [DRY RUN] $phaseLabel: $shellCommand');
          return true;
        }
        if (args.verbose) {
          print('  $phaseLabel: $shellCommand');
        }
        final result = await ProcessRunner.runShell(
          shellCommand,
          workingDirectory: Directory.current.path,
          environment: Platform.environment,
        );
        final shellFailed = result.exitCode != 0;
        final shellCombined =
            '${result.stdout.toLowerCase()}\n${result.stderr.toLowerCase()}';
        final shellHasSignals = shellCombined.contains('error') ||
            shellCombined.contains('warn') ||
            shellCombined.contains('fail');
        if (args.verbose || shellFailed || shellHasSignals) {
          // Cap each per-failure dump in non-verbose mode so a huge AOT error
          // body (e.g. the umbrella `tom` build) stays readable; verbose keeps
          // the full output since the user explicitly asked for detail.
          if (result.stdout.isNotEmpty) {
            stdout.write(args.verbose ? result.stdout : capOutput(result.stdout));
          }
          if (result.stderr.isNotEmpty) {
            stderr.write(args.verbose ? result.stderr : capOutput(result.stderr));
          }
        }
        return !shellFailed;

      case PipelineCommandPrefix.stdin:
        final stdinParsed = script_utils.parseStdinCommand(
          'stdin ${parsed.body}',
        );
        if (stdinParsed == null) {
          print('  Error: Invalid stdin command format in "$rawCommand".');
          return false;
        }
        final stdinResult = await script_utils.executeWithStdin(
          command: stdinParsed.command,
          stdinContent: stdinParsed.stdinContent,
          workingDirectory: Directory.current.path,
          environment: Platform.environment,
          dryRun: args.dryRun,
          verbose: args.verbose,
        );
        return stdinResult;

      case PipelineCommandPrefix.print:
        print(parsed.body);
        return true;

      case PipelineCommandPrefix.shellScan:
        final shellScanCommand = parsed.body.trim();
        if (args.dryRun) {
          print('  [DRY RUN] $phaseLabel [shell-scan]: $shellScanCommand');
          return true;
        }
        if (args.verbose) {
          print('  $phaseLabel [shell-scan]: $shellScanCommand');
        }
        final shellScanResult = await ProcessRunner.runShell(
          shellScanCommand,
          workingDirectory: Directory.current.path,
          environment: Platform.environment,
        );
        final scanFailed = shellScanResult.exitCode != 0;
        final scanCombined =
            '${shellScanResult.stdout.toLowerCase()}\n${shellScanResult.stderr.toLowerCase()}';
        final scanHasSignals = scanCombined.contains('error') ||
            scanCombined.contains('warn') ||
            scanCombined.contains('fail');
        if (args.verbose || scanFailed || scanHasSignals) {
          // Cap each per-failure dump in non-verbose mode (see the shell case).
          if (shellScanResult.stdout.isNotEmpty) {
            stdout.write(
              args.verbose
                  ? shellScanResult.stdout
                  : capOutput(shellScanResult.stdout),
            );
          }
          if (shellScanResult.stderr.isNotEmpty) {
            stderr.write(
              args.verbose
                  ? shellScanResult.stderr
                  : capOutput(shellScanResult.stderr),
            );
          }
        }
        return !scanFailed;

      case PipelineCommandPrefix.tool:
        final argv = _tokenize(parsed.body);
        final inProcessMklink = _tryRunInProcessMklink(argv, args, phaseLabel);
        if (inProcessMklink != null) {
          return inProcessMklink;
        }
        if (args.dryRun) {
          print('  [DRY RUN] $phaseLabel: buildkit ${argv.join(' ')}');
          return true;
        }
        if (args.verbose) {
          print('  $phaseLabel: buildkit ${argv.join(' ')}');
        }
        final exitCode = await runBinaryStreaming(
          'buildkit',
          argv,
          Directory.current.path,
        );
        return exitCode == 0;
    }
  }

  Future<bool>? _tryRunInProcessMklink(
    List<String> argv,
    CliArgs args,
    String phaseLabel,
  ) {
    if (argv.isEmpty) {
      return null;
    }

    final commandToken = argv.first.trim().toLowerCase();
    if (commandToken != ':mklink' && commandToken != 'mklink') {
      return null;
    }

    final positional = <String>[];
    var force = false;
    for (var i = 1; i < argv.length; i++) {
      final token = argv[i].trim();
      if (token == '--force' || token == '-f') {
        force = true;
      } else {
        positional.add(token);
      }
    }

    if (args.verbose || args.dryRun) {
      final prefix = args.dryRun ? '[DRY RUN] ' : '';
      print('  $prefix$phaseLabel: buildkit ${argv.join(' ')} (in-process)');
    }

    return () async {
      if (positional.length < 2) {
        print('  Error: :mklink requires <target-path> <link-path>.');
        return false;
      }

      final targetPath = positional[0];
      final linkPath = positional[1];

      if (args.dryRun) {
        return true;
      }

      final existingType = FileSystemEntity.typeSync(
        linkPath,
        followLinks: false,
      );
      if (existingType != FileSystemEntityType.notFound) {
        if (!force) {
          print(
            '  Error: Destination already exists: $linkPath '
            '(use --force to replace).',
          );
          return false;
        }

        switch (existingType) {
          case FileSystemEntityType.directory:
            Directory(linkPath).deleteSync(recursive: true);
          case FileSystemEntityType.file:
            File(linkPath).deleteSync();
          case FileSystemEntityType.link:
            Link(linkPath).deleteSync();
          case FileSystemEntityType.pipe:
          case FileSystemEntityType.unixDomainSock:
          case FileSystemEntityType.notFound:
            break;
        }
      }

      final parentDir = Directory(p.dirname(linkPath));
      if (!parentDir.existsSync()) {
        parentDir.createSync(recursive: true);
      }

      dcli.createSymLink(targetPath: targetPath, linkPath: linkPath);
      return true;
    }();
  }

  List<String> _tokenize(String input) {
    final matches = RegExp(r'''("[^"]*"|'[^']*'|\S+)''').allMatches(input);
    return matches.map((m) => m.group(0)!).map((token) {
      if ((token.startsWith('"') && token.endsWith('"')) ||
          (token.startsWith("'") && token.endsWith("'"))) {
        return token.substring(1, token.length - 1);
      }
      return token;
    }).toList();
  }

  /// Ensures a `dart compile exe` command writes a `.exe`-suffixed output.
  ///
  /// On Windows an AOT executable must end in `.exe`; a `-o`/`--output` target
  /// without an extension produces an extensionless binary (the stale-cruft
  /// problem). This rewrites such a target to append `.exe`. It is **pure** (no
  /// platform check) so it is testable on every host; callers gate it on
  /// `Platform.isWindows`.
  ///
  /// Only `dart compile exe` commands are touched, and only when the output
  /// target has no extension at all — an explicit extension (`.exe`, or any
  /// other) is left untouched. Quoted targets are preserved.
  static String appendExeToCompileOutput(String command) {
    if (!RegExp(r'\bcompile\b\s+\bexe\b').hasMatch(command)) return command;
    final regex = RegExp(r'(\s(?:-o|--output)(?:=|\s+))("[^"]*"|\S+)');
    return command.replaceAllMapped(regex, (m) {
      final prefix = m.group(1)!;
      final raw = m.group(2)!;
      final quoted =
          raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"');
      final bare = quoted ? raw.substring(1, raw.length - 1) : raw;
      if (p.extension(bare).isNotEmpty) return m.group(0)!;
      final fixed = '$bare.exe';
      return '$prefix${quoted ? '"$fixed"' : fixed}';
    });
  }

  /// Maximum number of lines shown from a failing command's captured output in
  /// non-verbose mode. See [capOutput].
  static const int maxFailureOutputLines = 50;

  /// Caps a captured command-output stream to [maxLines] lines for readable
  /// failure reporting.
  ///
  /// A failing AOT compile (e.g. the umbrella `tom` binary) can emit well over
  /// a thousand error lines; printing the whole dump per failure drowns the log
  /// (tool_run_analysis §b.5, "`tom` failure is enormous and unactionable").
  /// When [text] has more than [maxLines] content lines, this returns the first
  /// [maxLines] lines followed by a one-line truncation marker naming how many
  /// lines were elided and how to see them all. When [text] fits (or is empty),
  /// it is returned unchanged.
  ///
  /// A single trailing newline is not counted as a content line, so output that
  /// is exactly [maxLines] lines plus a trailing newline is left intact.
  ///
  /// Pure (no I/O, no platform check) so it is unit-testable on every host.
  static String capOutput(String text, {int maxLines = maxFailureOutputLines}) {
    if (text.isEmpty) return text;
    final lines = text.split('\n');
    // split() turns a trailing newline into a final empty element; that is not
    // a content line, so exclude it from both the count and the kept slice.
    final content = lines.isNotEmpty && lines.last.isEmpty
        ? lines.sublist(0, lines.length - 1)
        : lines;
    if (content.length <= maxLines) return text;
    final elided = content.length - maxLines;
    final kept = content.take(maxLines).join('\n');
    return '$kept\n'
        '  ... [output truncated: $elided more line(s) of ${content.length} '
        'total; re-run with -v for the full output]\n';
  }

  /// Known compiler placeholder names. These are resolved when written as
  /// `%{name}` (or, for a subset, `[name]`) — never as the shell-style
  /// `${name}`.
  static const Set<String> knownPlaceholderNames = {
    'file',
    'file.path',
    'file.name',
    'file.basename',
    'file.extension',
    'file.dir',
    'target-os',
    'target-arch',
    'dart-target-os',
    'dart-target-arch',
    'target-platform',
    'target-platform-vs',
    'current-os',
    'current-arch',
    'current-platform',
    'current-platform-vs',
  };

  /// Detects compiler placeholders written in the wrong `${name}` shell form.
  ///
  /// The compiler resolves placeholders written as `%{name}` (or `[name]`),
  /// never the shell-style `${name}`. A `${name}` naming a known compiler
  /// placeholder is almost always a `%{}` vs `${}` mistake: the `$` would
  /// otherwise reach the shell and typically expand to an empty string.
  ///
  /// Returns the misused placeholder names (without braces), in order of first
  /// appearance and de-duplicated. An empty list means no misuse was found.
  static List<String> detectMisusedPlaceholders(String command) {
    final found = <String>[];
    for (final match in RegExp(r'\$\{([^}]+)\}').allMatches(command)) {
      final name = match.group(1)!;
      if (knownPlaceholderNames.contains(name) && !found.contains(name)) {
        found.add(name);
      }
    }
    return found;
  }

  /// Prints an actionable hint when [command] contains misused `${...}`
  /// placeholders, pointing at the `%{}` vs `${}` mistake.
  void _warnMisusedPlaceholders(String command, String phaseLabel) {
    final misused = detectMisusedPlaceholders(command);
    if (misused.isEmpty) return;
    final wrong = misused.map((n) => '\${$n}').join(', ');
    final right = misused.map((n) => '%{$n}').join(', ');
    print(
      '  Warning [$phaseLabel]: placeholder(s) $wrong use shell-style '
      '\${...} syntax and will NOT be resolved by the compiler — use %{...} '
      'instead (e.g. $right).',
    );
  }

  String _resolvePlaceholders(
    String template, {
    required String filePath,
    required String fileName,
    required String fileBasename,
    required String fileExtension,
    required String fileDir,
    required String targetOS,
    required String targetArch,
    required String targetDart,
    required String targetPlatform,
    required String currentOS,
    required String currentArch,
    required String currentPlatform,
  }) {
    return template
        .replaceAll(r'%{file}', filePath)
        .replaceAll(r'%{file.path}', filePath)
        .replaceAll(r'%{file.name}', fileName)
        .replaceAll(r'%{file.basename}', fileBasename)
        .replaceAll(r'%{file.extension}', fileExtension)
        .replaceAll(r'%{file.dir}', fileDir)
        .replaceAll(r'%{target-os}', targetOS)
        .replaceAll(r'%{target-arch}', targetArch)
        .replaceAll(r'%{dart-target-os}', targetOS)
        .replaceAll(r'%{dart-target-arch}', targetArch)
        .replaceAll(r'%{target-platform}', targetDart)
        .replaceAll(r'%{target-platform-vs}', targetPlatform)
        .replaceAll(r'%{current-os}', currentOS)
        .replaceAll(r'%{current-arch}', currentArch)
        .replaceAll(r'%{current-platform}', currentPlatform)
        .replaceAll(r'%{current-platform-vs}', currentPlatform)
        .replaceAll('[file]', filePath)
        .replaceAll('[file.name]', fileName)
        .replaceAll('[target-os]', targetOS)
        .replaceAll('[target-arch]', targetArch)
        .replaceAll('[target-platform]', targetDart)
        .replaceAll('[target-platform-vs]', targetPlatform);
  }

  List<String> _expandTargets(List<String> targets) {
    final expanded = <String>[];
    for (final target in targets) {
      expanded.addAll(PlatformUtils.normalizePlatform(target));
    }
    return expanded;
  }

  String _replaceEnvVars(String command) {
    var result = command;
    result = result.replaceAllMapped(RegExp(r'\$(\w+)'), (match) {
      final varName = match.group(1)!;
      if (varName.startsWith('{')) return match.group(0)!;
      var value = Platform.environment[varName] ?? '';
      if (Platform.isWindows) {
        value = value.replaceAll('\\', '/');
      }
      return value;
    });
    result = result.replaceAllMapped(RegExp(r'\[(\w+)\]'), (match) {
      final varName = match.group(1)!;
      var value = Platform.environment[varName] ?? '';
      if (Platform.isWindows) {
        value = value.replaceAll('\\', '/');
      }
      return value;
    });
    return result;
  }

  void _ensureTargetOutputDirectory({
    required String targetPlatform,
    required CliArgs args,
  }) {
    final binaryRoot = Platform.environment['TOM_BINARY_PATH'];
    if (binaryRoot == null || binaryRoot.isEmpty) return;

    final platformDir = Directory(p.join(binaryRoot, targetPlatform));
    if (!platformDir.existsSync()) {
      platformDir.createSync(recursive: true);
      if (args.verbose) {
        print('  Created output directory: ${platformDir.path}');
      }
    }
  }

}
