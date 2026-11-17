/// The `wssetup` tool (tom_build_base v2) and the executor `buildkit
/// :wssetup` delegates to. See `wssetup.dart` for what a run does.
library;

import 'dart:io';

import 'package:tom_build_base/tom_build_base_v2.dart';

import '../version.versioner.dart';
import 'repos_manifest.dart';
import 'wssetup.dart';

/// The options of `wssetup` and of `buildkit :wssetup`. Named so they do not
/// meet the navigation options (`--root`, `--workspace`, `-s`, ...).
const wssetupOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'tree',
    description:
        'The root of the tree (default: the nearest folder above holding repos.yaml)',
    valueName: 'dir',
  ),
  OptionDefinition.option(
    name: 'folder',
    description:
        'The workspace folder to set up, relative to the root (default: the '
        'one the working directory is in; at the root, the whole tree)',
    valueName: 'path',
  ),
  OptionDefinition.option(
    name: 'host',
    description:
        "This host's fleet id (default: TOM_REPOS_HOST, .tom/machine_id, the host name)",
    valueName: 'id',
  ),
  OptionDefinition.multi(
    name: 'only',
    description:
        'Clone only this entry (repeatable); also an on-demand entry or '
        "another host's",
    valueName: 'path',
  ),
  OptionDefinition.option(
    name: 'manifest',
    description: 'A repos.yaml kept elsewhere (default: <root>/repos.yaml)',
    valueName: 'file',
  ),
  OptionDefinition.flag(
    name: 'check',
    description:
        "Report each parent's generated ignore block instead of writing it",
  ),
];

const _help = '''
After a checkout of the root repository, wssetup clones every repository of
the tree that repos.yaml lists; run in a workspace folder (or with --folder),
only the repositories below that folder. It clones only what is missing, on
the entry's branch (an upstream at its pinned SHA), for this host (hosts:);
an existing repository is compared (origin URL, branch, pin) and never
pulled, pushed or changed. Then it writes each parent's generated ignore
block as tom_repos --apply does (--check: reports it).

It needs no AI setup (no .tom, no _ai, no extension configuration). The AI
state and the links are left to the fleet skill (tom_clone_new). Before the
cutover (the root still holds a .gitmodules) the submodule entries are left to
git and no ignore block is written.

Exit codes: 0 done; 1 a clone failed, or with --check a block differs;
2 no repos.yaml, or an invalid one.''';

/// The `wssetup` tool.
final wssetupTool = ToolDefinition(
  name: 'wssetup',
  description:
      'Set up the directory tree after a checkout: clone the repositories '
      'repos.yaml lists',
  version: BuildkitVersionInfo.version,
  versionString: 'wssetup ${BuildkitVersionInfo.versionLong}',
  mode: ToolMode.singleCommand,
  features: const NavigationFeatures(
    projectTraversal: false,
    gitTraversal: false,
    recursiveScan: false,
    interactiveMode: false,
    dryRun: true,
    jsonOutput: false,
    verbose: true,
  ),
  globalOptions: wssetupOptions,
  helpFooter: _help,
);

/// Runs `wssetup` with [CliArgs] options (`wssetup` itself and `buildkit
/// :wssetup`).
class WssetupExecutor extends CommandExecutor {
  WssetupExecutor({this.commandName = 'wssetup', this.out});

  /// The command whose options are read (`wssetup` / `wssetup` in buildkit).
  final String commandName;

  /// Where the report goes; default stdout.
  final StringSink? out;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.failure(
        path: context.path,
        name: context.name,
        error: 'wssetup visits no projects',
      );

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final o = args.optionsFor(commandName);
    final sink = out ?? stdout;
    final only = switch (o['only']) {
      final List<dynamic> list => [for (final v in list) '$v'],
      final String one => [one],
      _ => const <String>[],
    };
    final WssetupResult result;
    try {
      result = await runWssetup(
        WssetupRequest(
          tree: o['tree'] as String?,
          folder: o['folder'] as String?,
          host: o['host'] as String?,
          only: only,
          manifest: o['manifest'] as String?,
          check: o['check'] == true,
          dryRun: args.dryRun,
          verbose: args.verbose,
        ),
      );
    } on WssetupUsageException catch (e) {
      sink.writeln(e.message);
      return ToolResult(
        success: false,
        errorMessage: e.message,
        itemResults: [
          ItemResult.failure(
            path: '.',
            name: 'wssetup',
            error: e.message,
            exitCode: 2,
          ),
        ],
      );
    } on ReposManifestException catch (e) {
      sink.writeln('wssetup: $e');
      return ToolResult(
        success: false,
        errorMessage: 'invalid repos.yaml',
        itemResults: [
          ItemResult.failure(
            path: '.',
            name: 'wssetup',
            error: 'invalid repos.yaml',
            exitCode: 2,
          ),
        ],
      );
    }
    sink.writeln(result.render());
    final blockDiffers = result.count('block differs') > 0;
    if (result.hasFailures || blockDiffers) {
      return ToolResult.failure(
        result.hasFailures
            ? '${result.count('failed')} entr(y/ies) failed'
            : 'an ignore block differs (--check)',
      );
    }
    return const ToolResult.success();
  }
}
