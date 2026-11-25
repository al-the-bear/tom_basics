/// The executors of `:skill-build-binaries`, `:skill-build-all-binaries` and
/// `:skill-push-binaries`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../../platform_utils.dart';
import 'binaries_build.dart';
import 'binaries_push.dart';
import 'release_set.dart';

String _json(RunReport report, String key, Map<String, Object?> data) =>
    const JsonEncoder.withIndent('  ').convert({...report.toJson(), key: data});

ToolResult _result(String command, int code) => code == 0
    ? const ToolResult.success()
    : ToolResult.failure('$command: exit $code', exitCode: code);

/// `:skill-build-binaries` ([all] false) and `:skill-build-all-binaries`.
class SkillBuildBinariesExecutor extends CommandExecutor {
  SkillBuildBinariesExecutor({
    required this.all,
    this.out,
    this.now,
    this.buildkit,
    this.compileSelf,
    this.progress,
    this.platform,
  });

  final bool all;
  final StringSink? out;
  final DateTime? now;
  final BinBuildkitRunner? buildkit;
  final BinSelfCompiler? compileSelf;
  final StringSink? progress;
  final String? platform;

  String get _name => all ? 'skill-build-all-binaries' : 'skill-build-binaries';

  /// `--list` prints the release set.
  @override
  bool get handlesListMode => true;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.failure(
        path: context.path,
        name: context.name,
        error: ':$_name runs over the whole workspace, without the traversal',
      );

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final sink = out ?? stdout;
    final opts = args.optionsFor(_name);
    final json = opts['json'] == true;
    final start = p.normalize(p.absolute(args.root ?? Directory.current.path));
    final root = releaseWorkspaceRoot(start);
    if (root == null) {
      sink.writeln('Error: no buildkit_master.yaml at or above $start.');
      return ToolResult.failure(
        'no workspace',
        exitCode: ReportExitCode.refused,
      );
    }
    final set = ReleaseSet.load(root);
    final plat = platform ?? PlatformUtils.getCurrentPlatform();
    if (args.listOnly) {
      sink.writeln(
        json
            ? const JsonEncoder.withIndent('  ').convert({
                'root': root,
                'platform': plat,
                'binaries': [for (final b in set.binaries) b.toJson()],
                'onPlatform': [for (final b in set.forPlatform(plat)) b.name],
                'problems': set.problems,
              })
            : binListText(set, plat),
      );
      return set.problems.isEmpty
          ? const ToolResult.success()
          : ToolResult.failure('release set', exitCode: ReportExitCode.refused);
    }
    final run = SkillBinariesBuild(
      set: set,
      binaries: binTomBinaries(root, given: opts['binaries'] as String?),
      all: all,
      platform: plat,
      dryRun: args.dryRun,
      now: now,
      buildkit: buildkit,
      compileSelf: compileSelf,
      progress: progress,
    );
    await run.run();
    sink.writeln(
      json
          ? _json(run.report, 'build', run.toJson())
          : [
              run.report.renderText(verbose: args.verbose),
              if (args.dryRun) ...[
                'Would run:',
                for (final c in run.planned) '  $c',
              ],
            ].join('\n'),
    );
    return _result(':$_name', run.report.exitCode);
  }
}

/// `:skill-push-binaries`.
class SkillPushBinariesExecutor extends CommandExecutor {
  SkillPushBinariesExecutor({this.out, this.now, this.gitEnvironment});

  final StringSink? out;
  final DateTime? now;
  final Map<String, String>? gitEnvironment;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.failure(
        path: context.path,
        name: context.name,
        error:
            ':skill-push-binaries runs on tom_binaries, without the traversal',
      );

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final sink = out ?? stdout;
    final opts = args.optionsFor('skill-push-binaries');
    final json = opts['json'] == true;
    final start = p.normalize(p.absolute(args.root ?? Directory.current.path));
    final root = releaseWorkspaceRoot(start) ?? start;
    final run = SkillPushBinariesRun(
      binaries: binTomBinaries(root, given: opts['binaries'] as String?),
      dryRun: args.dryRun,
      now: now,
      gitEnvironment: gitEnvironment,
    );
    await run.run();
    sink.writeln(
      json
          ? _json(run.report, 'push', {
              'binaries': run.binaries,
              'outcome': run.outcome,
            })
          : '${run.report.renderText(verbose: args.verbose)}\n'
                ':skill-push-binaries: ${run.outcome}',
    );
    return _result(':skill-push-binaries', run.report.exitCode);
  }
}
