/// `wssetup`: sets up the directory tree after a checkout, from `repos.yaml`.
///
/// After a checkout of the root repository it clones every repository of the
/// tree; run in (or `--folder`) a workspace folder, only the repositories
/// below that folder. It only clones what is missing: an existing repository
/// is compared (origin URL, branch, an upstream's pin) and never pulled,
/// pushed or changed. Then it writes each parent's generated ignore block as
/// `tom_repos --apply` does (`--check`: reports it instead).
///
/// It needs no AI setup: it reads `repos.yaml` and git, and no `.tom`, `_ai`
/// or extension configuration. The AI state (`kind: ai`) and the `links:` are
/// the fleet skill's (`tom_clone_new`); they are reported, not made.
///
/// Before the cutover (the root still holds a `.gitmodules`, reduced mode)
/// the entries that are submodules are left to git, and no ignore block is
/// written: the blocks come with the cutover, as for `tom_repos --apply`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:tom_build_base/tom_build_base_v2.dart'
    show
        RepoEntry,
        RepoKind,
        ReposManifest,
        ReposManifestException,
        findReposRoot,
        reposHostId;

/// The first and last line of a parent's generated ignore block.
const wssetupBlockBegin = '# >>> repos.yaml (generated, tom_repos) >>>';
const wssetupBlockEnd = '# <<< repos.yaml <<<';

/// What a run is asked to do.
class WssetupRequest {
  const WssetupRequest({
    this.tree,
    this.folder,
    this.host,
    this.only = const [],
    this.manifest,
    this.check = false,
    this.dryRun = false,
    this.verbose = false,
    this.workingDirectory,
    this.gitEnvironment,
  });

  /// The root of the tree; default: the nearest folder above the working
  /// directory that holds `repos.yaml`.
  final String? tree;

  /// The workspace folder to set up, relative to the root (or absolute);
  /// default: the entry the working directory is in, the whole tree at the
  /// root.
  final String? folder;

  /// This host's fleet id; default: `TOM_REPOS_HOST`, `.tom/machine_id`,
  /// then the host name.
  final String? host;

  /// Only these entry paths (also on-demand entries and other hosts' ones).
  final List<String> only;

  /// A `repos.yaml` kept elsewhere; default `<root>/repos.yaml`.
  final String? manifest;

  /// Report the ignore blocks instead of writing them.
  final bool check;

  /// List the plan; clone and write nothing.
  final bool dryRun;

  final bool verbose;

  /// Default: the process's current directory.
  final String? workingDirectory;

  /// Variables added to git's environment (e.g. `GIT_CONFIG_*`).
  final Map<String, String>? gitEnvironment;
}

/// One line of the report: an entry or a parent and what happened to it.
class WssetupItem {
  const WssetupItem(this.status, this.path, [this.detail = '']);

  /// `cloned`, `exists`, `differs`, `skipped`, `failed`, `would clone`,
  /// `block written`, `block ok`, `block differs`, `would write block`.
  final String status;
  final String path;
  final String detail;

  bool get isFailure => status == 'failed';

  @override
  String toString() =>
      '${status.padRight(17)} ${path.isEmpty ? '.' : path}'
      '${detail.isEmpty ? '' : '  ($detail)'}';
}

/// What a run did.
class WssetupResult {
  WssetupResult(this.root, this.scope, this.host, this.reduced, this.items);

  final String root;

  /// The folder that was set up ('' for the whole tree).
  final String scope;
  final String host;
  final bool reduced;
  final List<WssetupItem> items;

  int count(String status) => items.where((i) => i.status == status).length;

  bool get hasFailures => items.any((i) => i.isFailure);

  /// The report: header, one line per item, a count per status.
  String render() {
    final b = StringBuffer()
      ..writeln(
        'wssetup: ${scope.isEmpty ? 'the whole tree' : scope} '
        'of $root, host $host, '
        'mode ${reduced ? 'reduced (root .gitmodules present)' : 'full'}',
      );
    for (final item in items) {
      b.writeln('  $item');
    }
    final counts = <String, int>{};
    for (final item in items) {
      counts[item.status] = (counts[item.status] ?? 0) + 1;
    }
    b.write(
      counts.isEmpty
          ? 'nothing to do'
          : counts.entries.map((e) => '${e.value} ${e.key}').join(', '),
    );
    return b.toString();
  }
}

/// A usage problem: no root, no manifest, an invalid manifest.
class WssetupUsageException implements Exception {
  WssetupUsageException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Sets up the tree as [request] asks and returns what it did. Throws
/// [WssetupUsageException] when there is no tree or manifest to read, and
/// [ReposManifestException] for an invalid manifest.
Future<WssetupResult> runWssetup(WssetupRequest request) async {
  final cwd = p.normalize(
    p.absolute(request.workingDirectory ?? Directory.current.path),
  );
  final root = request.tree != null
      ? p.normalize(p.absolute(cwd, request.tree!))
      : findReposRoot(cwd) ??
            (request.manifest != null
                ? cwd
                : throw WssetupUsageException(
                    'wssetup: no repos.yaml in this folder or above it '
                    '(give --tree or --manifest)',
                  ));
  final manifestPath = request.manifest != null
      ? p.normalize(p.absolute(cwd, request.manifest!))
      : p.join(root, 'repos.yaml');
  final manifestFile = File(manifestPath);
  if (!manifestFile.existsSync()) {
    throw WssetupUsageException('wssetup: no manifest at $manifestPath');
  }
  final manifest = ReposManifest.parse(manifestFile.readAsStringSync());
  _gitEnv = request.gitEnvironment;

  final scope = _scope(request.folder, cwd, root, manifest);
  final host = request.host ?? reposHostId(root);
  final reduced = File(p.join(root, '.gitmodules')).existsSync();
  final items = <WssetupItem>[];

  final only = request.only.map(_norm).toSet();
  for (final path in only) {
    if (!manifest.entries.any((e) => e.path == path)) {
      items.add(WssetupItem('failed', path, '--only: no entry with this path'));
    }
  }

  // Parents before children: a path sorts after every prefix of it.
  final entries =
      manifest.entries.where((e) => _inScope(e.path, scope)).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final unmanaged = manifest.unmanaged.toSet();
  var gitlinked = <String>{};

  for (final entry in entries) {
    if (reduced) gitlinked = await _gitlinks(root);
    final target = p.join(root, p.joinAll(entry.path.split('/')));
    if (only.isNotEmpty && !only.contains(entry.path)) {
      if (request.verbose) {
        items.add(WssetupItem('skipped', entry.path, 'not in --only'));
      }
      continue;
    }
    if (entry.kind == RepoKind.ai) {
      items.add(
        WssetupItem(
          'skipped',
          entry.path,
          'the AI state: cloned and linked by the fleet skill',
        ),
      );
      continue;
    }
    if (only.isEmpty && !entry.isForHost(host)) {
      items.add(
        WssetupItem(
          'skipped',
          entry.path,
          entry.onDemand
              ? 'on demand (--only ${entry.path})'
              : 'not for host $host',
        ),
      );
      continue;
    }
    if (_isRepo(target)) {
      items.add(await _compare(entry, target));
      continue;
    }
    if (reduced && gitlinked.contains(entry.path)) {
      items.add(
        WssetupItem(
          'skipped',
          entry.path,
          'a submodule (reduced mode): git submodule update --init',
        ),
      );
      continue;
    }
    final dir = Directory(target);
    if (dir.existsSync() && dir.listSync().isNotEmpty) {
      items.add(
        WssetupItem(
          'failed',
          entry.path,
          'the folder exists and is no repository',
        ),
      );
      continue;
    }
    if (_insideUnmanaged(entry.path, unmanaged)) {
      items.add(
        WssetupItem('skipped', entry.path, 'inside an unmanaged clone'),
      );
      continue;
    }
    if (request.dryRun) {
      items.add(WssetupItem('would clone', entry.path, _describe(entry)));
      continue;
    }
    items.add(await _clone(entry, target));
  }

  items.addAll(_blocks(manifest, root, scope, reduced, request));
  return WssetupResult(root, scope, host, reduced, items);
}

// ---------------------------------------------------------------- the tree

String _norm(String path) =>
    path.replaceAll(r'\', '/').replaceAll(RegExp(r'^/+|/+$'), '');

bool _inScope(String path, String scope) =>
    scope.isEmpty || path == scope || path.startsWith('$scope/');

bool _insideUnmanaged(String path, Set<String> unmanaged) =>
    unmanaged.any((u) => path == u || path.startsWith('$u/'));

bool _isRepo(String dir) =>
    FileSystemEntity.typeSync(p.join(dir, '.git')) !=
    FileSystemEntityType.notFound;

/// The folder to set up: [folder] as given, else the deepest entry the
/// working directory is in, else the working directory's path below the
/// root ('' at the root: the whole tree).
String _scope(String? folder, String cwd, String root, ReposManifest manifest) {
  if (folder != null) {
    final abs = p.isAbsolute(folder) ? folder : p.join(root, folder);
    return _norm(
      p.relative(p.normalize(abs), from: root),
    ).replaceAll(RegExp(r'^\.$'), '');
  }
  if (!p.isWithin(root, cwd)) return '';
  final rel = _norm(p.relative(cwd, from: root));
  var best = '';
  for (final e in manifest.entries) {
    if ((rel == e.path || rel.startsWith('${e.path}/')) &&
        e.path.length > best.length) {
      best = e.path;
    }
  }
  return best.isEmpty ? rel : best;
}

/// This host's fleet id, as tom_repos finds it.
/// The paths of every submodule declared in a `.gitmodules` of the tree.
Future<Set<String>> _gitlinks(String root) async {
  final out = <String>{};
  final todo = [''];
  while (todo.isNotEmpty) {
    final rel = todo.removeLast();
    final repo = rel.isEmpty ? root : p.join(root, rel);
    if (!File(p.join(repo, '.gitmodules')).existsSync()) continue;
    final r = await _git(repo, [
      'config',
      '-f',
      '.gitmodules',
      '--get-regexp',
      r'^submodule\..*\.path$',
    ]);
    if (r.exitCode != 0) continue;
    for (final line in LineSplitter.split('${r.stdout}')) {
      final value = line.substring(line.indexOf(' ') + 1).trim();
      final path = _norm(rel.isEmpty ? value : '$rel/$value');
      if (out.add(path)) todo.add(path);
    }
  }
  return out;
}

// --------------------------------------------------------------------- git

/// Variables added to every git call of the current run.
Map<String, String>? _gitEnv;

Future<ProcessResult> _git(String dir, List<String> args) => Process.run(
  'git',
  args,
  workingDirectory: dir,
  environment: _gitEnv,
  runInShell: Platform.isWindows,
);

String _describe(RepoEntry e) => e.kind == RepoKind.upstream
    ? '${e.url} at ${e.pin}'
    : '${e.url} on ${e.branch}';

Future<WssetupItem> _clone(RepoEntry entry, String target) async {
  Directory(p.dirname(target)).createSync(recursive: true);
  final args = [
    'clone',
    if (entry.kind != RepoKind.upstream) ...['--branch', entry.branch!],
    entry.url,
    target,
  ];
  final clone = await _git(p.dirname(target), args);
  if (clone.exitCode != 0) {
    return WssetupItem(
      'failed',
      entry.path,
      'git clone: ${'${clone.stderr}'.trim().split('\n').last}',
    );
  }
  if (entry.kind == RepoKind.upstream) {
    final checkout = await _git(target, [
      'checkout',
      '--quiet',
      '--detach',
      entry.pin!,
    ]);
    if (checkout.exitCode != 0) {
      return WssetupItem(
        'failed',
        entry.path,
        'cloned, but the pin ${entry.pin} cannot be checked out',
      );
    }
  }
  return WssetupItem('cloned', entry.path, _describe(entry));
}

/// An existing repository against its entry: origin URL (as stored), branch
/// (detached at the head of `origin/<branch>` counts, a fork's series
/// head), an upstream's pin.
Future<WssetupItem> _compare(RepoEntry entry, String target) async {
  final differences = <String>[];
  final url =
      '${(await _git(target, ['config', '--get', 'remote.origin.url'])).stdout}'
          .trim();
  if (url != entry.url) differences.add('origin $url, not ${entry.url}');
  final head = '${(await _git(target, ['rev-parse', 'HEAD'])).stdout}'.trim();
  if (entry.kind == RepoKind.upstream) {
    if (head != entry.pin) {
      differences.add('at ${_short(head)}, not the pin ${_short(entry.pin!)}');
    }
  } else {
    final branch =
        '${(await _git(target, ['symbolic-ref', '--quiet', '--short', 'HEAD'])).stdout}'
            .trim();
    if (branch != entry.branch) {
      final tip = await _git(target, [
        'rev-parse',
        'refs/remotes/origin/${entry.branch}',
      ]);
      final atTip =
          branch.isEmpty && tip.exitCode == 0 && '${tip.stdout}'.trim() == head;
      if (!atTip) {
        differences.add(
          branch.isEmpty
              ? 'detached at ${_short(head)}, not on ${entry.branch}'
              : 'on $branch, not ${entry.branch}',
        );
      }
    }
  }
  return differences.isEmpty
      ? WssetupItem('exists', entry.path)
      : WssetupItem('differs', entry.path, differences.join('; '));
}

String _short(String sha) => sha.length > 12 ? sha.substring(0, 12) : sha;

// ----------------------------------------------------------- ignore blocks

List<WssetupItem> _blocks(
  ReposManifest manifest,
  String root,
  String scope,
  bool reduced,
  WssetupRequest request,
) {
  if (reduced) {
    return const [
      WssetupItem(
        'skipped',
        '.gitignore blocks',
        'reduced mode: written after the cutover, as tom_repos --apply',
      ),
    ];
  }
  final items = <WssetupItem>[];
  final wanted = manifest.ignoreBlocks();
  // Every parent in scope: the root (whole tree only) and every entry.
  final parents = <String>{
    if (scope.isEmpty) '',
    for (final e in manifest.entries)
      if (_inScope(e.path, scope)) e.path,
  }.toList()..sort();
  for (final parent in parents) {
    final lines = wanted[parent] ?? const <String>[];
    final repo = parent.isEmpty
        ? root
        : p.join(root, p.joinAll(parent.split('/')));
    if (!Directory(repo).existsSync()) continue;
    final gitignore = File(p.join(repo, '.gitignore'));
    final current = gitignore.existsSync() ? gitignore.readAsStringSync() : '';
    // A parent without children is touched only to remove a block it holds.
    if (lines.isEmpty &&
        !LineSplitter.split(current).contains(wssetupBlockBegin)) {
      continue;
    }
    final next = blockWritten(current, lines);
    final label = '${parent.isEmpty ? '.' : parent}/.gitignore';
    if (next == current) {
      if (lines.isNotEmpty) {
        items.add(WssetupItem('block ok', label, '${lines.length} line(s)'));
      }
      continue;
    }
    if (request.dryRun) {
      items.add(
        WssetupItem('would write block', label, '${lines.length} line(s)'),
      );
    } else if (request.check) {
      items.add(
        WssetupItem('block differs', label, '${lines.length} line(s) expected'),
      );
    } else {
      gitignore.writeAsStringSync(next);
      items.add(WssetupItem('block written', label, '${lines.length} line(s)'));
    }
  }
  return items;
}

/// [text] with its generated block replaced by [wanted] (removed when
/// [wanted] is empty); every line outside the block stays. The same result
/// as `tom_repos --apply` (`write_block`).
String blockWritten(String text, List<String> wanted) {
  final lines = LineSplitter.split(text).toList();
  List<String> before;
  List<String> after;
  final i = lines.indexOf(wssetupBlockBegin);
  if (i >= 0) {
    final end = lines.indexOf(wssetupBlockEnd, i);
    final j = end >= 0 ? end + 1 : lines.length;
    before = lines.sublist(0, i);
    after = lines.sublist(j);
  } else {
    before = lines;
    after = const [];
  }
  while (before.isNotEmpty && before.last.trim().isEmpty) {
    before.removeLast();
  }
  final block = wanted.isEmpty
      ? <String>[]
      : [wssetupBlockBegin, ...wanted, wssetupBlockEnd];
  final result = [
    ...before,
    if (before.isNotEmpty && block.isNotEmpty) '',
    ...block,
  ];
  if (after.isNotEmpty) {
    if (after.first.trim().isNotEmpty) result.add('');
    result.addAll(after);
  }
  if (result.isEmpty) return '';
  return '${result.join('\n').replaceAll(RegExp(r'\n+$'), '')}\n';
}
