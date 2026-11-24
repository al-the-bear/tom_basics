/// `buildkit :ws-repo-cleanup`: the surplus clones of the tree reported,
/// moved or deleted (buildkit_ws_commands.md § 1.5, decision WSC-12).
///
/// A surplus clone is on disk under the root, no entry of repos.yaml, not
/// listed under `unmanaged:`, no quest clone, no tool's, and **not inside
/// `_ai`** (anything with an `_ai` segment in its path is left alone).
///
/// - Default: report only. Per clone: its origin and branch, uncommitted
///   files, commits on no remote branch, branches without an upstream,
///   stashes, what is inside it, and what each option would do.
/// - `--apply`: every removable clone (clean, every commit on a remote
///   branch, no stash, nothing inside) is moved to
///   `<root>/ztmp/<yymmdd>_ws_repo_cleanup/<path>`; `--delete` (with or
///   without `--apply`) deletes them instead.
/// - A clone that is not removable stays: `ws-not-removable`
///   (`--force-remove`: moved anyway, never deleted; or
///   `:ws-push --include-unknown <repo>` first). One that holds an entry or another
///   clone is never moved as a whole, not even with `--force-remove`.
///
/// Exit 0 when nothing needs you (removable clones are warnings); 1 when a
/// clone is not removable or one was left out (`--skip`); 2 refused.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import 'ws_common.dart';
import 'ws_messages.dart';

/// The options of `:ws-repo-cleanup` that take repositories.
const wsRepoCleanupRepoOptions = ['skip', 'force-remove'];

/// The options of a run, as given.
class WsRepoCleanupOptions {
  WsRepoCleanupOptions({
    this.apply = false,
    this.delete = false,
    this.dryRun = false,
    this.verbose = false,
    this.json = false,
    this.repoLists = const {},
  });

  final bool apply;
  final bool delete;
  final bool dryRun;
  final bool verbose;
  final bool json;
  final Map<String, String> repoLists;

  /// Whether the removable clones are removed (`--apply` or `--delete`).
  bool get removes => apply || delete;

  /// The command line as typed (no `-n`).
  List<String> get given => [
    if (apply) '--apply',
    if (delete) '--delete',
    for (final e in repoLists.entries) ...['--${e.key}', e.value],
  ];
}

/// Reads the run's options from [opts] (`args.optionsFor('ws-repo-cleanup')`).
WsRepoCleanupOptions wsRepoCleanupOptions(
  Map<String, dynamic> opts,
  CliArgs args,
) {
  List<String> list(Object? v) => [
    for (final x in switch (v) {
      final List<dynamic> l => l,
      final String s => [s],
      _ => const <dynamic>[],
    })
      '$x',
  ];
  return WsRepoCleanupOptions(
    apply: opts['apply'] == true,
    delete: opts['delete'] == true,
    dryRun: args.dryRun,
    verbose: args.verbose,
    json: opts['json'] == true,
    repoLists: {
      for (final name in wsRepoCleanupRepoOptions)
        if (list(opts[name]).isNotEmpty) name: list(opts[name]).join(','),
    },
  );
}

/// What a surplus clone holds.
class WsSurplusClone {
  WsSurplusClone(this.member);

  final RepoSetMember member;
  String url = '';
  String? branch;
  List<String> uncommitted = const [];
  List<String> unpushed = const [];
  List<String> noUpstream = const [];
  List<String> stashes = const [];

  /// The repositories below it (entries, clones of any kind).
  List<String> inside = const [];

  String get rel => member.relPath;

  /// Nothing would be lost by removing it.
  bool get removable =>
      uncommitted.isEmpty &&
      unpushed.isEmpty &&
      stashes.isEmpty &&
      inside.isEmpty;
}

/// Whether [rel] is `_ai` or inside an `_ai` folder: never touched.
bool wsInsideAi(String rel) => rel.split('/').contains('_ai');

/// One `:ws-repo-cleanup` run over the tree of [set].
class WsRepoCleanupRun {
  WsRepoCleanupRun({
    required this.set,
    required this.options,
    DateTime? now,
    this.gitEnvironment,
  }) : now = now ?? DateTime.now();

  final RepoSet set;
  final WsRepoCleanupOptions options;
  final DateTime now;
  final Map<String, String>? gitEnvironment;

  late final RunReport report;
  late final RepoSelections _sel;
  var _leftOut = false;

  bool get _dry => options.dryRun;

  /// The run's exit code.
  int get exitCode {
    final code = report.exitCode;
    if (code < ReportExitCode.needsYou && _leftOut) {
      return ReportExitCode.needsYou;
    }
    return code;
  }

  /// `ztmp/<yymmdd>_ws_repo_cleanup`, relative to the root.
  String get cleanupFolder {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'ztmp/${two(now.year % 100)}${two(now.month)}${two(now.day)}'
        '_ws_repo_cleanup';
  }

  /// The surplus clones of the set.
  List<RepoSetMember> get surplus => [
    for (final m in set.members)
      if (m.repoClass == RepoClass.unknown && !wsInsideAi(m.relPath)) m,
  ];

  /// Runs it; [RepoNameException] for an unknown or ambiguous name.
  Future<RunReport> run() async {
    final clones = surplus;
    final names = RepoNames([for (final m in clones) m.relPath]);
    _sel = RepoSelections({
      for (final e in options.repoLists.entries)
        e.key: names.resolve(e.value).toSet(),
    });
    report = RunReport(
      tool: 'buildkit',
      command: ':ws-repo-cleanup',
      root: set.root,
      host: set.host,
      started: now,
      given: options.given,
      names: names,
    );
    if (options.repoLists.containsKey('skip')) _leftOut = true;

    final read = <WsSurplusClone>[];
    await wsPool(clones, (m) async => read.add(await _read(m)));
    read.sort((a, b) => a.rel.compareTo(b.rel));
    report.lookedAt.addAll([for (final c in read) c.rel]);
    for (final c in read) {
      if (_sel.applies('skip', c.rel)) continue;
      await _handle(c);
    }
    return report;
  }

  Future<WsSurplusClone> _read(RepoSetMember m) async {
    final g = WsGit(m.path, gitEnvironment);
    final c = WsSurplusClone(m);
    c.inside = [
      for (final o in set.members)
        if (o.onDisk && p.isWithin(m.path, o.path)) o.relPath,
    ];
    final insideRel = [
      for (final o in c.inside) '${p.relative(o, from: m.relPath)}/',
    ];
    c.url = await g.originUrl();
    final head = await g.run(['symbolic-ref', '-q', '--short', 'HEAD']);
    c.branch = head.exitCode == 0 ? '${head.stdout}'.trim() : null;
    c.uncommitted = [
      for (final ch in await g.changes())
        if (!insideRel.any((i) => ch.path == i || ch.path.startsWith(i)))
          '${ch.code} ${ch.path}',
    ];
    c.unpushed = await g.log('--branches --not --remotes', max: 20);
    if (c.branch == null && await g.hasRef('HEAD')) {
      // A detached HEAD's commits count too.
      c.unpushed = {
        ...c.unpushed,
        ...await g.log('HEAD --not --remotes', max: 20),
      }.toList();
    }
    final refs = await g.out([
      'for-each-ref',
      '--format=%(refname:short) %(upstream:short)',
      'refs/heads',
    ]);
    c.noUpstream = [
      for (final line in refs.split('\n'))
        if (line.trim().isNotEmpty && !line.trim().contains(' ')) line.trim(),
    ];
    final stashes = await g.out(['stash', 'list']);
    c.stashes = stashes.isEmpty ? const [] : stashes.split('\n');
    return c;
  }

  List<ReportEvidence> _evidence(WsSurplusClone c) => [
    ReportEvidence('origin', [
      c.url.isEmpty ? '(no origin)' : c.url,
    ], label: 'Origin:'),
    ReportEvidence('branch', [c.branch ?? '(detached HEAD)'], label: 'Branch:'),
    if (c.uncommitted.isNotEmpty)
      ReportEvidence('files', c.uncommitted, label: 'Uncommitted:'),
    if (c.unpushed.isNotEmpty)
      ReportEvidence('commits', c.unpushed, label: 'On no remote branch:'),
    if (c.noUpstream.isNotEmpty)
      ReportEvidence('branches', c.noUpstream, label: 'Without upstream:'),
    if (c.stashes.isNotEmpty)
      ReportEvidence('stashes', c.stashes, label: 'Stashes:'),
    if (c.inside.isNotEmpty)
      ReportEvidence('inside', c.inside, label: 'Inside it:'),
  ];

  /// Where [c] is moved to, relative to the root (a free name).
  String _target(WsSurplusClone c) {
    var rel = '$cleanupFolder/${c.rel}';
    var n = 2;
    while (FileSystemEntity.typeSync(
          p.join(set.root, p.joinAll(rel.split('/'))),
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound) {
      rel = '$cleanupFolder/${c.rel}-${n++}';
    }
    return rel;
  }

  void _move(WsSurplusClone c, String target) {
    final to = p.join(set.root, p.joinAll(target.split('/')));
    Directory(p.dirname(to)).createSync(recursive: true);
    Directory(c.member.path).renameSync(to);
  }

  Future<void> _handle(WsSurplusClone c) async {
    final target = _target(c);
    if (c.removable) {
      if (!options.removes) {
        report.add(
          wsSurplus.raise(
            repository: c.rel,
            branch: c.branch,
            finding:
                'Clean, every commit on a remote branch, no stash: removable.',
            evidence: _evidence(c),
            state: 'Left where it is (report only).',
            explanations: {
              'apply':
                  'Move it to $target;\n'
                  'delete that folder by hand once you are sure.',
            },
          ),
        );
        return;
      }
      if (options.delete) {
        if (!_dry) Directory(c.member.path).deleteSync(recursive: true);
        report.changed(ReportDone(c.rel, [_dry ? 'would delete' : 'deleted']));
      } else {
        if (!_dry) _move(c, target);
        report.changed(
          ReportDone(c.rel, ['${_dry ? 'would move' : 'moved'} to $target']),
        );
      }
      return;
    }

    final nested = c.inside.isNotEmpty;
    if (!nested && _sel.applies('force-remove', c.rel)) {
      if (!_dry) _move(c, target);
      report.changed(
        ReportDone(c.rel, [
          '${_dry ? 'would move' : 'moved'} to $target with its work '
              '(--force-remove)',
        ]),
      );
      return;
    }
    final what = [
      if (c.uncommitted.isNotEmpty)
        '${c.uncommitted.length} uncommitted file(s)',
      if (c.unpushed.isNotEmpty)
        '${c.unpushed.length} commit(s) on no remote branch',
      if (c.stashes.isNotEmpty) '${c.stashes.length} stash(es)',
    ];
    report.add(
      wsNotRemovable.raise(
        repository: c.rel,
        branch: c.branch,
        finding: nested
            ? 'It holds ${c.inside.length} repositor${c.inside.length == 1 ? 'y' : 'ies'} '
                  'below it; a clone is never moved as a whole with what is '
                  'inside.${what.isEmpty ? '' : ' It also has ${what.join(', ')}.'}'
            : 'It has ${what.join(', ')}; removing it would lose them.',
        evidence: _evidence(c),
        state: 'Left where it is.',
        offer: nested ? const ['skip'] : null,
        explanations: {
          'force-remove':
              'Move it anyway to $target, with its work;\n'
              'never deleted, even with --delete. Or push it first:\n'
              'buildkit :ws-push --include-unknown ${report.names.nameOf(c.rel)}',
        },
      ),
    );
  }
}

/// `:ws-repo-cleanup` (see the library comment).
class WsRepoCleanupExecutor extends CommandExecutor {
  WsRepoCleanupExecutor({this.out, this.now, this.gitEnvironment});

  final StringSink? out;
  final DateTime? now;
  final Map<String, String>? gitEnvironment;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.failure(
        path: context.path,
        name: context.name,
        error:
            ':ws-repo-cleanup runs over the whole tree, without the traversal',
      );

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final sink = out ?? stdout;
    final options = wsRepoCleanupOptions(
      args.optionsFor('ws-repo-cleanup'),
      args,
    );
    final start = p.normalize(p.absolute(args.root ?? Directory.current.path));
    final started = now ?? DateTime.now();

    RepoSet? set;
    String? problem;
    try {
      set = RepoSet.discover(start, manifestPath: args.manifest);
      if (set == null) {
        problem = 'No repos.yaml at or above $start (give --manifest).';
      }
    } on ReposManifestException catch (e) {
      problem = '$e';
    } on FileSystemException catch (e) {
      problem = 'repos.yaml cannot be read: ${e.message} (${e.path})';
    }
    if (set == null) {
      final report =
          RunReport(
            tool: 'buildkit',
            command: ':ws-repo-cleanup',
            root: start,
            host: Platform.localHostname,
            started: started,
            given: options.given,
            names: RepoNames(const []),
          )..add(
            wsManifest.raise(finding: problem!, state: 'Nothing was changed.'),
          );
      sink.writeln(options.json ? report.renderJson() : report.renderText());
      return ToolResult.failure(problem, exitCode: ReportExitCode.refused);
    }

    final run = WsRepoCleanupRun(
      set: set,
      options: options,
      now: started,
      gitEnvironment: gitEnvironment,
    );
    try {
      await run.run();
    } on RepoNameException catch (e) {
      sink.writeln('Error: $e');
      return ToolResult.failure('$e', exitCode: ReportExitCode.refused);
    }
    sink.writeln(
      options.json
          ? run.report.renderJson()
          : run.report.renderText(verbose: options.verbose),
    );
    final code = run.exitCode;
    return code == 0
        ? const ToolResult.success()
        : ToolResult.failure(':ws-repo-cleanup: exit $code', exitCode: code);
  }
}
