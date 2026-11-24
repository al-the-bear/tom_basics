/// What the `:skill-*` commands share (buildkit_ws_commands.md § 1.6): this
/// host's entries of repos.yaml in the order the fleet skills walk them, the
/// uncommitted work of a repository as the skills read it, the dirty scan
/// (`tom_dw_scan_tree` of `.claude/skills/_lib/dirty_scan_lib.sh`) and the
/// baseline a run's own files are told apart by.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../ws/ws_common.dart';
import '../ws/ws_messages.dart';

/// One repository a `:skill-*` command walks.
class SkillEntry {
  const SkillEntry({
    required this.abs,
    required this.rel,
    required this.kind,
    this.branch,
    this.pin,
    this.url,
  });

  /// The folder.
  final String abs;

  /// The path from the root; `.` is the root.
  final String rel;

  /// `root`, or the entry's kind (code, fork, ai, binaries, upstream).
  final String kind;
  final String? branch;
  final String? pin;
  final String? url;

  bool get isRoot => rel == '.';
  bool get cloned =>
      FileSystemEntity.typeSync(p.join(abs, '.git'), followLinks: false) !=
      FileSystemEntityType.notFound;
}

/// This host's entries of [set] (of [kinds], all when null), deepest first,
/// then by path: the order of `repos.py entries` (the skills' `each_repo`).
List<SkillEntry> skillEntries(RepoSet set, {Set<String>? kinds}) {
  final out = [
    for (final e in set.manifest.entries)
      if (e.isForHost(set.host) &&
          (kinds == null || kinds.contains(e.kind.name)))
        SkillEntry(
          abs: p.join(set.root, p.joinAll(e.path.split('/'))),
          rel: e.path,
          kind: e.kind.name,
          branch: e.branch,
          pin: e.pin,
          url: e.url,
        ),
  ];
  int depth(String rel) => rel.split('/').length;
  out.sort((a, b) {
    final d = depth(b.rel).compareTo(depth(a.rel));
    return d != 0 ? d : a.rel.compareTo(b.rel);
  });
  return out;
}

/// The root as an entry of kind `root`.
SkillEntry skillRoot(RepoSet set) => SkillEntry(
  abs: set.root,
  rel: '.',
  kind: 'root',
  branch: set.manifest.rootBranch,
  url: set.manifest.rootUrl,
);

/// The repositories under the root that are no entry of repos.yaml (of any
/// host), not unmanaged and no tool's: the skills' `tom_unknown_nested_repos`.
List<String> skillUnknownRepos(RepoSet set) => [
  for (final m in set.members)
    if (m.repoClass == RepoClass.unknown && !_isWorktree(m.path)) m.relPath,
];

/// A git worktree is no repository: its `.git` is a file pointing into the
/// `worktrees/` folder of its repository.
bool _isWorktree(String dir) {
  final git = File(p.join(dir, '.git'));
  if (!git.existsSync()) return false;
  try {
    return git.readAsStringSync().contains('/worktrees/');
  } on FileSystemException {
    return false;
  }
}

/// The path a porcelain-v1 line is about (a rename's destination), git's
/// quotes stripped (`tom_porcelain_path`).
String skillPorcelainPath(String line) {
  var path = line.length > 3 ? line.substring(3) : '';
  final arrow = path.lastIndexOf(' -> ');
  if (arrow >= 0) path = path.substring(arrow + 4);
  if (path.endsWith('"')) path = path.substring(0, path.length - 1);
  if (path.startsWith('"')) path = path.substring(1);
  return path;
}

/// The repository's own uncommitted work as porcelain-v1 lines
/// (`tom_dw_content_porcelain`): `all` lists every untracked file, `normal`
/// folds untracked folders. Left out: a nested clone, the `_ai` symlink and
/// its backups, `.worktrees/`.
Future<List<String>> skillContentPorcelain(
  WsGit g, {
  String untracked = 'all',
}) async {
  final r = await g.run([
    'status',
    '--porcelain=v1',
    '--untracked-files=$untracked',
  ]);
  if (r.exitCode != 0) return const [];
  final out = <String>[];
  for (final line in '${r.stdout}'.split('\n')) {
    if (line.replaceAll(' ', '').isEmpty) continue;
    final path = skillPorcelainPath(line);
    if (path == '.worktrees' || path.startsWith('.worktrees/')) continue;
    if (path == '_ai' || path == '_ai/' || path.startsWith('_ai.')) continue;
    if (line.startsWith('??')) {
      final bare = path.endsWith('/')
          ? path.substring(0, path.length - 1)
          : path;
      final full = p.join(g.dir, bare);
      if (FileSystemEntity.typeSync(p.join(full, '.git'), followLinks: false) !=
          FileSystemEntityType.notFound) {
        continue;
      }
      if (p.basename(bare) == '_ai' && FileSystemEntity.isLinkSync(full)) {
        continue;
      }
    }
    out.add(line);
  }
  return out;
}

/// The secret-like paths (`TOM_SECRET_PATTERNS` of the skills).
final skillSecretPattern = RegExp(
  r'(^|/)(\.env(\..+)?|.*\.pem|credentials\..*)$',
);

/// The paths a tool writes (`TOM_DW_GENERATED_RE`).
final skillGeneratedPattern = RegExp(
  r'(\.(b|g|freezed|reflection|versioner|mocks|gr)\.dart|(^|/)(tom_build_state\.json|pubspec\.lock))$',
);

/// The groups of the scan, in the order the decision document lists them.
const skillDirtyGroups = ['secret', 'generated', 'modified', 'new'];

/// The group of one uncommitted path (`tom_dw_group_of`).
String skillGroupOf(String xy, String path) {
  if (skillSecretPattern.hasMatch(path)) return 'secret';
  if (skillGeneratedPattern.hasMatch(path)) return 'generated';
  if (xy == '??') return 'new';
  return 'modified';
}

/// One uncommitted path of the scan.
class SkillDirtyFile {
  const SkillDirtyFile(this.xy, this.path, this.age);
  final String xy;
  final String path;

  /// Seconds since its last change; -1 when it does not exist (a deletion).
  final int age;
}

/// One group of one repository of the scan.
class SkillDirtyGroup {
  const SkillDirtyGroup(this.group, this.files, this.newest, this.fingerprint);
  final String group;
  final List<SkillDirtyFile> files;

  /// The youngest file's age; -1 when none exists.
  final int newest;

  /// The first 12 characters of `git hash-object` of the group's
  /// `<xy>\t<path>` lines: what `tom_dirty_work --apply-group` checks.
  final String fingerprint;
}

/// One repository of the scan.
class SkillDirtyRepo {
  const SkillDirtyRepo(this.abs, this.disp, this.groups);
  final String abs;

  /// Its path from the root; the root's is its folder name.
  final String disp;
  final List<SkillDirtyGroup> groups;
  int get files => groups.fold(0, (n, g) => n + g.files.length);
}

/// The scan of a host (`tom_dw_scan_tree`).
class SkillDirtyScan {
  SkillDirtyScan(this.label, this.repos, this.unknown);

  /// The root's folder name (the scan rows' `<root-label>`).
  final String label;

  /// Every repository walked, in walk order (clean ones included).
  final List<SkillDirtyRepo> repos;
  final List<String> unknown;

  int get files => repos.fold(0, (n, r) => n + r.files);
  int get groups => repos.fold(0, (n, r) => n + r.groups.length);

  /// The rows `tom_dirty_work --scan` prints, byte for byte.
  List<String> rows() => [
    for (final r in repos)
      for (final g in r.groups) ...[
        for (final f in g.files)
          [
            'DIRTY',
            label,
            r.disp,
            g.group,
            f.xy,
            '${f.age}',
            f.path,
          ].join('\t'),
        [
          'GROUP',
          label,
          r.disp,
          g.group,
          '${g.files.length}',
          '${g.newest}',
          g.fingerprint,
        ].join('\t'),
      ],
    for (final u in unknown) ['UNKNOWN', label, u].join('\t'),
    'SCANNED\t${repos.length}',
  ];

  Map<String, Object?> toJson() => {
    'label': label,
    'scanned': repos.length,
    'files': files,
    'repositories': [
      for (final r in repos)
        if (r.groups.isNotEmpty)
          {
            'path': r.disp,
            'groups': [
              for (final g in r.groups)
                {
                  'group': g.group,
                  'count': g.files.length,
                  'newestAge': g.newest,
                  'fingerprint': g.fingerprint,
                  'files': [
                    for (final f in g.files)
                      {'xy': f.xy, 'path': f.path, 'age': f.age},
                  ],
                },
            ],
          },
    ],
    'unknown': unknown,
  };
}

/// The run worktrees of the repository at [repo] that lie under
/// `<root>/.worktrees/`: `(abs, disp)`, disp relative to the root.
Future<List<(String, String)>> skillRunWorktrees(
  WsGit repo,
  String root,
) async {
  final out = <(String, String)>[];
  final list = await repo.out(['worktree', 'list', '--porcelain']);
  for (final line in list.split('\n')) {
    if (!line.startsWith('worktree ')) continue;
    final path = p.normalize(line.substring('worktree '.length));
    if (p.isWithin(p.join(root, '.worktrees'), path) &&
        Directory(path).existsSync()) {
      out.add((path, p.relative(path, from: root).replaceAll(r'\', '/')));
    }
  }
  return out;
}

/// The repositories the dirty scan covers (`tom_dw_each_repo`): the cloned
/// code, fork and upstream entries deepest first, each followed by its run
/// worktrees, then the root and its run worktrees. `(abs, disp)`.
Future<List<(String, String)>> skillDirtyRepos(
  RepoSet set, {
  Map<String, String>? env,
}) async {
  final label = p.basename(set.root);
  final out = <(String, String)>[];
  for (final e in skillEntries(set, kinds: {'code', 'fork', 'upstream'})) {
    if (!e.cloned) continue;
    out.add((e.abs, e.rel));
    out.addAll(await skillRunWorktrees(WsGit(e.abs, env), set.root));
  }
  out.add((set.root, label));
  out.addAll(await skillRunWorktrees(WsGit(set.root, env), set.root));
  return out;
}

int _compareBytes(String a, String b) {
  final x = utf8.encode(a), y = utf8.encode(b);
  for (var i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) return x[i] - y[i];
  }
  return x.length - y.length;
}

/// `git hash-object --stdin` of [text], its first 12 characters.
Future<String> skillFingerprint(WsGit g, String text) async {
  final proc = await Process.start(
    'git',
    ['hash-object', '--stdin'],
    workingDirectory: g.dir,
    environment: g.environment,
  );
  proc.stdin.add(utf8.encode(text));
  await proc.stdin.close();
  final out = await proc.stdout.transform(utf8.decoder).join();
  await proc.exitCode;
  final sha = out.trim();
  return sha.length >= 12 ? sha.substring(0, 12) : sha;
}

/// Scans one repository (`tom_dw_scan_repo`).
Future<SkillDirtyRepo> skillScanRepo(
  String abs,
  String disp,
  int now, {
  Map<String, String>? env,
}) async {
  final g = WsGit(abs, env);
  final content = await skillContentPorcelain(g);
  final groups = <SkillDirtyGroup>[];
  for (final group in skillDirtyGroups) {
    final lines = <(String, String)>[
      for (final line in content)
        if (skillGroupOf(line.substring(0, 2), skillPorcelainPath(line)) ==
            group)
          (line.substring(0, 2), skillPorcelainPath(line)),
    ];
    if (lines.isEmpty) continue;
    lines.sort((a, b) => _compareBytes('${a.$1}\t${a.$2}', '${b.$1}\t${b.$2}'));
    var newest = -1;
    final files = <SkillDirtyFile>[];
    for (final (xy, path) in lines) {
      final full = p.join(abs, path);
      var age = -1;
      if (FileSystemEntity.typeSync(full, followLinks: false) !=
          FileSystemEntityType.notFound) {
        final stat = FileStat.statSync(full);
        if (stat.type != FileSystemEntityType.notFound) {
          age = now - stat.modified.millisecondsSinceEpoch ~/ 1000;
          if (age < 0) age = 0;
        }
      }
      if (age >= 0 && (newest < 0 || age < newest)) newest = age;
      files.add(SkillDirtyFile(xy, path, age));
    }
    final text =
        '${[for (final (xy, path) in lines) '$xy\t$path'].join('\n')}\n';
    groups.add(
      SkillDirtyGroup(group, files, newest, await skillFingerprint(g, text)),
    );
  }
  return SkillDirtyRepo(abs, disp, groups);
}

/// The scan of this host (`tom_dw_scan_tree`).
Future<SkillDirtyScan> skillScanTree(
  RepoSet set, {
  Map<String, String>? env,
  DateTime? now,
}) async {
  final at = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  final repos = [
    for (final (abs, disp) in await skillDirtyRepos(set, env: env))
      await skillScanRepo(abs, disp, at, env: env),
  ];
  return SkillDirtyScan(p.basename(set.root), repos, skillUnknownRepos(set));
}

/// Writes the baseline (`tom_dw_write_baseline`): `<abs>\t<path>` for every
/// path uncommitted now.
Future<int> skillWriteBaseline(
  RepoSet set,
  String file, {
  Map<String, String>? env,
}) async {
  final lines = <String>[];
  for (final (abs, _) in await skillDirtyRepos(set, env: env)) {
    for (final line in await skillContentPorcelain(WsGit(abs, env))) {
      lines.add('$abs\t${skillPorcelainPath(line)}');
    }
  }
  File(file)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
  return lines.length;
}

/// The lines of a baseline file, as a set.
Set<String> skillReadBaseline(String file) => {
  for (final l in File(file).readAsLinesSync())
    if (l.isNotEmpty) l,
};

/// The rest of every `:skill-*` executor: the set, or the refusal printed.
Future<({RepoSet? set, ToolResult? refused})> skillDiscover({
  required CliArgs args,
  required String command,
  required List<String> given,
  required bool json,
  required StringSink sink,
  required DateTime started,
}) async {
  final start = p.normalize(p.absolute(args.root ?? Directory.current.path));
  String? problem;
  RepoSet? set;
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
  if (set != null) return (set: set, refused: null);
  final report = RunReport(
    tool: 'buildkit',
    command: command,
    root: start,
    host: Platform.localHostname,
    started: started,
    given: given,
    names: RepoNames(const []),
  )..add(wsManifest.raise(finding: problem!, state: 'Nothing was changed.'));
  sink.writeln(json ? report.renderJson() : report.renderText());
  return (
    set: null,
    refused: ToolResult.failure(problem, exitCode: ReportExitCode.refused),
  );
}

/// The JSON of a `:skill-*` run: the report (§ 1.10) and the command's own
/// section under [key].
String skillJson(RunReport report, String key, Map<String, Object?> data) =>
    const JsonEncoder.withIndent('  ').convert({...report.toJson(), key: data});
