import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../../console_encoding.dart';
import 'cli_arg_parser.dart';
import 'command_definition.dart';
import 'completion_generator.dart';
import 'console_markdown_zone.dart';
import 'help_generator.dart';
import 'macro_expansion.dart';
import 'nested_tool_executor.dart';
import 'builtin_help_topics.dart';
import 'binary_helpers.dart';
import 'pipeline_config.dart';
import 'pipeline_executor.dart';
import 'tool_definition.dart';
import 'tool_origin.dart';
import 'tool_definition_serializer.dart';
import 'command_executor.dart';
import 'wiring_loader.dart';
import '../execute_placeholder.dart';
import '../folder/fs_folder.dart';
import '../traversal/command_context.dart';
import '../traversal/traversal_info.dart';
import '../traversal/build_base.dart';
import '../traversal/filter_pipeline.dart';
import '../workspace_utils.dart';

/// Result of running a tool or command.
class ToolResult {
  /// Whether the execution was successful.
  final bool success;

  /// Number of items processed.
  final int processedCount;

  /// Number of items that failed.
  final int failedCount;

  /// Error message if failed.
  final String? errorMessage;

  /// Detailed results per item.
  final List<ItemResult> itemResults;

  /// The exit code of a failure that carries no failed item — a usage error
  /// the run stopped on before any command ran ([ToolDefinition
  /// .usageErrorExitCode]); null means 1.
  final int? failureExitCode;

  /// The highest exit code a process may end with for a run: 126 and above
  /// have shell meanings, and an exit status is one byte, so a count of 256
  /// would be read as success.
  static const maxExitCode = 125;

  /// The exit code of the run: 0 on success; on failure the sum of the
  /// failed items' own [ItemResult.exitCode]s (1 for an item without one, and
  /// [failureExitCode] or 1 for a failure with no items), capped at
  /// [maxExitCode].
  int get exitCode {
    if (success) return 0;
    final failed = itemResults.where((i) => !i.success);
    if (failed.isEmpty) return (failureExitCode ?? 1).clamp(1, maxExitCode);
    final sum = failed.fold<int>(0, (n, i) => n + (i.exitCode ?? 1));
    return sum.clamp(1, maxExitCode);
  }

  const ToolResult({
    this.success = true,
    this.processedCount = 0,
    this.failedCount = 0,
    this.errorMessage,
    this.itemResults = const [],
    this.failureExitCode,
  });

  /// Create a success result.
  const ToolResult.success({
    this.processedCount = 0,
    this.itemResults = const [],
  }) : success = true,
       failedCount = 0,
       errorMessage = null,
       failureExitCode = null;

  /// Create a failure result; [exitCode] is the process exit code it ends
  /// with (1 when null).
  const ToolResult.failure(this.errorMessage, {int? exitCode})
    : success = false,
      processedCount = 0,
      failedCount = 0,
      itemResults = const [],
      failureExitCode = exitCode;

  /// Create from aggregated item results.
  factory ToolResult.fromItems(List<ItemResult> items) {
    final failed = items.where((i) => !i.success).length;
    return ToolResult(
      success: failed == 0,
      processedCount: items.length,
      failedCount: failed,
      itemResults: items,
    );
  }

  /// Render a consolidated end-of-run summary block shared by every
  /// `tom_build_base`-based tool, so outcomes read uniformly after a long run.
  ///
  /// The block contains, in order:
  /// 1. a **Skipped** section listing items that were deliberately skipped
  ///    (configured/conditional skips — see [ItemResult.skipped]);
  /// 2. either an **Errors** section naming every failed item (with a
  ///    `N error(s) in M project(s).` tally) or, when nothing failed, the
  ///    single line `Done. No errors.`.
  ///
  /// Returns an empty string when no items were processed (e.g. `--version`,
  /// `--help`, or a single-shot command that does no traversal), so callers
  /// can print it unconditionally without adding a spurious footer. The
  /// returned string has no leading or trailing newline; the caller frames it.
  ///
  /// When the items carry durations (ToolRunner times every project) a
  /// **Timing** section comes before the footer: per command the projects
  /// it ran on, their summed time and the three slowest; then the run's
  /// total [elapsed] and how much of it was startup and traversal rather
  /// than the commands' own work.
  String renderRunSummary({Duration? elapsed}) {
    if (itemResults.isEmpty) return '';

    final failures = itemResults.where((i) => !i.success).toList();
    final skips = itemResults.where((i) => i.success && i.skipped).toList();

    String describe(ItemResult item, String detail) {
      // `default` is a single-command tool's executor key, not a command
      // the user typed (the timing table leaves it out the same way).
      final name = item.commandName;
      final cmd = name != null && name != 'default' ? ' :$name' : '';
      return '  ${item.name}$cmd — $detail';
    }

    final lines = <String>[];

    if (skips.isNotEmpty) {
      lines.add('=== Skipped ===');
      for (final item in skips) {
        lines.add(describe(item, item.message ?? 'skipped'));
      }
      final skippedProjects = skips.map((s) => s.name).toSet().length;
      lines.add('$skippedProjects project(s) skipped.');
      lines.add('');
    }

    lines.addAll(_timingLines(elapsed));

    if (failures.isNotEmpty) {
      lines.add('=== Errors ===');
      for (final item in failures) {
        lines.add(describe(item, item.error ?? 'unknown error'));
      }
      final failedProjects = failures.map((f) => f.name).toSet().length;
      lines.add('${failures.length} error(s) in $failedProjects project(s).');
    } else {
      lines.add('Done. No errors.');
    }

    return lines.join('\n');
  }

  /// The Timing section, or nothing when no item was timed.
  List<String> _timingLines(Duration? elapsed) {
    final timed = itemResults.where((i) => i.duration != null).toList();
    if (timed.isEmpty) return const [];
    final byCommand = <String, List<ItemResult>>{};
    for (final item in timed) {
      byCommand.putIfAbsent(item.commandName ?? '', () => []).add(item);
    }
    var work = Duration.zero;
    final lines = ['=== Timing ==='];
    for (final entry in byCommand.entries) {
      final items = entry.value;
      final sum = items.fold(Duration.zero, (t, i) => t + i.duration!);
      work += sum;
      final label = entry.key.isEmpty || entry.key == 'default'
          ? 'run'
          : ':${entry.key}';
      // A slowest list only says something when a project took a moment.
      final slowest =
          items.length < 2 ||
              items.every((i) => i.duration! < const Duration(milliseconds: 50))
          ? ''
          : '  (slowest: ${([...items]..sort((a, b) => b.duration!.compareTo(a.duration!))).take(3).map((i) => '${i.name} ${formatDuration(i.duration!)}').join(', ')})';
      lines.add(
        '  $label  ${items.length} project(s)  ${formatDuration(sum)}$slowest',
      );
    }
    if (elapsed != null) {
      if (work > elapsed) {
        // More project time than the run took: the projects ran at once.
        lines.add(
          '  Total ${formatDuration(elapsed)}; the projects ran at once '
          '(${formatDuration(work)} of project time)',
        );
      } else {
        lines.add(
          '  Total ${formatDuration(elapsed)}, of which startup and traversal '
          '${formatDuration(elapsed - work)}',
        );
      }
    }
    lines.add('');
    return lines;
  }
}

/// [d] as `0.3s`, `12.4s` or `2m 05.4s`: tenths of a second, minutes from
/// one minute on.
String formatDuration(Duration d) {
  final tenths = (d.inMilliseconds / 100).round();
  final seconds = tenths ~/ 10;
  final tenth = tenths % 10;
  if (seconds < 60) return '$seconds.${tenth}s';
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '${minutes}m $rest.${tenth}s';
}

/// Result for a single processed item (folder/project).
class ItemResult {
  /// Item path.
  final String path;

  /// Item name.
  final String name;

  /// The command that produced this result (e.g. 'runner', 'compiler').
  final String? commandName;

  /// Whether processing succeeded.
  final bool success;

  /// Whether the item was deliberately skipped (a configured/conditional
  /// skip — not a failure). Skipped items are still [success] so they never
  /// affect the exit code, but the end-of-run summary lists them separately
  /// from items that did real work. See [ToolResult.renderRunSummary].
  final bool skipped;

  /// Result message.
  final String? message;

  /// Error message if failed.
  final String? error;

  /// The exit code this failure stands for (e.g. a mutation sweep's count of
  /// surviving and invalid mutants); null counts 1. See
  /// [ToolResult.exitCode].
  final int? exitCode;

  /// How long the item took; ToolRunner measures every project it runs a
  /// command on. Null for an item nothing timed.
  final Duration? duration;

  const ItemResult({
    required this.path,
    required this.name,
    this.commandName,
    this.success = true,
    this.skipped = false,
    this.message,
    this.error,
    this.exitCode,
    this.duration,
  });

  const ItemResult.success({
    required this.path,
    required this.name,
    this.commandName,
    this.message,
    this.duration,
  }) : success = true,
       skipped = false,
       error = null,
       exitCode = null;

  /// A deliberately skipped item — a configured or conditional skip, reported
  /// as a (non-failing) success so it does not affect the exit code, but
  /// surfaced in the end-of-run summary's skipped section. [message] should
  /// explain why the item was skipped.
  const ItemResult.skipped({
    required this.path,
    required this.name,
    this.commandName,
    this.message,
    this.duration,
  }) : success = true,
       skipped = true,
       error = null,
       exitCode = null;

  const ItemResult.failure({
    required this.path,
    required this.name,
    this.commandName,
    required this.error,
    this.exitCode,
    this.duration,
  }) : success = false,
       skipped = false,
       message = null;

  /// This result with [commandName] (when it has none) and [duration]
  /// (when it has none): what ToolRunner knows of every item it runs.
  ItemResult timed({String? commandName, required Duration duration}) =>
      ItemResult(
        path: path,
        name: name,
        commandName: this.commandName ?? commandName,
        success: success,
        skipped: skipped,
        message: message,
        error: error,
        exitCode: exitCode,
        duration: this.duration ?? duration,
      );
}

class _RequirementCheckResult {
  final List<String> warnings;
  final List<String> errors;
  final String? setupInstructions;

  /// The pipeline `required-environment.setup.setup-pipeline` names: run it
  /// to set up what is missing.
  final String? setupPipeline;

  const _RequirementCheckResult({
    this.warnings = const [],
    this.errors = const [],
    this.setupInstructions,
    this.setupPipeline,
  });

  bool get hasErrors => errors.isNotEmpty;

  bool get hasIssues => warnings.isNotEmpty || errors.isNotEmpty;
}

/// Runs tools based on their definitions.
///
/// Handles argument parsing, help display, command routing,
/// traversal execution, and nested tool wiring.
class ToolRunner {
  /// Tool definition.
  final ToolDefinition tool;

  /// Command executors by name.
  final Map<String, CommandExecutor> executors;

  /// Mutable copy of tool definition (updated during wiring).
  late ToolDefinition _effectiveTool;

  /// Whether to print output.
  final bool verbose;

  /// Output writer (default: stdout).
  final StringSink output;

  /// Where a usage error is written — an argument error, an unknown or
  /// ambiguous command (default: [output]). A tool whose commands keep stdout
  /// for their own output (a JSON report) passes stderr.
  final StringSink errorOutput;

  /// Runtime-only macros (`$macro`) for this invocation session.
  ///
  /// These are persisted to `{workspace_root}/{tool_name}_macros.yaml` so that
  /// macros defined in one invocation are visible in subsequent ones.
  final Map<String, String> _runtimeMacros = <String, String>{};

  /// Whether the persisted macros have been loaded into [_runtimeMacros].
  bool _macrosLoaded = false;

  ToolRunner({
    required this.tool,
    this.executors = const {},
    this.verbose = true,
    StringSink? output,
    StringSink? errorOutput,
    Future<ProcessResult> Function(
      String binary,
      List<String> args,
      String workingDirectory,
    )?
    workspaceRunner,
  }) : output = _resolveOutput(output),
       errorOutput = errorOutput ?? _resolveOutput(output),
       _workspaceRunner = workspaceRunner ?? runSelf {
    _effectiveTool = tool;
  }

  /// How `-w` runs the tool in a nested workspace: this program again
  /// ([runSelf]: the same binary or script, nothing looked up on the PATH)
  /// unless a test hands its own.
  final Future<ProcessResult> Function(
    String binary,
    List<String> args,
    String workingDirectory,
  )
  _workspaceRunner;

  /// The arguments of the run after macro expansion and normalization: what
  /// `-w` hands a nested workspace (without the scan roots).
  List<String> _invocationArgs = const [];

  /// The nested workspaces `-w` has run the tool in during this run, so a
  /// workspace passed over by several commands' traversals runs once.
  final _ranInWorkspaces = <String>{};

  /// Resolve the output sink.
  ///
  /// When running inside a console_markdown zone and no explicit sink is
  /// provided, wraps [stdout] in a [ConsoleMarkdownSink] so that
  /// `output.writeln()` calls also render markdown.  When an explicit sink
  /// is provided (e.g. a test buffer), it is used as-is.
  static StringSink _resolveOutput(StringSink? explicit) {
    if (explicit != null) return explicit;
    if (isConsoleMarkdownActive) return ConsoleMarkdownSink(stdout);
    return stdout;
  }

  /// Normalize legacy/alternative flag forms before parsing.
  ///
  /// Converts single-dash long-form flags to their canonical double-dash form,
  /// at any position in [args]:
  /// - `-version` → `--version`
  /// - `-help` → `--help`
  ///
  /// [run] applies this automatically after macro expansion. It is also exposed
  /// publicly so tools that pre-parse arguments *before* delegating to [run]
  /// (e.g. to detect a TUI mode, or to early-exit for help/version before
  /// loading credentials) can apply the identical normalization instead of
  /// maintaining their own duplicate helper. Idempotent; returns [args]
  /// unchanged when empty or when there is nothing to convert.
  static List<String> normalizeArgs(List<String> args) {
    if (args.isEmpty) return args;
    return args.map((arg) {
      if (arg == '-version') return '--version';
      if (arg == '-help') return '--help';
      return arg;
    }).toList();
  }

  static String _formatMs(Duration d) => '${d.inMilliseconds}ms';

  String _formatCommandStatus(ItemResult result) {
    if (result.success) {
      final message = result.message?.trim();
      if (message != null && message.isNotEmpty) return message;
      return 'ok';
    }

    final error = result.error?.trim();
    if (error != null && error.isNotEmpty) {
      return 'ERROR: $error';
    }
    return 'ERROR: failed';
  }

  Future<ItemResult> _executeItemGuarded({
    required CommandContext context,
    required String commandName,
    required Future<ItemResult> Function() action,
  }) async {
    final completer = Completer<ItemResult>();
    final watch = Stopwatch()..start();

    runZonedGuarded(
      () async {
        try {
          final result = await action();
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        } catch (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.complete(
              ItemResult.failure(
                path: context.path,
                name: context.name,
                error: 'Unhandled exception in :$commandName: $error',
              ),
            );
          }
          if (verbose) {
            output.writeln('     STACK: $stackTrace');
          }
        }
      },
      (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.complete(
            ItemResult.failure(
              path: context.path,
              name: context.name,
              error: 'Unhandled zone error in :$commandName: $error',
            ),
          );
        }
        if (verbose) {
          output.writeln('     STACK: $stackTrace');
        }
      },
    );

    final result = await completer.future;
    return result.timed(commandName: commandName, duration: watch.elapsed);
  }

  /// Calls [executor]'s [CommandExecutor.afterTraversal] with the results of
  /// its command and answers the item it adds to the run, if any; an
  /// exception there becomes a failure item, as one in `execute` does.
  Future<ItemResult?> _afterTraversal(
    CommandExecutor executor,
    String commandName,
    List<ItemResult> results,
    CliArgs cliArgs,
  ) async {
    try {
      return await executor.afterTraversal(List.unmodifiable(results), cliArgs);
    } catch (error, stackTrace) {
      if (verbose) {
        output.writeln('     STACK: $stackTrace');
      }
      return ItemResult.failure(
        path: '',
        name: commandName,
        commandName: commandName,
        error: 'Unhandled exception after :$commandName: $error',
      );
    }
  }

  /// The pool a parallel [cmd]'s projects run in, or null to run them one
  /// after another: `--jobs <n>` (written before or after the command), by
  /// default the CPU count, at most 8.
  _JobPool? _poolFor(CommandDefinition cmd, CliArgs cliArgs) {
    if (!cmd.parallel || _listOnly) return null;
    final value =
        cliArgs.optionsFor(cmd.name)['jobs'] ?? cliArgs.extraOptions['jobs'];
    final jobs = value == null
        ? (Platform.numberOfProcessors < 8 ? Platform.numberOfProcessors : 8)
        : int.tryParse('$value') ?? 1;
    return jobs > 1 ? _JobPool(jobs) : null;
  }

  /// Runs [action] with everything it prints held back and written to
  /// [output] in one piece when it is done, so projects running at once do
  /// not interleave their lines. [action] writes its own lines to the sink
  /// it is given.
  Future<T> _heldOutput<T>(Future<T> Function(StringSink out) action) async {
    final buffer = StringBuffer();
    try {
      return await runZoned(
        () => action(buffer),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => buffer.writeln(line),
        ),
      );
    } finally {
      if (buffer.isNotEmpty) output.write(buffer.toString());
    }
  }

  void _printStartupTiming(String label, Duration phase, Duration total) {
    output.writeln(
      '[startup] $label: +${_formatMs(phase)} (total ${_formatMs(total)})',
    );
  }

  /// Run the tool to completion, applying the shared CLI entrypoint contract.
  ///
  /// This folds the identical `run → print summary → set exit code` tail that
  /// every tool's `main` repeated (buildkit/testkit/issuekit) into a single
  /// shared implementation, so the process-exit semantics defined in
  /// `doc/cli_error_handling.md` cannot drift per tool. It:
  ///
  /// 1. runs [args] via [run];
  /// 2. writes `result.renderRunSummary()` (with a leading blank line) to
  ///    [output] when it is non-empty — empty for single-shot commands that
  ///    traverse nothing (`--version`, `--help`);
  /// 3. sets the process [exitCode] to [ToolResult.exitCode] (1 unless items
  ///    carry their own) when the run failed — and **never**
  ///    calls `exit()`, so `main` can return and the VM drains buffered output
  ///    first (a bare `exit(1)` can truncate the summary just written).
  ///
  /// Returns the [ToolResult] so callers may inspect it further. A successful
  /// run leaves [exitCode] untouched (it does not reset it to `0`).
  Future<ToolResult> runToCompletion(List<String> args) async {
    final watch = Stopwatch()..start();
    final result = await run(args);

    final summary = result.renderRunSummary(elapsed: watch.elapsed);
    if (summary.isNotEmpty) {
      output.writeln('\n$summary');
    }

    if (!result.success) {
      exitCode = result.exitCode;
    }

    return result;
  }

  /// Run the tool with command-line arguments.
  Future<ToolResult> run(List<String> args) async {
    // Ensure non-ASCII tool/subprocess output renders correctly on Windows
    // (UTF-8 console + sinks). No-op on other platforms; idempotent.
    enableUtf8Console();

    final startupWatch = Stopwatch()..start();
    var lastCheckpoint = Duration.zero;

    Duration checkpoint() {
      final now = startupWatch.elapsed;
      lastCheckpoint = now;
      return now;
    }

    Duration phaseSinceLast() {
      return startupWatch.elapsed - lastCheckpoint;
    }

    // Expand macros before parsing (loads persisted macros if needed)
    _loadPersistedMacros();
    final expandedArgs = expandMacros(args, _runtimeMacros);
    final expandedAt = checkpoint();

    // Normalize legacy flags before parsing.
    final normalizedArgs = normalizeArgs(expandedArgs);
    _invocationArgs = normalizedArgs;

    // Parse arguments
    final parser = CliArgParser(toolDefinition: tool);
    final cliArgs = parser.parse(normalizedArgs);
    final parsedAt = checkpoint();

    if (cliArgs.verbose) {
      _printStartupTiming('Load macros + expand args', expandedAt, expandedAt);
      _printStartupTiming(
        'Normalize + parse args',
        parsedAt - expandedAt,
        parsedAt,
      );
    }

    // Arguments the parser refused (e.g. `-s-`) stop the run before anything
    // else: a run carried out without what the caller wrote is the wrong run.
    if (cliArgs.argumentErrors.isNotEmpty) {
      for (final error in cliArgs.argumentErrors) {
        errorOutput.writeln('Error: $error');
      }
      return ToolResult.failure(
        'Invalid arguments: ${cliArgs.argumentErrors.join('; ')}',
        exitCode: tool.usageErrorExitCode,
      );
    }

    _listOnly = cliArgs.listOnly;

    // --dump-definitions: serialize tool definition and exit immediately.
    // Intercepted before any wiring or traversal.
    if (cliArgs.dumpDefinitions) {
      final yaml = ToolDefinitionSerializer.toYaml(tool);
      output.write(yaml);
      return const ToolResult.success();
    }

    // --completion <shell>: emit a shell completion script and exit.
    // Intercepted here (like --dump-definitions) so it works as a bare
    // invocation, before any wiring, env checks, or traversal.
    if (cliArgs.completion != null) {
      return _handleCompletion(cliArgs.completion!);
    }

    // A tool whose `features.dryRun` is false has no dry-run mode. Accepting
    // `-n` and running anyway is the dangerous default: the caller asked for a
    // preview and got a real run, which is how `d4rtgen -n` used to regenerate
    // files. Refuse here -- after the informational intercepts above and
    // `isHelpMode` below, so `-n --help` still prints help, but before any
    // wiring, traversal or executor runs.
    if (cliArgs.dryRun && !tool.features.dryRun && !cliArgs.isHelpMode) {
      output.writeln(
        'Error: ${tool.name} has no dry-run mode, so -n / --dry-run is not '
        'supported. Re-run without the flag to do the work for real.',
      );
      return ToolResult.failure(
        '${tool.name} has no dry-run mode (-n / --dry-run not supported)',
      );
    }

    // `required-environment:` of the master file is checked before every run
    // except help / version / list, a `--nested` run (its host checked), the
    // setup pipeline (it is the fix) and an explicit bypass. An error stops
    // the run and says how to fix it; warnings show in doctor and with -v.
    // Version tests (they start the binary) run in doctor only.
    final doctorRequested = _isDoctorRequested(cliArgs);
    final bypassRequiredEnvironmentChecks =
        !doctorRequested &&
        (cliArgs.isHelpMode ||
            cliArgs.nested ||
            _onlyCommandsWithoutEnvironment(cliArgs) ||
            _isRequiredEnvironmentCheckBypassed());

    if (cliArgs.verbose) {
      output.writeln(
        '[startup] Required-environment checks: '
        '${bypassRequiredEnvironmentChecks ? 'skipped' : 'enabled'}',
      );
    }

    if (!bypassRequiredEnvironmentChecks) {
      final checks = _runRequiredEnvironmentChecks(
        withVersionTests: doctorRequested,
      );
      if (cliArgs.verbose) {
        final phase = phaseSinceLast();
        final total = checkpoint();
        _printStartupTiming('Run required-environment checks', phase, total);
      }
      final setupRun =
          checks.setupPipeline != null &&
          cliArgs.commands.isEmpty &&
          cliArgs.positionalArgs.firstOrNull == checks.setupPipeline;
      if (doctorRequested) {
        if (checks.hasIssues) _printRequirementIssues(checks);
        if (checks.hasErrors) {
          return const ToolResult.failure('Installation requirements not met');
        }
        output.writeln('Doctor check passed.');
        return const ToolResult.success();
      }
      if (!setupRun) {
        if (checks.hasErrors) {
          _printRequirementIssues(checks);
          return const ToolResult.failure('Installation requirements not met');
        }
        if (cliArgs.verbose && checks.hasIssues) {
          _printRequirementIssues(checks);
        }
      }
    }

    // --nested: skip wiring, skip traversal, run single-project in cwd.
    if (cliArgs.nested) {
      if (cliArgs.verbose) {
        final phase = phaseSinceLast();
        final total = checkpoint();
        _printStartupTiming('Enter nested mode', phase, total);
      }
      return _runNestedMode(cliArgs);
    }

    // Lazy wiring: merge code + YAML defaults, query only needed tools.
    if (tool.hasWiring) {
      final wiringOk = await _lazyWireNestedTools(cliArgs);
      if (cliArgs.verbose) {
        final phase = phaseSinceLast();
        final total = checkpoint();
        _printStartupTiming('Lazy nested-tool wiring', phase, total);
      }
      if (!wiringOk) {
        return const ToolResult.failure('Missing nested tool binaries');
      }
    }

    // Auto-inject master YAML help topics for multiCommand tools.
    if (_effectiveTool.mode == ToolMode.multiCommand &&
        _effectiveTool.builtInHelpTopics) {
      _injectMasterYamlHelpTopics();
      if (cliArgs.verbose) {
        final phase = phaseSinceLast();
        final total = checkpoint();
        _printStartupTiming('Inject help topics', phase, total);
      }
    }

    // Handle help (uses _effectiveTool which now includes wired commands)
    if (cliArgs.help) {
      return _handleHelp(cliArgs);
    }

    // Handle bare 'help' positional: 'buildkit help pipelines' (a topic),
    // 'buildkit help compiler' / 'help :compiler' (a command).
    if (cliArgs.positionalArgs.firstOrNull == 'help') {
      final topic = _bareHelpName(cliArgs);
      if (topic != null) {
        final name = topic.startsWith(':') ? topic.substring(1) : topic;
        final builtInHelp = _tryHandleBuiltInMacroDefineHelp(name);
        if (builtInHelp != null) {
          output.writeln(builtInHelp);
          return const ToolResult.success();
        }
        if (!topic.startsWith(':')) {
          final topicDef = _effectiveTool.findHelpTopic(name);
          if (topicDef != null) {
            output.writeln(
              HelpGenerator.generateTopicHelp(topicDef, tool: _effectiveTool),
            );
            return const ToolResult.success();
          }
        }
        final commandHelp = await _commandHelp(name, cliArgs);
        if (commandHelp != null) return commandHelp;
        output.writeln('Unknown help topic: $topic');
        return const ToolResult.failure('Unknown help topic');
      }
      // 'help' alone — show full tool help
      final baseHelp = HelpGenerator.generateToolHelp(
        _effectiveTool,
        nestedCommandNames: _wiredExecutors.keys.toSet(),
      );
      output.write(baseHelp);
      final appendix = _builtInMacroDefineHelpAppendix();
      if (appendix != null) {
        output.writeln();
        output.writeln(appendix);
      }
      return const ToolResult.success();
    }

    // Handle version (--version flag or bare 'version' positional arg)
    if (cliArgs.version || cliArgs.positionalArgs.contains('version')) {
      final versionOutput =
          _effectiveTool.versionString ??
          '${_effectiveTool.name} v${_effectiveTool.version}';
      output.writeln(versionOutput);
      // SCE8: which COPY answered, under the number. The first line is
      // unchanged on purpose — anything parsing the banner reads that one —
      // and the origin goes beneath it. A version alone cannot distinguish a
      // working tree carrying an unpublished fix from a pub-cache copy or a
      // binary on PATH out of another clone; SCC70 lost a regeneration batch
      // to exactly that ambiguity.
      output.writeln(currentToolOriginLine());
      return const ToolResult.success();
    }

    // Handle multi-command mode
    if (_effectiveTool.mode == ToolMode.multiCommand) {
      final pipelineAttempt = await _tryRunPipelineInvocation(cliArgs);
      if (pipelineAttempt != null) {
        return pipelineAttempt;
      }

      if (cliArgs.commands.isEmpty && _listOnly) {
        return _listCommandsAndPipelines();
      }

      if (cliArgs.commands.isEmpty) {
        if (_effectiveTool.defaultCommand != null) {
          return _runCommand(_effectiveTool.defaultCommand!, cliArgs);
        }
        errorOutput.writeln('No command specified.\n');
        errorOutput.writeln(HelpGenerator.generateUsageSummary(_effectiveTool));
        return ToolResult.failure(
          'No command specified',
          exitCode: _effectiveTool.usageErrorExitCode,
        );
      }

      return _runMultiCommandFolderByFolder(cliArgs);
    }

    // Single command mode - run default executor
    final executor = _listing(executors['default'], 'default');
    if (executor == null) {
      return const ToolResult.failure('No default executor configured');
    }

    // A single-command tool that visits no projects (a daemon, a server:
    // neither project nor git traversal) runs once, in the current directory.
    // An executor that implements only execute() (a tool that works on the
    // project it is run in) gets the current directory as its project.
    if (!_effectiveTool.features.projectTraversal &&
        !_effectiveTool.features.gitTraversal) {
      final result = await executor.executeWithoutTraversal(cliArgs);
      if (!hasNoRunWithoutTraversal(result)) return result;
    }

    return _runWithTraversal(executor, null, cliArgs);
  }

  /// Run multi-command tools folder-by-folder in a single traversal.
  ///
  /// For each matching folder, all commands are executed in the order given.
  /// If commands are not traversal-compatible, falls back to legacy
  /// command-by-command execution.
  Future<ToolResult> _runMultiCommandFolderByFolder(CliArgs cliArgs) async {
    final resolved = <({CommandDefinition cmd, CommandExecutor executor})>[];
    for (final cmdName in cliArgs.commands) {
      final cmd = _effectiveTool.findCommand(cmdName);
      if (cmd == null) {
        // Keep existing error semantics via single-command path.
        return _runCommand(cmdName, cliArgs);
      }
      final executor = _findExecutor(cmd.name);
      if (executor == null) {
        return ToolResult.failure('No executor for command: ${cmd.name}');
      }
      resolved.add((cmd: cmd, executor: executor));
    }

    // If any command is non-traversal, preserve legacy behavior.
    if (resolved.any((entry) => !entry.cmd.requiresTraversal)) {
      final results = <ItemResult>[];
      for (final entry in resolved) {
        final result = await _runWithTraversal(
          entry.executor,
          entry.cmd,
          cliArgs,
        );
        results.addAll(result.itemResults);
        if (!result.success) return result;
      }
      return ToolResult.fromItems(results);
    }

    // Multi-command folder-first traversal currently supports project traversal.
    // If git traversal is requested/required by any command, keep legacy behavior
    // until mixed traversal policies are unified.
    final needsGitTraversal = resolved.any(
      (entry) =>
          entry.cmd.requiresGitTraversal ||
          (cliArgs.gitModeExplicitlySet && entry.cmd.supportsGitTraversal),
    );
    if (needsGitTraversal) {
      final results = <ItemResult>[];
      for (final entry in resolved) {
        final result = await _runWithTraversal(
          entry.executor,
          entry.cmd,
          cliArgs,
        );
        results.addAll(result.itemResults);
        if (!result.success) return result;
      }
      return ToolResult.fromItems(results);
    }

    final String executionRoot;
    if (cliArgs.root != null) {
      executionRoot = cliArgs.root!;
    } else {
      // Outside a workspace a tool runs on the directory it was started in.
      executionRoot =
          findWorkspaceRootOrNull(Directory.current.path) ??
          Directory.current.path;
    }

    // Reject any --project path (global *or* per-command) that is outside the
    // workspace or that names a non-glob path which does not exist.
    final projectPathsError = _guardProjectPaths(cliArgs, executionRoot);
    if (projectPathsError != null) {
      return ToolResult.failure(projectPathsError);
    }

    final configDefaults = TraversalDefaults.load(executionRoot);
    final traversalInfo = cliArgs.toProjectTraversalInfo(
      executionRoot: executionRoot,
      configDefaults: configDefaults,
    );

    // Security boundary: reject a --scan path outside the workspace.
    final scanPathError = validateScanRootsWithinRoot(
      traversalInfo.scanRoots,
      executionRoot,
    );
    if (scanPathError != null) {
      output.writeln('Error: $scanPathError');
      return ToolResult.failure(scanPathError);
    }

    final masterDefines = _loadMasterDefines(cliArgs.modes);
    final results = <ItemResult>[];
    // Folders run at once only when every command of the run is parallel.
    final pool = resolved.every((e) => e.cmd.parallel)
        ? _poolFor(resolved.first.cmd, cliArgs)
        : null;
    final pending = <List<ItemResult>>[];

    final processingResult = await BuildBase.traverse(
      info: traversalInfo,
      verbose: verbose,
      worksWithNatures: const {FsFolder},
      // Per-command patterns are applied inside `run` rather than by the
      // filter pipeline, so they have to be handed to the audit explicitly.
      additionalProjectPatterns: [
        for (final entry in resolved)
          ...?cliArgs.commandArgs[entry.cmd.name]?.projectPatterns,
      ],
      allowUnmatchedProjectPatterns: cliArgs.allowEmpty,
      run: (context) async {
        final runnable =
            <
              ({
                CommandDefinition cmd,
                CommandExecutor executor,
                CliArgs resolvedArgs,
              })
            >[];

        // Resolve args once per folder.
        final placeholderCtx = ExecutePlaceholderContext.fromCommandContext(
          context,
          executionRoot,
        );
        final placeholderResolvedArgs = cliArgs.withResolvedStrings(
          (s) => ExecutePlaceholderResolver.resolveCommand(
            s,
            placeholderCtx,
            skipUnknown: true,
          ),
        );
        final projectDefines = _loadProjectDefines(
          context.fsFolder.path,
          masterDefines,
          cliArgs.modes,
        );
        final resolvedArgs = placeholderResolvedArgs.withResolvedStrings(
          (s) => _resolveDefineString(s, projectDefines),
        );

        for (final entry in resolved) {
          if (!_contextMatchesCommandNatures(context, entry.cmd)) {
            continue;
          }
          if (!_contextPassesPerCommandFilters(
            context,
            traversalInfo,
            cliArgs,
            entry.cmd,
          )) {
            continue;
          }
          runnable.add((
            cmd: entry.cmd,
            executor: entry.executor,
            resolvedArgs: resolvedArgs,
          ));
        }

        if (runnable.isEmpty) return true;

        // The folder's commands, one after another; the folder itself runs
        // beside others when every command of the run is parallel.
        Future<List<ItemResult>> folderWork(StringSink out) async {
          final folderResults = <ItemResult>[];
          // The stand-in under --list prints its own line per project.
          if (!runnable.every((e) => e.executor is _ListingExecutor)) {
            out.writeln('>>> ${context.relativePath}');
          }

          for (final runEntry in runnable) {
            final result = await _executeItemGuarded(
              context: context,
              commandName: runEntry.cmd.name,
              action: () =>
                  runEntry.executor.execute(context, runEntry.resolvedArgs),
            );
            // Tag result with the command that produced it.
            final tagged = ItemResult(
              path: result.path,
              name: result.name,
              commandName: runEntry.cmd.name,
              success: result.success,
              skipped: result.skipped,
              message: result.message,
              error: result.error,
              exitCode: result.exitCode,
              duration: result.duration,
            );
            folderResults.add(tagged);

            if (runEntry.executor is! _ListingExecutor) {
              out.writeln(
                '  -> :${runEntry.cmd.name} ${_formatCommandStatus(tagged)}',
              );
            }

            if (!tagged.success) {
              // Stop remaining commands for this folder, continue traversal.
              break;
            }
          }
          return folderResults;
        }

        if (pool == null) {
          results.addAll(await folderWork(output));
        } else {
          final slot = pending.length;
          pending.add(const []);
          pool.add(() async {
            pending[slot] = await _heldOutput(folderWork);
          });
        }
        return true;
      },
    );
    if (pool != null) {
      await pool.drain();
      results.addAll(pending.expand((r) => r));
    }

    final unmatchedError = _reportUnmatchedProjects(
      processingResult,
      traversalInfo,
      allowEmpty: cliArgs.allowEmpty,
    );
    if (unmatchedError != null) return ToolResult.failure(unmatchedError);

    for (final entry in resolved) {
      final extra = await _afterTraversal(entry.executor, entry.cmd.name, [
        for (final r in results)
          if (r.commandName == entry.cmd.name) r,
      ], cliArgs);
      if (extra != null) results.add(extra);
    }
    results.addAll(await _runInNestedWorkspaces(processingResult, cliArgs));

    return ToolResult.fromItems(results);
  }

  /// With `-w`: runs this tool, with this run's arguments, in each nested
  /// workspace (a folder with its own `buildkit_master.yaml`) the traversal
  /// passed over, from that folder; each uses its own configuration and,
  /// with `-w` handed on, its own nested workspaces. A traversal option that
  /// pins this run (`--root`, `--project`, `--exclude`, `--group`) keeps
  /// them out, with a message. One item per workspace: it fails when the
  /// tool exits with an error there.
  Future<List<ItemResult>> _runInNestedWorkspaces(
    ProcessingResult processing,
    CliArgs cliArgs,
  ) async {
    if (!cliArgs.workspaceRecursion || cliArgs.nested) return const [];
    final workspaces = processing.skippedWorkspaces
        .where(_ranInWorkspaces.add)
        .toList();
    if (workspaces.isEmpty) return const [];
    if (PipelineOptionResolver.hasDisqualifyingTraversalOptions(cliArgs)) {
      for (final ws in workspaces) {
        output.writeln(
          'Skipped workspace: ${p.basename(ws)}, global traversal option '
          'specified.',
        );
      }
      return const [];
    }
    final args = argsForNestedWorkspace(_invocationArgs);
    final results = <ItemResult>[];
    for (final ws in workspaces) {
      final name = p.basename(ws);
      output.writeln('>>> workspace $name: ${tool.name} ${args.join(' ')}');
      final ProcessResult run;
      try {
        run = await _workspaceRunner(tool.name, args, ws);
      } on ProcessException catch (e) {
        results.add(
          ItemResult.failure(
            path: ws,
            name: 'workspace $name',
            error: 'could not start ${tool.name}: ${e.message}',
          ),
        );
        continue;
      }
      for (final stream in [run.stdout, run.stderr]) {
        final text = '$stream'.trimRight();
        if (text.isNotEmpty) output.writeln(text);
      }
      results.add(
        run.exitCode == 0
            ? ItemResult.success(path: ws, name: 'workspace $name')
            : ItemResult.failure(
                path: ws,
                name: 'workspace $name',
                error: '${tool.name} exited with code ${run.exitCode}',
                exitCode: run.exitCode,
              ),
      );
    }
    return results;
  }

  bool _contextPassesPerCommandFilters(
    CommandContext context,
    BaseTraversalInfo traversalInfo,
    CliArgs cliArgs,
    CommandDefinition cmd,
  ) {
    if (traversalInfo is! ProjectTraversalInfo) return true;
    final cmdArgs = cliArgs.commandArgs[cmd.name];
    if (cmdArgs == null) return true;

    if (cmdArgs.projectPatterns.isNotEmpty) {
      final filter = FilterPipeline();
      final matches = filter.matchesProjectPattern(
        context.fsFolder,
        cmdArgs.projectPatterns,
        executionRoot: traversalInfo.executionRoot,
      );
      if (!matches) return false;
    }

    if (cmdArgs.excludePatterns.isNotEmpty) {
      final filter = FilterPipeline();
      final excluded = filter.matchesProjectPattern(
        context.fsFolder,
        cmdArgs.excludePatterns,
        executionRoot: traversalInfo.executionRoot,
      );
      if (excluded) return false;
    }

    return true;
  }

  bool _contextMatchesCommandNatures(
    CommandContext context,
    CommandDefinition cmd,
  ) {
    final reqNatures = cmd.requiredNatures;
    final workNatures = cmd.worksWithNatures;
    final hasRequired = reqNatures != null && reqNatures.isNotEmpty;
    final hasWorksWith = workNatures.isNotEmpty;
    if (!hasRequired && !hasWorksWith) return false;

    if (hasRequired) {
      return reqNatures.every(
        (type) => BuildBase.matchesNature(context.natures, type),
      );
    }

    return workNatures.any(
      (type) => BuildBase.matchesNature(context.natures, type),
    );
  }

  Future<ToolResult?> _tryRunPipelineInvocation(CliArgs cliArgs) async {
    if (cliArgs.commands.isNotEmpty) return null;
    if (cliArgs.positionalArgs.isEmpty) return null;

    final candidateName = cliArgs.positionalArgs.first;
    if (candidateName.startsWith('-') || candidateName == 'help') return null;

    final ToolPipelineConfig? loaded;
    try {
      loaded = ToolPipelineConfigLoader.load(tool: _effectiveTool);
    } on FormatException catch (error) {
      // A malformed pipeline command (e.g. an unprefixed, unknown command such
      // as "rm -rf /") is a security rejection, not a crash: surface it on
      // stdout with a non-zero exit instead of letting the exception escape to
      // stderr as an unhandled error.
      output.writeln('Error: ${error.message}');
      return const ToolResult.failure('Invalid pipeline command');
    }
    if (loaded == null || !loaded.hasPipelines) return null;

    final definition = loaded.pipelines[candidateName];
    if (definition == null) return null;

    if (_listOnly) {
      output.writeln('Pipeline $candidateName: not run (--list)');
      for (final (phase, steps) in [
        ('precore', definition.precore),
        ('core', definition.core),
        ('postcore', definition.postcore),
      ]) {
        for (final step in steps) {
          for (final command in step.commands) {
            output.writeln('  $phase: ${command.raw}');
          }
        }
      }
      return const ToolResult.success();
    }

    final executor = ToolPipelineExecutor(
      tool: _effectiveTool,
      output: output,
      verbose: verbose,
    );

    final ok = await executor.executeInvocation(
      pipelineName: candidateName,
      config: loaded,
      cliArgs: cliArgs,
    );

    if (!ok) {
      return const ToolResult.failure('Pipeline execution failed');
    }
    return const ToolResult.success();
  }

  /// Run a specific command.
  Future<ToolResult> _runCommand(String cmdName, CliArgs cliArgs) async {
    if (_listOnly &&
        _macroDefineCommands.contains(cmdName) &&
        _effectiveTool.mode == ToolMode.multiCommand) {
      output.writeln(
        ':$cmdName works on ${_effectiveTool.name}_master.yaml, not on '
        'projects: not run (--list)',
      );
      return const ToolResult.success();
    }
    final builtIn = _tryHandleBuiltInMacroDefineCommand(cmdName, cliArgs);
    if (builtIn != null) {
      return builtIn;
    }

    final cmd = _effectiveTool.findCommand(cmdName);
    if (cmd == null) {
      // Check if it's an ambiguous prefix
      final matches = _effectiveTool.findCommandsWithPrefix(cmdName);
      if (matches.length > 1) {
        errorOutput.writeln('Ambiguous command prefix ":$cmdName" matches:');
        for (final match in matches) {
          errorOutput.writeln('  :${match.name}');
        }
        return ToolResult.failure(
          'Ambiguous command prefix',
          exitCode: _effectiveTool.usageErrorExitCode,
        );
      }
      errorOutput.writeln('Unknown command: :$cmdName');
      return ToolResult.failure(
        'Unknown command: $cmdName',
        exitCode: _effectiveTool.usageErrorExitCode,
      );
    }

    // Use the actual command name for executor lookup and help
    final actualCmdName = cmd.name;

    // Check for per-command --help (check both original and resolved names)
    final cmdArgs =
        cliArgs.commandArgs[cmdName] ?? cliArgs.commandArgs[actualCmdName];
    if (cmdArgs != null && cmdArgs.options['help'] == true) {
      output.writeln(
        HelpGenerator.generateCommandHelp(cmd, tool: _effectiveTool),
      );
      return const ToolResult.success();
    }

    // Look up executor by actual command name (native or wired)
    final executor = _findExecutor(actualCmdName);
    if (executor == null) {
      return ToolResult.failure('No executor for command: $actualCmdName');
    }

    return _runWithTraversal(executor, cmd, cliArgs);
  }

  /// Every `--project` pattern that must pass the path guards.
  ///
  /// A `--project` placed *before* the command name lands in the global
  /// [CliArgs.projectPatterns]; one placed *after* a command name (e.g.
  /// `:dependencies --project _build/x`) lands in
  /// `commandArgs[cmd].projectPatterns`. Both forms select which projects the
  /// tool operates on, so both must be guarded — otherwise the per-command form
  /// silently no-ops on a mistyped or out-of-workspace path.
  List<String> _allProjectPatterns(CliArgs cliArgs) => [
    ...cliArgs.projectPatterns,
    for (final cmdArgs in cliArgs.commandArgs.values)
      ...cmdArgs.projectPatterns,
  ];

  /// Guard every `--project` path (global and per-command) against the
  /// workspace boundary and, for non-glob paths, existence.
  ///
  /// Within-root is validated before existence so the existence check only ever
  /// sees in-root absolute paths (as its contract documents). On the first
  /// offending pattern the error is written to [output] and returned; a return
  /// of null means every `--project` path is valid.
  String? _guardProjectPaths(CliArgs cliArgs, String executionRoot) {
    final patterns = _allProjectPatterns(cliArgs);

    final withinRootError = validateProjectPathsWithinRoot(
      patterns,
      executionRoot,
    );
    if (withinRootError != null) {
      output.writeln('Error: $withinRootError');
      return withinRootError;
    }

    final existsError = validateProjectPathsExist(patterns, executionRoot);
    if (existsError != null) {
      output.writeln('Error: $existsError');
      return existsError;
    }

    return null;
  }

  /// Turn `--project` selectors that matched nothing into a failure message.
  ///
  /// An unmatched selector yields an empty selection, and an empty selection
  /// executes nothing and would otherwise report success — so a mistyped
  /// selector and a finished job are indistinguishable from the outside. The
  /// message names both the selector and the root it was searched under, since
  /// the same selector is right or wrong depending on where the tool was
  /// pointed. Returns null when every selector matched something, or when
  /// [allowEmpty] (`--allow-empty`) opts out of the rule.
  String? _reportUnmatchedProjects(
    ProcessingResult result,
    BaseTraversalInfo traversalInfo, {
    required bool allowEmpty,
  }) {
    if (!result.hasUnmatchedSelectors || allowEmpty) return null;

    final scanRoot = traversalInfo is ProjectTraversalInfo
        ? traversalInfo.absoluteScanRoot
        : traversalInfo.executionRoot;
    final message = [
      if (result.unmatchedProjectPatterns.isNotEmpty)
        describeUnmatchedProjectPatterns(
          result.unmatchedProjectPatterns,
          scanRoot: scanRoot,
        ),
      if (result.unmatchedGroups.isNotEmpty)
        describeUnmatchedGroups(result.unmatchedGroups, scanRoot: scanRoot),
    ].join('\n');
    output.writeln('Error: $message');
    output.writeln('Use --allow-empty if matching nothing is intended.');
    return message;
  }

  /// Run executor with traversal.
  Future<ToolResult> _runWithTraversal(
    CommandExecutor executor,
    CommandDefinition? cmd,
    CliArgs cliArgs,
  ) async {
    // Get execution root: explicit path > workspace root (default)
    // Default behavior is --scan . -R --not-recursive (workspace mode)
    final String executionRoot;
    if (cliArgs.root != null) {
      // Explicit -R <path> was provided
      executionRoot = cliArgs.root!;
    } else {
      // Default: use workspace root (as if bare -R was passed)
      // Outside a workspace a tool runs on the directory it was started in.
      executionRoot =
          findWorkspaceRootOrNull(Directory.current.path) ??
          Directory.current.path;
    }

    // Reject any --project path (global *or* per-command) that is outside the
    // workspace or that names a non-glob path which does not exist, before any
    // scanning happens, so the tool never silently no-ops on such a path.
    final projectPathsError = _guardProjectPaths(cliArgs, executionRoot);
    if (projectPathsError != null) {
      return ToolResult.failure(projectPathsError);
    }

    // Load config defaults from buildkit_master.yaml navigation section
    final configDefaults = TraversalDefaults.load(executionRoot);

    // Build traversal info
    final supportsGit = cmd?.supportsGitTraversal ?? false;
    final requiresGit = cmd?.requiresGitTraversal ?? false;
    final gitModeSpecified = cliArgs.gitModeExplicitlySet;
    final defaultGitOrder = cmd?.defaultGitOrder;
    final BaseTraversalInfo traversalInfo;

    // Validate: user requested git but command doesn't support it
    if (!supportsGit && gitModeSpecified) {
      output.writeln('Error: This command does not support git traversal.');
      output.writeln('Remove -i/--inner-first-git or -o/--outer-first-git.');
      return const ToolResult.failure(
        'Git traversal not supported by this command',
      );
    }

    // Determine if we should use git traversal
    final useGitTraversal = requiresGit || (gitModeSpecified && supportsGit);

    if (useGitTraversal) {
      // Try git traversal (uses defaultGitOrder if -i/-o not specified)
      final gitInfo = cliArgs.toGitTraversalInfo(
        executionRoot: executionRoot,
        commandDefaultGitOrder: defaultGitOrder,
      );
      if (gitInfo == null) {
        // No -i/-o specified and no defaultGitOrder available
        output.writeln('Error: Git traversal mode required for this command.');
        output.writeln('Use --inner-first-git (-i) or --outer-first-git (-o).');
        return const ToolResult.failure(
          'Git traversal mode required but not specified',
        );
      }
      traversalInfo = gitInfo;
    } else {
      // Use project traversal (default)
      traversalInfo = cliArgs.toProjectTraversalInfo(
        executionRoot: executionRoot,
        configDefaults: configDefaults,
      );
    }

    // Security boundary: reject a --scan path outside the workspace before any
    // scanning happens. Only project traversal walks a --scan path; git
    // traversal uses the already-validated execution root.
    if (traversalInfo is ProjectTraversalInfo) {
      final scanPathError = validateScanRootsWithinRoot(
        traversalInfo.scanRoots,
        executionRoot,
      );
      if (scanPathError != null) {
        output.writeln('Error: $scanPathError');
        return ToolResult.failure(scanPathError);
      }
    }

    // Check if command requires traversal
    if (cmd != null && !cmd.requiresTraversal) {
      // Execute without traversal
      return executor.executeWithoutTraversal(cliArgs);
    }

    // Validate nature configuration — every traversal command must declare
    // its nature requirements. Use FsFolder to traverse all folders.
    // For singleCommand tools (cmd == null), fall back to tool-level natures.
    final reqNatures = cmd?.requiredNatures ?? _effectiveTool.requiredNatures;
    final workNatures =
        cmd?.worksWithNatures ??
        (cmd == null ? _effectiveTool.worksWithNatures : const <Type>{});
    final hasRequired = reqNatures != null && reqNatures.isNotEmpty;
    final hasWorksWith = workNatures.isNotEmpty;
    if (!hasRequired && !hasWorksWith) {
      final cmdLabel = cmd != null ? ' "${cmd.name}"' : '';
      output.writeln('Error: Command$cmdLabel has no nature configuration.');
      output.writeln(
        'Set requiredNatures or worksWithNatures '
        '(use FsFolder for all folders).',
      );
      return ToolResult.failure('Command$cmdLabel has no nature configuration');
    }

    // Load master defines once before traversal.
    // Merges default defines with mode-specific defines based on --modes.
    final masterDefines = _loadMasterDefines(cliArgs.modes);

    // Execute with traversal
    final results = <ItemResult>[];
    // A parallel command's projects run at once (--jobs); --list stays in
    // order, its stand-in only names each project.
    final pool = cmd != null && cmd.parallel && executor is! _ListingExecutor
        ? _poolFor(cmd, cliArgs)
        : null;
    final pending = <ItemResult?>[];

    final processingResult = await BuildBase.traverse(
      info: traversalInfo,
      verbose: verbose,
      requiredNatures: reqNatures,
      worksWithNatures: workNatures,
      // Per-command patterns are applied inside `run` rather than by the
      // filter pipeline, so they have to be handed to the audit explicitly.
      additionalProjectPatterns:
          cliArgs.commandArgs[cmd?.name]?.projectPatterns ?? const [],
      allowUnmatchedProjectPatterns: cliArgs.allowEmpty,
      run: (context) async {
        // Apply per-command filters for project traversal
        if (traversalInfo is ProjectTraversalInfo) {
          final cmdArgs = cliArgs.commandArgs[cmd?.name];
          if (cmdArgs != null) {
            // Check project patterns (ID → name → folder name glob → path)
            if (cmdArgs.projectPatterns.isNotEmpty) {
              final filter = FilterPipeline();
              final matches = filter.matchesProjectPattern(
                context.fsFolder,
                cmdArgs.projectPatterns,
                executionRoot: traversalInfo.executionRoot,
              );
              if (!matches) return true; // Skip, continue
            }
            // Check exclude patterns (ID → name → folder name glob → path)
            if (cmdArgs.excludePatterns.isNotEmpty) {
              final filter = FilterPipeline();
              final excluded = filter.matchesProjectPattern(
                context.fsFolder,
                cmdArgs.excludePatterns,
                executionRoot: traversalInfo.executionRoot,
              );
              if (excluded) return true; // Skip, continue
            }
          }
        }

        final header = verbose ? '>>> ${context.relativePath}' : null;
        // Show progress for folder being processed.
        if (pool == null && header != null) output.writeln(header);

        // Resolve %{...} placeholders in CLI args per folder.
        // Uses skipUnknown: true so command-specific placeholders (e.g.,
        // compiler's ${file}) are left for the executor's own resolver.
        final placeholderCtx = ExecutePlaceholderContext.fromCommandContext(
          context,
          executionRoot,
        );
        final placeholderResolvedArgs = cliArgs.withResolvedStrings(
          (s) => ExecutePlaceholderResolver.resolveCommand(
            s,
            placeholderCtx,
            skipUnknown: true,
          ),
        );

        // Resolve @[name] define placeholders per folder.
        // Merges master defines with per-project buildkit.yaml defines
        // (project overrides master).
        final projectDefines = _loadProjectDefines(
          context.fsFolder.path,
          masterDefines,
          cliArgs.modes,
        );
        final resolvedArgs = placeholderResolvedArgs.withResolvedStrings(
          (s) => _resolveDefineString(s, projectDefines),
        );

        Future<ItemResult> work() => _executeItemGuarded(
          context: context,
          commandName: cmd?.name ?? 'default',
          action: () => executor.execute(context, resolvedArgs),
        );
        if (pool == null) {
          results.add(await work());
        } else {
          final slot = pending.length;
          pending.add(null);
          pool.add(() async {
            pending[slot] = await _heldOutput((out) {
              if (header != null) out.writeln(header);
              return work();
            });
          });
        }
        return true; // Continue to next
      },
    );
    if (pool != null) {
      await pool.drain();
      results.addAll(pending.whereType<ItemResult>());
    }

    final unmatchedError = _reportUnmatchedProjects(
      processingResult,
      traversalInfo,
      allowEmpty: cliArgs.allowEmpty,
    );
    if (unmatchedError != null) return ToolResult.failure(unmatchedError);

    final extra = await _afterTraversal(
      executor,
      cmd?.name ?? 'default',
      results,
      cliArgs,
    );
    if (extra != null) results.add(extra);
    results.addAll(await _runInNestedWorkspaces(processingResult, cliArgs));

    return ToolResult.fromItems(results);
  }

  /// Run in nested mode: skip wiring, skip traversal, execute in cwd.
  ///
  /// Used when a host tool invokes this tool with `--nested`. The tool
  /// runs its command directly in the current working directory without
  /// any project traversal or nested tool wiring.
  Future<ToolResult> _runNestedMode(CliArgs cliArgs) async {
    // `--nested help <command>`: how a host asks a nested tool for the help
    // of a wired command (see _delegateNestedHelp).
    if (cliArgs.positionalArgs.firstOrNull == 'help') {
      final topic = _bareHelpName(cliArgs);
      if (topic == null) {
        output.writeln(HelpGenerator.generateToolHelp(tool));
        return const ToolResult.success();
      }
      final name = topic.startsWith(':') ? topic.substring(1) : topic;
      final cmd = name.isEmpty ? null : tool.findCommand(name);
      if (cmd != null) {
        output.writeln(HelpGenerator.generateCommandHelp(cmd, tool: tool));
        return const ToolResult.success();
      }
      final topicDef = topic.startsWith(':') ? null : tool.findHelpTopic(name);
      if (topicDef != null) {
        output.writeln(HelpGenerator.generateTopicHelp(topicDef, tool: tool));
        return const ToolResult.success();
      }
      output.writeln('Unknown help topic: $topic');
      return const ToolResult.failure('Unknown help topic');
    }

    // Handle help in nested mode
    if (cliArgs.help) {
      if (cliArgs.commands.isNotEmpty) {
        final cmdName = cliArgs.commands.first;
        final cmd = tool.findCommand(cmdName);
        if (cmd != null) {
          output.writeln(HelpGenerator.generateCommandHelp(cmd, tool: tool));
          return const ToolResult.success();
        }
      }
      output.writeln(HelpGenerator.generateToolHelp(tool));
      return const ToolResult.success();
    }

    // Handle version
    if (cliArgs.version) {
      output.writeln('${tool.name} v${tool.version}');
      return const ToolResult.success();
    }

    // Multi-command: route to single command
    if (tool.mode == ToolMode.multiCommand) {
      if (cliArgs.commands.isEmpty) {
        if (tool.defaultCommand != null) {
          return _runNestedCommand(tool.defaultCommand!, cliArgs);
        }
        return const ToolResult.failure('No command specified in nested mode');
      }
      // In nested mode, only one command at a time
      return _runNestedCommand(cliArgs.commands.first, cliArgs);
    }

    // Single command: nested mode skips traversal, so run the default
    // executor's non-traversal entry point.
    final executor = _listing(executors['default'], 'default');
    if (executor == null) {
      return const ToolResult.failure('No default executor configured');
    }
    return executor.executeWithoutTraversal(cliArgs);
  }

  /// Run a single command in nested mode (no traversal).
  Future<ToolResult> _runNestedCommand(String cmdName, CliArgs cliArgs) async {
    final cmd = tool.findCommand(cmdName);
    if (cmd == null) {
      return ToolResult.failure('Unknown command in nested mode: $cmdName');
    }

    final executor = _listing(executors[cmd.name], cmd.name);
    if (executor == null) {
      return ToolResult.failure('No executor for command: ${cmd.name}');
    }
    // Nested mode means the host tool has already traversed and invoked us per
    // project. Commands that don't require traversal run via
    // executeWithoutTraversal — consistent with the non-nested path (see the
    // `!cmd.requiresTraversal` branch in the main run flow). Only commands that
    // genuinely require per-folder logic fall through to a cwd-scoped execute.
    if (!cmd.requiresTraversal) {
      return executor.executeWithoutTraversal(cliArgs);
    }
    return _executeNestedInCwd(executor, cliArgs);
  }

  /// Execute a command executor against the current working directory (no
  /// traversal).
  ///
  /// Used for nested commands that require traversal: the host tool has already
  /// traversed to the project directory, so this runs the executor's per-folder
  /// [CommandExecutor.execute] logic once, with a [CommandContext] built from
  /// the current working directory.
  Future<ToolResult> _executeNestedInCwd(
    CommandExecutor executor,
    CliArgs cliArgs,
  ) async {
    final cwd = Directory.current.path;
    final context = CommandContext(
      fsFolder: FsFolder(path: cwd),
      natures: const [],
      executionRoot: cwd,
    );
    final result = await executor.execute(context, cliArgs);
    final extra = await _afterTraversal(
      executor,
      cliArgs.commands.isEmpty ? 'default' : cliArgs.commands.first,
      [result],
      cliArgs,
    );
    return ToolResult.fromItems([result, ?extra]);
  }

  /// Lazy wire nested tools into the effective tool definition.
  ///
  /// Merges code-level [ToolDefinition.defaultIncludes] with YAML
  /// `nested_tools:` entries, then queries only the needed tools.
  /// Updates [_effectiveTool] and [executors] with wired commands.
  ///
  /// Returns `true` if wiring succeeded, `false` if a required binary
  /// was missing and execution should be aborted.
  Future<bool> _lazyWireNestedTools(CliArgs cliArgs) async {
    final workspaceRoot =
        findWorkspaceRootOrNull(Directory.current.path) ??
        Directory.current.path;
    final loader = WiringLoader(tool: tool);

    // Determine which commands are requested
    final Set<String>? requestedCommands;
    if (cliArgs.isHelpMode) {
      // Help mode: wire all tools, tolerate missing binaries
      requestedCommands = null;
    } else if (cliArgs.commands.isNotEmpty) {
      requestedCommands = cliArgs.commands.toSet();
    } else {
      // No commands specified — no nested tools needed
      return true;
    }

    final result = await loader.resolve(
      requestedCommands: requestedCommands,
      workspaceRoot: workspaceRoot,
      tolerateMissing: cliArgs.isHelpMode,
    );

    // Handle errors — abort if any requested nested tool binary is missing.
    // Since we only query binaries for commands the user actually requested,
    // any error here means the user's intended command cannot run.
    if (result.hasErrors) {
      output.writeln('Error: Missing required tool binaries:');
      for (final msg in result.errors) {
        output.writeln('  - $msg');
      }
      return false;
    }

    // Print warnings
    for (final warning in result.warnings) {
      if (verbose) {
        output.writeln('Warning: $warning');
      }
    }

    // Merge wired commands into the effective tool
    if (result.commands.isNotEmpty) {
      _effectiveTool = _effectiveTool.copyWith(
        commands: [..._effectiveTool.commands, ...result.commands],
      );
    }

    // Merge wired executors (mutable map)
    if (result.executors.isNotEmpty) {
      final mutableExecutors = Map<String, CommandExecutor>.from(executors);
      mutableExecutors.addAll(result.executors);
      // We can't reassign final executors, so we update _effectiveTool
      // and use a separate lookup. Actually, executors is final const.
      // Instead, we store the wired executors and check both maps.
      _wiredExecutors.addAll(result.executors);
    }

    return true;
  }

  /// Wired executors merged during lazy wiring.
  final Map<String, CommandExecutor> _wiredExecutors = {};

  /// `--list` was given: every executor is replaced by a [_ListingExecutor],
  /// so the run names what it would do and does none of it.
  bool _listOnly = false;

  /// Look up an executor by command name (checks both native and wired).
  CommandExecutor? _findExecutor(String cmdName) {
    return _listing(executors[cmdName] ?? _wiredExecutors[cmdName], cmdName);
  }

  /// [executor] itself, or under `--list` the stand-in that runs nothing
  /// (unless the executor has its own read-only list mode).
  CommandExecutor? _listing(CommandExecutor? executor, String commandName) {
    if (executor == null || !_listOnly || executor.handlesListMode) {
      return executor;
    }
    return _ListingExecutor(_listingLabel(commandName), output);
  }

  /// How a `--list` line names what would run: `:<command>` for a command;
  /// the tool's name for a single-command tool's `default` executor, a key
  /// the user never types.
  String _listingLabel(String commandName) {
    final isDefaultExecutor =
        commandName == 'default' &&
        (_effectiveTool.mode == ToolMode.singleCommand ||
            _effectiveTool.findCommand('default')?.name != 'default');
    return isDefaultExecutor ? _effectiveTool.name : ':$commandName';
  }

  /// `--list` without a command: the commands and the pipelines.
  ToolResult _listCommandsAndPipelines() {
    output.writeln('Commands:');
    for (final cmd in _effectiveTool.commands.where((c) => !c.hidden)) {
      output.writeln('  :${cmd.name.padRight(18)} ${cmd.description}');
    }
    ToolPipelineConfig? loaded;
    try {
      loaded = ToolPipelineConfigLoader.load(tool: _effectiveTool);
    } on FormatException {
      loaded = null;
    }
    final pipelines = loaded?.pipelines ?? const {};
    if (pipelines.isNotEmpty) {
      output.writeln('Pipelines:');
      for (final name in pipelines.keys) {
        output.writeln('  $name');
      }
    }
    output.writeln(
      'With a command, --list names the projects it would run on and runs '
      'nothing.',
    );
    return const ToolResult.success();
  }

  /// Handle `--completion <shell>`: print a shell completion script.
  ///
  /// Intercepted early (alongside `--dump-definitions`, before lazy wiring), so
  /// it emits from the tool's own command/option definitions. Returns a failure
  /// (non-zero exit) for an unknown shell so automation can distinguish a bad
  /// request from a successful emission.
  ToolResult _handleCompletion(String shellName) {
    final shell = switch (shellName.toLowerCase()) {
      'bash' => ShellType.bash,
      'zsh' => ShellType.zsh,
      'fish' => ShellType.fish,
      _ => null,
    };
    if (shell == null) {
      output.writeln(
        "Error: unknown shell '$shellName' for --completion. "
        'Supported shells: bash, zsh, fish.',
      );
      return const ToolResult.failure('Unknown completion shell');
    }
    output.write(tool.generateCompletion(shell));
    return const ToolResult.success();
  }

  /// Handle help display with wired commands included.
  /// The name a bare `help` asks about: the word after it (`help compiler`,
  /// `help pipelines`), or the command the parser took from `help :compiler`
  /// (returned with its colon). Null for `help` alone.
  static String? _bareHelpName(CliArgs cliArgs) {
    final word = cliArgs.positionalArgs.skip(1).firstOrNull;
    if (word != null) return word;
    final command = cliArgs.commands.firstOrNull;
    return command == null ? null : ':$command';
  }

  /// The help of the tool's command [name] (its name, an alias or an
  /// unambiguous prefix), as `:<command> --help` prints it; a wired command's
  /// help comes from its nested tool. An ambiguous prefix lists the commands
  /// it matches. Null when [name] names no command.
  Future<ToolResult?> _commandHelp(String name, CliArgs cliArgs) async {
    if (name.isEmpty) return null;
    final cmd = _effectiveTool.findCommand(name);
    if (cmd != null) {
      final wiredExec = _wiredExecutors[cmd.name];
      if (wiredExec is NestedToolExecutor) {
        return _delegateNestedHelp(wiredExec, cliArgs);
      }
      output.writeln(
        HelpGenerator.generateCommandHelp(cmd, tool: _effectiveTool),
      );
      return const ToolResult.success();
    }
    final matches = _effectiveTool.findCommandsWithPrefix(name);
    if (matches.length > 1) {
      output.writeln('Ambiguous command prefix ":$name" matches:');
      for (final match in matches) {
        output.writeln('  :${match.name}');
      }
      return const ToolResult.failure('Ambiguous command prefix');
    }
    return null;
  }

  Future<ToolResult> _handleHelp(CliArgs cliArgs) async {
    if (cliArgs.commands.isNotEmpty) {
      final cmdName = cliArgs.commands.first;
      final builtInHelp = _tryHandleBuiltInMacroDefineHelp(cmdName);
      if (builtInHelp != null) {
        output.writeln(builtInHelp);
        return const ToolResult.success();
      }
      final commandHelp = await _commandHelp(cmdName, cliArgs);
      if (commandHelp != null) return commandHelp;
      // Check help topics before giving up
      final topic = _effectiveTool.findHelpTopic(cmdName);
      if (topic != null) {
        output.writeln(
          HelpGenerator.generateTopicHelp(topic, tool: _effectiveTool),
        );
        return const ToolResult.success();
      }
      errorOutput.writeln('Unknown command: :$cmdName');
      return ToolResult.failure(
        'Unknown command',
        exitCode: _effectiveTool.usageErrorExitCode,
      );
    }
    final baseHelp = HelpGenerator.generateToolHelp(
      _effectiveTool,
      nestedCommandNames: _wiredExecutors.keys.toSet(),
    );
    output.write(baseHelp);
    final appendix = _builtInMacroDefineHelpAppendix();
    if (appendix != null) {
      output.writeln();
      output.writeln(appendix);
    }
    return const ToolResult.success();
  }

  /// Known built-in macro/define command names.
  static const _macroDefineCommands = {
    'macro',
    'macros',
    'unmacro',
    'define',
    'defines',
    'undefine',
  };

  ToolResult? _tryHandleBuiltInMacroDefineCommand(
    String cmdName,
    CliArgs cliArgs,
  ) {
    if (!_macroDefineCommands.contains(cmdName)) return null;
    if (_effectiveTool.mode != ToolMode.multiCommand) return null;

    // Command matches but master yaml may be missing.
    final masterMissing = _checkMasterYamlMissing();
    if (masterMissing != null) return masterMissing;

    switch (cmdName) {
      case 'macro':
        return _handleRuntimeMacroDefine(cliArgs);
      case 'macros':
        return _handleRuntimeMacroList();
      case 'unmacro':
        return _handleRuntimeMacroRemove(cliArgs);
      case 'define':
        return _handlePersistentDefineAdd(cliArgs);
      case 'defines':
        return _handlePersistentDefineList();
      case 'undefine':
        return _handlePersistentDefineRemove(cliArgs);
      default:
        return null;
    }
  }

  String? _tryHandleBuiltInMacroDefineHelp(String cmdName) {
    if (!_macroDefineCommands.contains(cmdName)) return null;
    // 'defines' and 'macros' are handled as comprehensive help topics now.
    if (cmdName == 'defines' || cmdName == 'macros') return null;
    if (_effectiveTool.mode != ToolMode.multiCommand) return null;
    // Show help text even if master file is missing — the user may need
    // the help to understand how to set things up.

    switch (cmdName) {
      case 'macro':
        return 'Command: :macro\nDefine a runtime macro for this tool run.\nUsage: ${tool.name} :macro name=value';
      case 'macros':
        return 'Command: :macros\nList runtime macros for this tool run.\nUsage: ${tool.name} :macros';
      case 'unmacro':
        return 'Command: :unmacro\nRemove a runtime macro.\nUsage: ${tool.name} :unmacro name';
      case 'define':
        return '''Command: :define
Persist a define in ${tool.name}_master.yaml under the ${tool.name}: section.
Usage: ${tool.name} :define [-m MODE] name=value
Options:
  -m MODE  Store as mode-specific define (e.g., DEV-defines:)''';
      case 'defines':
        return '''Command: :defines
List all persisted defines from ${tool.name}_master.yaml.
Shows both default defines and mode-specific defines (DEV-defines:, CI-defines:, etc.)
Usage: ${tool.name} :defines''';
      case 'undefine':
        return '''Command: :undefine
Remove a persisted define from ${tool.name}_master.yaml.
Usage: ${tool.name} :undefine [-m MODE] name
Options:
  -m MODE  Remove from mode-specific defines (e.g., DEV-defines:)''';
      default:
        return null;
    }
  }

  String? _builtInMacroDefineHelpAppendix() {
    if (_effectiveTool.mode != ToolMode.multiCommand) return null;
    // Only advertise macros/defines/pipelines when the tool is in an eligible
    // context (a `<tool>_master.yaml` exists in the workspace). Without it
    // these features are unavailable, so listing them in --help is misleading.
    if (!_isMacroDefineFeatureEligible()) return null;
    return '''<magenta>**Runtime Macros**</magenta>
  :macro <name>=<value>      Add runtime macro
  :macros                    List runtime macros
  :unmacro <name>            Remove runtime macro

<magenta>**Persistent Defines**</magenta>
  :define [-m MODE] <name>=<value>  Add define (use -m for mode-specific)
  :defines                          List all defines (default and mode-specific)
  :undefine [-m MODE] <name>        Remove define (use -m for mode-specific)

<cyan>**Help Topics**</cyan>
  Run `${tool.name} help <topic>` for detailed information:
    defines         Persistent key-value defines in master and project YAML
    macros          Runtime command-line macros with argument substitution
    pipelines       Multi-step pipeline configuration in master YAML
    placeholders    Placeholder types and resolution in YAML config files
    wiring          Nested tool integration via master YAML configuration
''';
  }

  bool _isMacroDefineFeatureEligible() {
    return ToolPipelineConfigLoader.isEligible(
      tool: _effectiveTool,
      fromDirectory: Directory.current.path,
    );
  }

  /// Returns an error [ToolResult] when the master yaml cannot be found,
  /// or `null` when the file exists and everything is fine.
  ToolResult? _checkMasterYamlMissing() {
    if (_isMacroDefineFeatureEligible()) return null;
    final wsRoot = findWorkspaceRootOrNull(Directory.current.path);
    final expected = '${_effectiveTool.name}_master.yaml';
    final where = wsRoot == null
        ? 'Not inside a workspace: no $kBuildkitMasterYaml above '
              '${Directory.current.path}.'
        : 'Cannot find $expected in workspace root ($wsRoot).';
    output.writeln(
      '$where\n'
      'Make sure you are running ${_effectiveTool.name} from inside the '
      'workspace that contains $expected.',
    );
    return ToolResult.failure('$expected not found');
  }

  /// Auto-inject built-in help topics for multiCommand tools.
  ///
  /// Adds topics from [masterYamlHelpTopics] that are not already present
  /// in the tool's [helpTopics]. This ensures all multiCommand tools
  /// automatically expose help for defines, macros, pipelines, and wiring.
  void _injectMasterYamlHelpTopics() {
    final existing = _effectiveTool.helpTopics.map((t) => t.name).toSet();
    final toAdd = masterYamlHelpTopics
        .where((t) => !existing.contains(t.name))
        .toList();
    if (toAdd.isNotEmpty) {
      _effectiveTool = _effectiveTool.copyWith(
        helpTopics: [..._effectiveTool.helpTopics, ...toAdd],
      );
    }
  }

  ToolResult _handleRuntimeMacroDefine(CliArgs cliArgs) {
    final parsed = _parseNameValueArg(cliArgs);
    if (parsed == null) {
      return const ToolResult.failure('Missing argument: name=value');
    }

    final (name, value) = parsed;
    _loadPersistedMacros();
    _runtimeMacros[name] = value;
    _savePersistedMacros();
    output.writeln('Added macro: $name: $value');
    return const ToolResult.success(processedCount: 1);
  }

  ToolResult _handleRuntimeMacroList() {
    _loadPersistedMacros();
    if (_runtimeMacros.isEmpty) {
      output.writeln('No macros defined.');
      return const ToolResult.success();
    }

    final keys = _runtimeMacros.keys.toList()..sort();
    for (final key in keys) {
      output.writeln('$key=${_runtimeMacros[key]}');
    }
    return const ToolResult.success(processedCount: 1);
  }

  ToolResult _handleRuntimeMacroRemove(CliArgs cliArgs) {
    final name = cliArgs.positionalArgs.isEmpty
        ? ''
        : cliArgs.positionalArgs.first.trim();
    if (name.isEmpty) {
      return const ToolResult.failure('Missing argument: macro name');
    }

    _loadPersistedMacros();
    final removed = _runtimeMacros.remove(name);
    if (removed == null) {
      return ToolResult.failure('Macro not found: $name');
    }

    _savePersistedMacros();
    output.writeln('Removed macro: $name : $removed');
    return const ToolResult.success(processedCount: 1);
  }

  /// Loads persisted macros from the `macros:` section of master.yaml into
  /// [_runtimeMacros]. A no-op if already loaded this invocation or if the
  /// section does not exist.
  ///
  /// Also performs one-time migration from legacy `{tool}_macros.yaml` file:
  /// if found, its contents are merged into master.yaml and the file is deleted.
  void _loadPersistedMacros() {
    if (_macrosLoaded) return;
    _macrosLoaded = true;

    try {
      final doc = _readMasterYaml();
      if (doc == null) return;
      final macros = doc['macros'];
      if (macros is! Map) return;
      for (final entry in macros.entries) {
        final k = entry.key?.toString();
        final v = entry.value?.toString();
        if (k != null && k.isNotEmpty && v != null) {
          _runtimeMacros[k] = v;
        }
      }
    } catch (_) {
      // Corrupt file — silently ignore; macros start empty this invocation.
    }
  }

  /// Writes [_runtimeMacros] to the `macros:` section of master.yaml.
  ///
  /// If [_runtimeMacros] is empty the `macros:` section is removed.
  void _savePersistedMacros() {
    _withMasterYaml((doc) {
      if (_runtimeMacros.isEmpty) {
        doc.remove('macros');
        return;
      }

      // Sort entries for deterministic output.
      final sorted = Map<String, String>.fromEntries(
        _runtimeMacros.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
      doc['macros'] = sorted;
    });
  }

  /// Parse mode flag from CLI args.
  ///
  /// Supports `-m MODE` or `--mode MODE` flags.
  /// Returns (mode, remaining args) or (null, original args).
  (String?, List<String>) _parseModeFlag(List<String> args) {
    final result = <String>[];
    String? mode;
    var i = 0;
    while (i < args.length) {
      final arg = args[i];
      if ((arg == '-m' || arg == '--mode') && i + 1 < args.length) {
        mode = args[i + 1];
        i += 2;
      } else {
        result.add(arg);
        i++;
      }
    }
    return (mode, result);
  }

  ToolResult _handlePersistentDefineAdd(CliArgs cliArgs) {
    // Parse optional -m MODE flag
    final (mode, remainingArgs) = _parseModeFlag(cliArgs.positionalArgs);

    // Parse name=value from remaining args
    final parsed = _parseNameValueFromList(remainingArgs);
    if (parsed == null) {
      return const ToolResult.failure('Missing argument: name=value');
    }
    final (name, value) = parsed;

    final result = _withMasterYaml((doc) {
      // Ensure tool section exists
      final toolSection = _ensureToolSection(doc);

      // Determine the key: 'defines' or '{MODE}-defines'
      final definesKey = mode != null ? '$mode-defines' : 'defines';

      // Read or create defines map
      final defines = _readToolDefines(toolSection, definesKey);
      defines[name] = value;

      // Sort and store
      final sorted = Map<String, String>.fromEntries(
        defines.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
      toolSection[definesKey] = sorted;
    });
    if (result != null) return result;

    final modePrefix = mode != null ? ' ($mode mode)' : '';
    output.writeln('Added define$modePrefix: $name: $value');
    return const ToolResult.success(processedCount: 1);
  }

  ToolResult _handlePersistentDefineList() {
    final doc = _readMasterYaml();
    if (doc == null) {
      output.writeln('No defines found.');
      return const ToolResult.success();
    }

    final toolSection = doc[tool.name] as Map<String, dynamic>? ?? {};
    final allDefines = <String, Map<String, String>>{};

    // Collect default defines
    final defaultDefines = _readToolDefines(toolSection, 'defines');
    if (defaultDefines.isNotEmpty) {
      allDefines['defines'] = defaultDefines;
    }

    // Collect mode-specific defines (keys ending with '-defines')
    for (final key in toolSection.keys) {
      final keyStr = key.toString();
      if (keyStr.endsWith('-defines') && keyStr != 'defines') {
        final modeDefines = _readToolDefines(toolSection, keyStr);
        if (modeDefines.isNotEmpty) {
          allDefines[keyStr] = modeDefines;
        }
      }
    }

    if (allDefines.isEmpty) {
      output.writeln('No defines found.');
      return const ToolResult.success();
    }

    // Print default defines first
    if (allDefines.containsKey('defines')) {
      output.writeln('defines:');
      final keys = allDefines['defines']!.keys.toList()..sort();
      for (final key in keys) {
        output.writeln('  $key=${allDefines['defines']![key]}');
      }
    }

    // Print mode-specific defines sorted by key
    final modeKeys = allDefines.keys.where((k) => k != 'defines').toList()
      ..sort();
    for (final modeKey in modeKeys) {
      output.writeln('$modeKey:');
      final keys = allDefines[modeKey]!.keys.toList()..sort();
      for (final key in keys) {
        output.writeln('  $key=${allDefines[modeKey]![key]}');
      }
    }

    return const ToolResult.success(processedCount: 1);
  }

  ToolResult _handlePersistentDefineRemove(CliArgs cliArgs) {
    // Parse optional -m MODE flag
    final (mode, remainingArgs) = _parseModeFlag(cliArgs.positionalArgs);

    final name = remainingArgs.isEmpty ? '' : remainingArgs.first.trim();
    if (name.isEmpty) {
      return const ToolResult.failure('Missing argument: define name');
    }

    String? removedValue;
    final result = _withMasterYaml((doc) {
      final toolSection = doc[tool.name] as Map<String, dynamic>?;
      if (toolSection == null) return;

      // Determine the key: 'defines' or '{MODE}-defines'
      final definesKey = mode != null ? '$mode-defines' : 'defines';

      final defines = _readToolDefines(toolSection, definesKey);
      removedValue = defines.remove(name);

      if (removedValue == null) return;

      final sorted = Map<String, String>.fromEntries(
        defines.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
      if (sorted.isEmpty) {
        toolSection.remove(definesKey);
        // Clean up empty tool section
        if (toolSection.isEmpty) {
          doc.remove(tool.name);
        }
      } else {
        toolSection[definesKey] = sorted;
      }
    });
    if (result != null) return result;

    if (removedValue == null) {
      final modePrefix = mode != null ? ' in $mode mode' : '';
      return ToolResult.failure('Define not found$modePrefix: $name');
    }

    final modePrefix = mode != null ? ' ($mode mode)' : '';
    output.writeln('Removed define$modePrefix: $name : $removedValue');
    return const ToolResult.success(processedCount: 1);
  }

  (String, String)? _parseNameValueArg(CliArgs cliArgs) {
    return _parseNameValueFromList(cliArgs.positionalArgs);
  }

  /// Parses a name=value pair from a list of arguments.
  ///
  /// The first argument should contain `name=value`, with subsequent
  /// arguments being concatenated as part of the value.
  (String, String)? _parseNameValueFromList(List<String> args) {
    if (args.isEmpty) return null;
    final first = args.first;
    final eqIndex = first.indexOf('=');
    if (eqIndex <= 0) return null;
    final name = first.substring(0, eqIndex).trim();
    final tail = <String>[first.substring(eqIndex + 1), ...args.skip(1)];
    final value = tail.join(' ').trim();
    if (name.isEmpty || value.isEmpty) return null;
    return (name, value);
  }

  Map<String, dynamic>? _readMasterYaml() {
    final wsRoot = findWorkspaceRootOrNull(Directory.current.path);
    if (wsRoot == null) return null;
    final path = '$wsRoot/${tool.name}_master.yaml';
    final file = File(path);
    if (!file.existsSync()) return null;

    final parsed = loadYaml(file.readAsStringSync());
    if (parsed is! YamlMap) return null;
    return _deepToDart(parsed) as Map<String, dynamic>;
  }

  ToolResult? _withMasterYaml(void Function(Map<String, dynamic> doc) mutate) {
    final wsRoot = findWorkspaceRootOrNull(Directory.current.path);
    if (wsRoot == null) {
      return const ToolResult.failure(
        'Not inside a workspace (no $kBuildkitMasterYaml found)',
      );
    }
    final path = '$wsRoot/${tool.name}_master.yaml';
    final file = File(path);
    if (!file.existsSync()) {
      return const ToolResult.failure('Tool master yaml not found');
    }

    final doc = _readMasterYaml();
    final before = _readMasterYaml();
    if (doc == null || before == null) {
      return const ToolResult.failure('Unable to parse tool master yaml');
    }

    mutate(doc);
    // Only what [mutate] changed is written, through yaml_edit: the file's
    // comments, its schema line and every other entry stay as they are.
    final editor = YamlEditor(file.readAsStringSync());
    _applyMasterEdits(editor, const [], before, doc);
    final edited = editor.toString();
    if (edited != file.readAsStringSync()) file.writeAsStringSync(edited);
    return null;
  }

  /// Turns [before] into [after] at [path] of [editor]: removed keys are
  /// removed, maps on both sides are edited key by key, any other changed
  /// value is written whole.
  void _applyMasterEdits(
    YamlEditor editor,
    List<Object> path,
    Map<dynamic, dynamic> before,
    Map<dynamic, dynamic> after,
  ) {
    for (final key in before.keys) {
      if (!after.containsKey(key)) editor.remove([...path, key as Object]);
    }
    for (final MapEntry(:key, :value) in after.entries) {
      final keyPath = [...path, key as Object];
      if (!before.containsKey(key)) {
        editor.update(keyPath, value);
        continue;
      }
      final old = before[key];
      if (old is Map && value is Map) {
        _applyMasterEdits(editor, keyPath, old, value);
      } else if (!_sameYamlValue(old, value)) {
        editor.update(keyPath, value);
      }
    }
  }

  static bool _sameYamlValue(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _sameYamlValue(a[k], b[k]));
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameYamlValue(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  /// Ensures the tool-specific section exists in the document.
  ///
  /// Returns the existing or newly created section.
  Map<String, dynamic> _ensureToolSection(Map<String, dynamic> doc) {
    final existing = doc[tool.name];
    if (existing is Map<String, dynamic>) return existing;
    if (existing is Map) {
      final converted = Map<String, dynamic>.from(existing);
      doc[tool.name] = converted;
      return converted;
    }
    final newSection = <String, dynamic>{};
    doc[tool.name] = newSection;
    return newSection;
  }

  /// Reads defines from a specific key within the tool section.
  ///
  /// The key can be 'defines' or '{MODE}-defines'.
  Map<String, String> _readToolDefines(
    Map<String, dynamic> toolSection,
    String key,
  ) {
    final raw = toolSection[key];
    if (raw is! Map) return <String, String>{};
    final result = <String, String>{};
    for (final entry in raw.entries) {
      result[entry.key.toString()] = entry.value.toString();
    }
    return result;
  }

  /// Regex for `@[name]` define placeholders.
  static final _definePlaceholderPattern = RegExp(
    r'@\[([a-zA-Z_][a-zA-Z0-9_-]*)\]',
  );

  /// Load defines from the master yaml, merging default + mode-specific.
  ///
  /// Reads the tool section's `defines:` key, then overlays any
  /// `{MODE}-defines:` sections for the given [modes].
  /// Returns an empty map if no master yaml or no defines exist.
  Map<String, String> _loadMasterDefines(List<String> modes) {
    final doc = _readMasterYaml();
    if (doc == null) return const {};

    final toolSection = doc[tool.name] as Map<String, dynamic>? ?? {};
    final defines = _readToolDefines(toolSection, 'defines');

    // Overlay mode-specific defines (later modes override earlier ones)
    for (final mode in modes) {
      final modeDefines = _readToolDefines(toolSection, '$mode-defines');
      defines.addAll(modeDefines);
    }

    return _resolveDefineChain(defines);
  }

  /// Load defines for a specific project folder, merged with master defines.
  ///
  /// Reads `buildkit.yaml` (or `{tool.name}.yaml`) in [projectPath],
  /// extracts `defines:` and `{tool.name}: defines:`, and overlays
  /// mode-specific sections. Project defines override [masterDefines].
  Map<String, String> _loadProjectDefines(
    String projectPath,
    Map<String, String> masterDefines,
    List<String> modes,
  ) {
    final merged = Map<String, String>.from(masterDefines);

    final projectFile = File('$projectPath/buildkit.yaml');
    if (!projectFile.existsSync()) return merged;

    try {
      final parsed = loadYaml(projectFile.readAsStringSync());
      if (parsed is! YamlMap) return merged;
      final projectDoc = _deepToDart(parsed) as Map<String, dynamic>;

      // Extract from top-level defines:
      _mergeDefineSection(merged, projectDoc['defines']);
      // Extract from tool-specific section, e.g. buildkit: defines:
      final toolSection = projectDoc[tool.name] as Map<String, dynamic>? ?? {};
      _mergeDefineSection(merged, toolSection['defines']);

      // Overlay mode-specific defines from project
      for (final mode in modes) {
        _mergeDefineSection(merged, projectDoc['$mode-defines']);
        _mergeDefineSection(merged, toolSection['$mode-defines']);
      }
    } catch (_) {
      // Corrupt project yaml — silently use master defines only.
    }

    return _resolveDefineChain(merged);
  }

  /// Merge a defines section into [target].
  void _mergeDefineSection(Map<String, String> target, dynamic section) {
    if (section is! Map) return;
    for (final entry in section.entries) {
      target[entry.key.toString()] = entry.value.toString();
    }
  }

  /// Resolve `@[name]` define placeholders in a string.
  ///
  /// Unresolved placeholders are left as-is.
  String _resolveDefineString(String input, Map<String, String> defines) {
    if (defines.isEmpty) return input;
    return input.replaceAllMapped(_definePlaceholderPattern, (match) {
      final name = match.group(1)!;
      return defines[name] ?? match.group(0)!;
    });
  }

  /// Resolve defines that reference other defines.
  ///
  /// Supports chained references like `@[buildPath]/@[subdir]`
  /// with a maximum depth of 10.
  Map<String, String> _resolveDefineChain(Map<String, String> defines) {
    final resolved = <String, String>{};
    const maxDepth = 10;

    String resolveValue(String value, int depth) {
      if (depth > maxDepth) return value;
      return value.replaceAllMapped(_definePlaceholderPattern, (match) {
        final name = match.group(1)!;
        final replacement = defines[name];
        if (replacement != null) {
          return resolveValue(replacement, depth + 1);
        }
        return match.group(0)!;
      });
    }

    for (final entry in defines.entries) {
      resolved[entry.key] = resolveValue(entry.value, 0);
    }
    return resolved;
  }

  dynamic _deepToDart(dynamic value) {
    if (value is YamlMap) {
      final map = <String, dynamic>{};
      for (final entry in value.entries) {
        map[entry.key.toString()] = _deepToDart(entry.value);
      }
      return map;
    }
    if (value is YamlList) {
      return value.map(_deepToDart).toList();
    }
    return value;
  }

  /// Delegate help for a wired command to the nested tool.
  ///
  /// Calls the nested tool's help system for detailed command help.
  Future<ToolResult> _delegateNestedHelp(
    NestedToolExecutor executor,
    CliArgs cliArgs,
  ) async {
    final args = <String>['--nested'];
    if (executor.isStandalone) {
      args.add('--help');
    } else {
      args.addAll(['help', executor.nestedCommand ?? '']);
    }

    try {
      final result = await runBinary(
        executor.binary,
        args,
        Directory.current.path,
      );
      final stdout = result.stdout.toString().trim();
      if (stdout.isNotEmpty) {
        output.writeln(stdout);
      }
      final stderr = result.stderr.toString().trim();
      if (stderr.isNotEmpty) {
        output.writeln(stderr);
      }
      return const ToolResult.success();
    } catch (_) {
      output.writeln(
        'Command :${executor.hostCommandName} — '
        'binary ${executor.binary} not found.',
      );
      return const ToolResult.failure('Nested help unavailable');
    }
  }

  bool _isDoctorRequested(CliArgs cliArgs) {
    String normalize(String value) {
      final trimmed = value.trim();
      if (trimmed.startsWith(':')) return trimmed.substring(1);
      return trimmed;
    }

    if (cliArgs.commands.any((c) => normalize(c) == 'doctor')) return true;
    if (cliArgs.positionalArgs.any((p) => normalize(p) == 'doctor')) {
      return true;
    }
    return false;
  }

  /// Whether the run names commands, and every one of them declares
  /// `needsEnvironment: false` (it only reads the tree).
  bool _onlyCommandsWithoutEnvironment(CliArgs cliArgs) {
    if (cliArgs.commands.isEmpty) return false;
    for (final name in cliArgs.commands) {
      final command = tool.findCommand(name);
      if (command == null || command.needsEnvironment) return false;
    }
    return true;
  }

  bool _isRequiredEnvironmentCheckBypassed() {
    final raw = Platform.environment['TOM_BOOTSTRAP_ALLOW_MISSING_SETUP'];
    if (raw == null) return false;
    final normalized = raw.trim().toLowerCase();
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on';
  }

  void _printRequirementIssues(_RequirementCheckResult result) {
    if (result.warnings.isNotEmpty) {
      output.writeln('Environment warnings:');
      for (final warning in result.warnings) {
        output.writeln('  - $warning');
      }
    }
    if (result.errors.isEmpty) return;
    output.writeln('Installation requirements not met:');
    for (final error in result.errors) {
      output.writeln('  - $error');
    }
    final instructions = result.setupInstructions?.trim();
    final pipeline = result.setupPipeline;
    final hasInstructions = instructions != null && instructions.isNotEmpty;
    if (!hasInstructions && pipeline == null) return;
    output.writeln('How to fix:');
    if (hasInstructions) output.writeln('  $instructions');
    if (pipeline != null) {
      output.writeln(
        '  Run `${tool.name} $pipeline` to set up what is missing.',
      );
    }
  }

  _RequirementCheckResult _runRequiredEnvironmentChecks({
    required bool withVersionTests,
  }) {
    // A run started in a directory that no longer exists has no workspace
    // to check (its command reports the missing directory if it needs one).
    final String cwd;
    try {
      cwd = Directory.current.path;
    } on FileSystemException {
      return const _RequirementCheckResult();
    }
    final wsRoot = findWorkspaceRootOrNull(cwd);
    final requiredMap = wsRoot == null
        ? null
        : _loadRequiredEnvironmentSection(wsRoot);
    if (requiredMap == null) {
      return const _RequirementCheckResult();
    }

    final warnings = <String>[];
    final errors = <String>[];
    String? setupInstructions;
    String? setupPipeline;

    final setup = requiredMap['setup'];
    if (setup is YamlMap) {
      setupInstructions = setup['instructions']?.toString();
      final pipeline = setup['setup-pipeline']?.toString().trim();
      if (pipeline != null && pipeline.isNotEmpty) setupPipeline = pipeline;
    }
    final binaryPathRaw = requiredMap['binaryPath']?.toString().trim();
    final binaryPath = binaryPathRaw == null || binaryPathRaw.isEmpty
        ? null
        : _resolveEnvVars(binaryPathRaw);

    final envVars = requiredMap['env-variables'];
    if (envVars is List) {
      for (final item in envVars) {
        if (item is! YamlMap) continue;
        final name = item['name']?.toString();
        if (name == null || name.isEmpty) continue;
        final value = Platform.environment[name];
        if (value != null && value.isNotEmpty) continue;
        final err = item['error']?.toString();
        final warn = item['warning']?.toString();
        if (err != null && err.isNotEmpty) {
          errors.add(err);
        } else if (warn != null && warn.isNotEmpty) {
          warnings.add(warn);
        }
      }
    }

    final folders = requiredMap['folders'];
    if (folders is List) {
      for (final item in folders) {
        if (item is! YamlMap) continue;
        final pathRaw = item['path']?.toString();
        if (pathRaw == null || pathRaw.isEmpty) continue;
        final path = _resolveEnvVars(pathRaw);
        if (Directory(path).existsSync()) continue;
        final err = item['error']?.toString();
        final warn = item['warning']?.toString();
        final name = item['name']?.toString() ?? pathRaw;
        if (err != null && err.isNotEmpty) {
          errors.add(err);
        } else if (warn != null && warn.isNotEmpty) {
          warnings.add(warn);
        } else {
          warnings.add('$name folder missing: $path');
        }
      }
    }

    final binaries = requiredMap['binaries'];
    if (binaries is List) {
      for (final item in binaries) {
        if (item is! YamlMap) continue;
        final binary = item['binary']?.toString();
        if (binary == null || binary.isEmpty) continue;

        final versionConstraint = item['version-constraint']?.toString();
        String substituted(String text) => versionConstraint == null
            ? text
            : text.replaceAll('%{version-constraint}', versionConstraint);

        if (!_isBinaryAvailable(binary, binaryPath)) {
          final err = item['error']?.toString();
          final warn = item['warning']?.toString();
          if (err != null && err.isNotEmpty) {
            errors.add(substituted(err));
          } else if (warn != null && warn.isNotEmpty) {
            warnings.add(substituted(warn));
          } else {
            warnings.add('$binary is not installed or not in PATH');
          }
          continue;
        }

        if (!withVersionTests) continue;
        final versionTest = item['version-test']?.toString();
        if (versionTest == null || versionConstraint == null) continue;

        final detectedVersion = _runVersionCommand(versionTest);
        if (detectedVersion == null) continue;

        final ok = _satisfiesCaretConstraint(
          detectedVersion,
          versionConstraint,
        );
        if (!ok) {
          final versionError = item['version-error']?.toString();
          if (versionError != null && versionError.isNotEmpty) {
            errors.add(substituted(versionError));
          } else {
            errors.add(
              '$binary version $detectedVersion does not satisfy '
              '$versionConstraint',
            );
          }
        }
      }
    }

    return _RequirementCheckResult(
      warnings: warnings,
      errors: errors,
      setupInstructions: setupInstructions,
      setupPipeline: setupPipeline,
    );
  }

  YamlMap? _loadRequiredEnvironmentSection(String wsRoot) {
    final candidates = <String>['${tool.name}_master.yaml'];
    if (tool.name == 'buildkit' && !candidates.contains(kBuildkitMasterYaml)) {
      candidates.add(kBuildkitMasterYaml);
    }

    for (final fileName in candidates) {
      final file = File('$wsRoot/$fileName');
      if (!file.existsSync()) continue;
      try {
        final parsed = loadYaml(file.readAsStringSync());
        if (parsed is! YamlMap) continue;
        final required = parsed['required-environment'];
        if (required is YamlMap) return required;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String _resolveEnvVars(String input) {
    return input.replaceAllMapped(RegExp(r'\$\[?(\w+)\]?'), (m) {
      final name = m.group(1)!;
      final directValue = Platform.environment[name];
      if (directValue != null && directValue.isNotEmpty) {
        return directValue;
      }

      if (Platform.isWindows && name.toUpperCase() == 'HOME') {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null && userProfile.isNotEmpty) {
          return userProfile;
        }

        final homeDrive = Platform.environment['HOMEDRIVE'];
        final homePath = Platform.environment['HOMEPATH'];
        if (homeDrive != null &&
            homeDrive.isNotEmpty &&
            homePath != null &&
            homePath.isNotEmpty) {
          return '$homeDrive$homePath';
        }
      }

      return m.group(0)!;
    });
  }

  /// Whether [binary] is in [binaryPath] (the binaries layer: the folder
  /// itself or its `<os>-<arch>/` folder) or in a folder on PATH. Looked up
  /// in the file system, without starting a process: the check runs before
  /// every command.
  bool _isBinaryAvailable(String binary, String? binaryPath) {
    final names = <String>[binary];
    if (Platform.isWindows && !binary.contains('.')) {
      final extensions = (Platform.environment['PATHEXT'] ?? '.EXE;.BAT;.CMD')
          .split(';')
          .where((e) => e.isNotEmpty);
      names.addAll([for (final e in extensions) '$binary${e.toLowerCase()}']);
    }
    final dirs = <String>[
      if (binaryPath != null) ...[
        binaryPath,
        '$binaryPath${Platform.pathSeparator}${_platformFolder()}',
      ],
      ...(Platform.environment['PATH'] ?? '')
          .split(Platform.isWindows ? ';' : ':')
          .where((d) => d.isNotEmpty),
    ];
    for (final dir in dirs) {
      for (final name in names) {
        final candidate = '$dir${Platform.pathSeparator}$name';
        if (FileSystemEntity.typeSync(candidate) == FileSystemEntityType.file) {
          return true;
        }
        if (FileSystemEntity.isLinkSync(candidate) &&
            File(candidate).existsSync()) {
          return true;
        }
      }
    }
    return false;
  }

  /// The binaries layer's folder of this platform: `darwin-arm64`,
  /// `linux-x64`, `win32-x64`, ...
  static String _platformFolder() {
    final parts = Abi.current().toString().split('_');
    final os = switch (parts.first) {
      'macos' => 'darwin',
      'windows' => 'win32',
      final other => other,
    };
    return '$os-${parts.last}';
  }

  String? _runVersionCommand(String command) {
    try {
      final result = Platform.isWindows
          ? Process.runSync('cmd', ['/c', command], runInShell: true)
          : Process.runSync('/bin/bash', ['-lc', command], runInShell: true);
      final output = '${result.stdout ?? ''}\n${result.stderr ?? ''}'.trim();
      final match = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(output);
      if (match == null) return null;
      final major = match.group(1)!;
      final minor = match.group(2)!;
      final patch = match.group(3) ?? '0';
      return '$major.$minor.$patch';
    } catch (_) {
      return null;
    }
  }

  bool _satisfiesCaretConstraint(String version, String constraint) {
    if (!constraint.startsWith('^')) return true;
    final minV = _parseVersionInts(constraint.substring(1));
    final curV = _parseVersionInts(version);
    if (minV == null || curV == null) return true;

    if (curV[0] != minV[0]) return false;
    if (curV[1] < minV[1]) return false;
    if (curV[1] == minV[1] && curV[2] < minV[2]) return false;
    return true;
  }

  List<int>? _parseVersionInts(String input) {
    final m = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(input);
    if (m == null) return null;
    return [
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3) ?? '0'),
    ];
  }
}

/// Stands in for every executor under `--list`: names the project (or, for a
/// command without traversal, the command) and runs nothing. [label] is what
/// would run: `:<command>`, or a single-command tool's name.
class _ListingExecutor extends CommandExecutor {
  final String label;
  final StringSink output;

  _ListingExecutor(this.label, this.output);

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    output.writeln('${context.relativePath}  $label  not run (--list)');
    return ItemResult.success(
      path: context.path,
      name: context.name,
      message: 'not run (--list)',
    );
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    output.writeln(
      '$label runs once, without visiting projects: not run (--list)',
    );
    return const ToolResult.success();
  }
}

/// At most [size] tasks at once; [drain] waits for every task added.
class _JobPool {
  _JobPool(this.size);

  final int size;
  int _running = 0;
  final _waiting = <Completer<void>>[];
  final _tasks = <Future<void>>[];

  void add(Future<void> Function() task) => _tasks.add(_run(task));

  Future<void> _run(Future<void> Function() task) async {
    while (_running >= size) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    try {
      await task();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  Future<void> drain() => Future.wait(_tasks);
}

/// [args] for a run in a nested workspace (`-w`): without the scan roots
/// (`-s` / `--scan`), which name folders of this run; the nested run scans
/// from its own workspace.
List<String> argsForNestedWorkspace(List<String> args) {
  final result = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-s' || arg == '--scan') {
      i++; // and its value
      continue;
    }
    if (arg.startsWith('--scan=') || arg.startsWith('-s=')) continue;
    result.add(arg);
  }
  return result;
}
