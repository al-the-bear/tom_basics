/// The combined repository set of a Tom root: the entries of `repos.yaml`
/// for this host **and** every clone found on disk, each in its class.
///
/// Git mode (`-i` / `-o`) works on it whenever a `repos.yaml` is at or above
/// the start folder (or `--manifest` names one); the `:ws-*` commands take
/// the whole tree from the folder holding `repos.yaml` ([RepoSet.members]).
/// Without a `repos.yaml` git mode walks the folders as before.
///
/// | Class | What | Git commands |
/// | --- | --- | --- |
/// | [RepoClass.entry] | the root, and an entry of `repos.yaml` on disk | included, but `kind: upstream` skipped |
/// | [RepoClass.questClone] | a clone inside `_ai/quests/` | included |
/// | [RepoClass.unmanaged] | a clone at a path under `unmanaged:` | skipped |
/// | [RepoClass.toolOwned] | a run worktree under `.worktrees/`, a bare `_ai/.quest-repos/*.git` | skipped |
/// | [RepoClass.unknown] | any other clone on disk | skipped (the `:ws-*` commands report it) |
/// | [RepoClass.missing] | an entry for this host that is not on disk | – (`:ws-update` clones it) |
///
/// Never looked at: hidden folders (but `.worktrees/` and
/// `_ai/.quest-repos/`, to class what is there), `ztmp/`, `build/`,
/// `node_modules/` and the other always-skipped folders, and symlinks (the
/// workspace folders' `_ai` links are no repositories). Build skip markers
/// (`*_skip.yaml`) do not hide a repository: `repos.yaml` decides.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../workspace_utils.dart' show kAlwaysSkipDirectories;
import 'repos_manifest.dart';

/// The class of a repository in a [RepoSet] (see the library comment).
enum RepoClass { entry, questClone, unmanaged, toolOwned, unknown, missing }

/// One repository of a [RepoSet].
class RepoSetMember {
  const RepoSetMember({
    required this.path,
    required this.relPath,
    required this.repoClass,
    this.entry,
    this.isRoot = false,
    this.expectedBranch,
    this.url,
  });

  /// Absolute, normalized.
  final String path;

  /// From the root, with `/`; '' for the root itself.
  final String relPath;

  final RepoClass repoClass;

  /// Its entry in `repos.yaml` ([RepoClass.entry], [RepoClass.missing]).
  final RepoEntry? entry;

  /// Whether it is the root repository (`root:` of `repos.yaml`).
  final bool isRoot;

  /// The branch it should be on: the entry's `branch:`, `root.branch`, a
  /// quest repository's from `_ai/quests.yaml`; null when none is known (an
  /// upstream has a pin instead, an unknown clone has no record).
  final String? expectedBranch;

  /// Its origin URL as recorded (entry, root, `_ai/quests.yaml`), or null.
  final String? url;

  /// The entry's kind, or null (the root, a quest clone, ...).
  RepoKind? get kind => entry?.kind;

  /// The commit an upstream is pinned to.
  String? get pin => entry?.pin;

  /// Whether its folder is a clone on disk.
  bool get onDisk => repoClass != RepoClass.missing;

  /// Whether the git commands take it by default: the root and every entry
  /// but an upstream, and the quest clones.
  bool get inGitSet => switch (repoClass) {
    RepoClass.entry => kind != RepoKind.upstream,
    RepoClass.questClone => true,
    _ => false,
  };

  /// What `%{repo.kind}` says: `root`, the entry's kind (`code`, `fork`,
  /// `ai`, `binaries`, `upstream`), else the class (`questClone`, ...).
  String get kindName => isRoot ? 'root' : (kind?.name ?? repoClass.name);

  @override
  String toString() =>
      'RepoSetMember(${relPath.isEmpty ? '.' : relPath}, $kindName)';
}

/// The repositories a git-mode run in one folder works on: [members] (the
/// ones the git commands take, on disk), and [nestedWorkspaces], the
/// repositories holding a workspace of their own that the run stops at
/// (`-w` runs the command there).
typedef RepoSetScope = ({
  List<RepoSetMember> members,
  List<String> nestedWorkspaces,
});

/// The combined repository set of a Tom root (see the library comment).
class RepoSet {
  RepoSet._(
    this.root,
    this.manifestPath,
    this.manifest,
    this.host,
    this.members,
  );

  /// The folder holding `repos.yaml` (or the root [manifestPath] was given
  /// for), absolute.
  final String root;

  /// The manifest read.
  final String manifestPath;

  final ReposManifest manifest;

  /// The host whose entries count ([reposHostId] unless given).
  final String host;

  /// Every repository of the tree, each in its class, sorted by
  /// [RepoSetMember.relPath] (parents before their children).
  final List<RepoSetMember> members;

  /// The set for a run started in [start]: from the `repos.yaml` at or above
  /// it, or from [manifestPath] (a file; relative to [start]). Null when
  /// there is neither. Throws [ReposManifestException] for an invalid
  /// manifest. [host] defaults to [reposHostId] of the root.
  static RepoSet? discover(String start, {String? manifestPath, String? host}) {
    final from = p.normalize(p.absolute(start));
    String root;
    String file;
    if (manifestPath != null) {
      file = p.normalize(p.absolute(from, manifestPath));
      final dir = p.dirname(file);
      root = from == dir || p.isWithin(dir, from)
          ? dir
          : (findReposRoot(from) ?? from);
    } else {
      final found = findReposRoot(from);
      if (found == null) return null;
      root = found;
      file = p.join(root, kReposManifestFile);
    }
    final manifest = ReposManifest.parse(File(file).readAsStringSync());
    if (!_covers(root, manifest, from)) return null;
    return load(root: root, manifestPath: file, host: host);
  }

  /// The set of [root], read from [manifestPath] (default
  /// `<root>/repos.yaml`). Throws [ReposManifestException] for an invalid
  /// manifest and [FileSystemException] when it cannot be read.
  static RepoSet load({
    required String root,
    String? manifestPath,
    String? host,
  }) {
    final rootPath = p.normalize(p.absolute(root));
    final file = manifestPath ?? p.join(rootPath, kReposManifestFile);
    final manifest = ReposManifest.parse(File(file).readAsStringSync());
    final hostId = host ?? reposHostId(rootPath);
    final quests = _QuestRepos.read(rootPath);

    final byPath = {for (final e in manifest.entries) e.path: e};
    final unmanaged = manifest.unmanaged.toSet();
    final members = <RepoSetMember>[];
    final seen = <String>{};

    RepoSetMember classify(String rel, {required bool toolOwned}) {
      final abs = rel.isEmpty
          ? rootPath
          : p.join(rootPath, p.joinAll(rel.split('/')));
      if (rel.isEmpty) {
        return RepoSetMember(
          path: abs,
          relPath: '',
          repoClass: RepoClass.entry,
          isRoot: true,
          expectedBranch: manifest.rootBranch,
          url: manifest.rootUrl,
        );
      }
      if (toolOwned) {
        return RepoSetMember(
          path: abs,
          relPath: rel,
          repoClass: RepoClass.toolOwned,
        );
      }
      final entry = byPath[rel];
      if (entry != null) {
        return RepoSetMember(
          path: abs,
          relPath: rel,
          repoClass: RepoClass.entry,
          entry: entry,
          expectedBranch: entry.branch,
          url: entry.url,
        );
      }
      if (rel.startsWith('$kQuestsFolder/')) {
        final id = rel.substring(kQuestsFolder.length + 1).split('/').first;
        final quest = quests[id];
        return RepoSetMember(
          path: abs,
          relPath: rel,
          repoClass: RepoClass.questClone,
          expectedBranch: quest?.branch,
          url: quest?.url,
        );
      }
      if (unmanaged.contains(rel)) {
        return RepoSetMember(
          path: abs,
          relPath: rel,
          repoClass: RepoClass.unmanaged,
        );
      }
      return RepoSetMember(
        path: abs,
        relPath: rel,
        repoClass: RepoClass.unknown,
      );
    }

    void add(String rel, {bool toolOwned = false}) {
      if (seen.add(rel)) members.add(classify(rel, toolOwned: toolOwned));
    }

    if (_isClone(rootPath)) add('');
    _walk(rootPath, '', unmanaged, add);

    for (final entry in manifest.entries) {
      if (seen.contains(entry.path) || !entry.isForHost(hostId)) continue;
      seen.add(entry.path);
      members.add(
        RepoSetMember(
          path: p.join(rootPath, p.joinAll(entry.path.split('/'))),
          relPath: entry.path,
          repoClass: RepoClass.missing,
          entry: entry,
          expectedBranch: entry.branch,
          url: entry.url,
        ),
      );
    }
    members.sort((a, b) => a.relPath.compareTo(b.relPath));
    return RepoSet._(rootPath, file, manifest, hostId, members);
  }

  /// Whether [path] (absolute, normalized) belongs to the tree this set
  /// describes: not inside a folder the walk never looks at (hidden, scratch
  /// or build folders: a test's fixture under `.dart_tool/` or `ztmp/`) nor
  /// inside an unmanaged clone (a tree a tool owns, such as the workspace
  /// clone). A run started there is a tree of its own.
  static bool _covers(String root, ReposManifest manifest, String path) {
    if (path != root && !p.isWithin(root, path)) return false;
    final rel = p.relative(path, from: root).replaceAll(r'\', '/');
    if (rel == '.') return true;
    final segments = rel.split('/');
    for (var i = 0; i < segments.length; i++) {
      final name = segments[i];
      final prefix = segments.take(i + 1).join('/');
      if (manifest.unmanaged.contains(prefix)) return false;
      if (prefix == '$kAiFolder/$kQuestReposFolder' ||
          name == kWorktreesFolder) {
        return false;
      }
      if (name.startsWith('.') || skippedFolders.contains(name)) return false;
    }
    return true;
  }

  /// The member whose folder is [path] (absolute or relative to the
  /// working directory), or null.
  RepoSetMember? memberAt(String path) {
    final abs = p.normalize(p.absolute(path));
    for (final m in members) {
      if (m.path == abs) return m;
    }
    return null;
  }

  /// The repositories a git-mode run started in [start] works on: those of
  /// the git set ([RepoSetMember.inGitSet]) on disk at or below [start].
  ///
  /// With [stopAtWorkspaces] (the ordinary git commands without `-w` taking
  /// over), a repository below [start] whose folder holds a workspace of its
  /// own (`<toolBasename>_master.yaml`) is a boundary: it and everything
  /// below it are left out and it is named in
  /// [RepoSetScope.nestedWorkspaces]. A workspace folder that is no
  /// repository of the set (a test fixture inside a repository) is no
  /// boundary, so `-w` never runs a repository twice.
  RepoSetScope scope(
    String start, {
    String toolBasename = 'buildkit',
    bool stopAtWorkspaces = true,
  }) {
    final from = p.normalize(p.absolute(start));
    final inScope = members
        .where((m) => m.inGitSet && m.onDisk)
        .where((m) => m.path == from || p.isWithin(from, m.path))
        .toList();
    if (!stopAtWorkspaces) {
      return (members: inScope, nestedWorkspaces: const []);
    }
    final boundaries = [
      for (final m in inScope)
        if (m.path != from &&
            File(p.join(m.path, '${toolBasename}_master.yaml')).existsSync())
          m.path,
    ];
    final outermost = [
      for (final b in boundaries)
        if (!boundaries.any((o) => o != b && p.isWithin(o, b))) b,
    ];
    return (
      members: [
        for (final m in inScope)
          if (!outermost.any((b) => m.path == b || p.isWithin(b, m.path))) m,
      ],
      nestedWorkspaces: outermost,
    );
  }

  /// The always-skipped folder names of git mode's walk: those of project
  /// mode but `_ai` (the AI state is a repository of the set).
  static final Set<String> skippedFolders = {...kAlwaysSkipDirectories}
    ..remove('_ai');

  static bool _isClone(String dir) =>
      FileSystemEntity.typeSync(p.join(dir, '.git'), followLinks: false) !=
      FileSystemEntityType.notFound;

  static void _walk(
    String dir,
    String rel,
    Set<String> unmanaged,
    void Function(String rel, {bool toolOwned}) add,
  ) {
    List<FileSystemEntity> children;
    try {
      children = Directory(dir).listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final child in children) {
      if (child is! Directory) continue;
      final name = p.basename(child.path);
      final childRel = rel.isEmpty ? name : '$rel/$name';
      if (name == kWorktreesFolder ||
          (name == kQuestReposFolder && rel == kAiFolder)) {
        _toolOwned(child.path, childRel, add);
        continue;
      }
      if (name.startsWith('.') || skippedFolders.contains(name)) continue;
      if (_isClone(child.path)) {
        add(childRel);
        if (unmanaged.contains(childRel)) continue;
      }
      _walk(child.path, childRel, unmanaged, add);
    }
  }

  /// Every clone in a tool's folder ([kWorktreesFolder],
  /// [kQuestReposFolder]): a worktree (`.git` file) or a bare clone
  /// (`*.git` folder) directly in it.
  static void _toolOwned(
    String dir,
    String rel,
    void Function(String rel, {bool toolOwned}) add,
  ) {
    List<FileSystemEntity> children;
    try {
      children = Directory(dir).listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final child in children) {
      if (child is! Directory) continue;
      final name = p.basename(child.path);
      if (_isClone(child.path) ||
          (name.endsWith('.git') &&
              File(p.join(child.path, 'HEAD')).existsSync())) {
        add('$rel/$name', toolOwned: true);
      }
    }
  }
}

/// The absolute paths of every `kind: upstream` entry of the `repos.yaml`
/// at or above [start]: project mode (builds) skips them without a marker
/// file. Empty without a `repos.yaml`, and when it does not parse (a build
/// does not fail over the manifest; git mode reports it).
Set<String> upstreamPaths(String start) {
  final root = findReposRoot(start);
  if (root == null) return const {};
  try {
    final manifest = ReposManifest.parse(
      File(p.join(root, kReposManifestFile)).readAsStringSync(),
    );
    return {
      for (final e in manifest.entries)
        if (e.kind == RepoKind.upstream)
          p.join(root, p.joinAll(e.path.split('/'))),
    };
  } on Exception {
    return const {};
  }
}

/// The AI state's folder at a Tom root.
const String kAiFolder = '_ai';

/// The quest folders inside the AI state; a clone there is a quest clone.
const String kQuestsFolder = '_ai/quests';

/// The run worktrees' folder (tool-owned clones).
const String kWorktreesFolder = '.worktrees';

/// The bare clones of the multi-quest repositories, inside `_ai`.
const String kQuestReposFolder = '.quest-repos';

/// `_ai/quests.yaml`: per quest id, the branch and URL of a repo-based quest
/// (`type: repo`: its `branch`; `type: multi`: `quest/<id>` of the
/// repository its `repo:` names under `repos:`). Empty when the file is not
/// there or does not parse.
class _QuestRepos {
  static Map<String, ({String? branch, String? url})> read(String root) {
    final file = File(p.join(root, kAiFolder, 'quests.yaml'));
    if (!file.existsSync()) return const {};
    try {
      final doc = loadYaml(file.readAsStringSync());
      if (doc is! YamlMap) return const {};
      final repos = doc['repos'] is YamlMap ? doc['repos'] as YamlMap : null;
      final out = <String, ({String? branch, String? url})>{};
      final quests = doc['quests'];
      if (quests is! YamlList) return const {};
      for (final q in quests) {
        if (q is! YamlMap || q['id'] == null) continue;
        final id = '${q['id']}';
        switch (q['type']) {
          case 'repo':
            out[id] = (
              branch: q['branch']?.toString(),
              url: q['url']?.toString(),
            );
          case 'multi':
            final repo = repos?[q['repo']];
            out[id] = (
              branch: 'quest/$id',
              url: repo is YamlMap ? repo['url']?.toString() : null,
            );
        }
      }
      return out;
    } on Exception {
      return const {};
    }
  }
}
