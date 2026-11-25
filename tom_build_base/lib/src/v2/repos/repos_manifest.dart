/// The repository manifest `repos.yaml` of a Tom root: what `wssetup` clones
/// and what git mode's combined repository set ([RepoSet]) is built from.
///
/// The file lists every repository of the tree: `path`, `url`, `kind`
/// (`code`, `fork`, `ai`, `binaries`, `upstream`), the `branch` it follows or,
/// for an upstream, its `pin`, and the `hosts` that clone it (absent: every
/// host; `[]`: on demand only); `links:` the symlinks, `unmanaged:` the clones
/// a tool makes and owns. Its JSON schema is
/// `.tom/json-schema/repos/repos.schema.json`; [ReposManifest.parse] checks the
/// same rules itself, so the tools run on a tree without `.tom`.
///
/// A key the reader does not know (one a newer format adds, or one you add
/// for yourself) is no error: it is left alone and named in
/// [ReposManifest.notes]. So is a `version:` above the one the reader knows.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The manifest's file name at a Tom root.
const String kReposManifestFile = 'repos.yaml';

/// The folder holding `repos.yaml` at or above [start] (absolute), or null.
String? findReposRoot(String start) {
  var dir = p.normalize(p.absolute(start));
  while (true) {
    if (File(p.join(dir, kReposManifestFile)).existsSync()) return dir;
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}

/// This host's fleet id, which `hosts:` of an entry names: `TOM_REPOS_HOST`,
/// else `<root>/.tom/machine_id`, else derived from the host name (`mbp`,
/// `bomber`, `bigbeast`, `legiondary01`, else the host name's first label).
String reposHostId(String root) {
  final env = Platform.environment['TOM_REPOS_HOST'];
  if (env != null && env.isNotEmpty) return env;
  final file = File(p.join(root, '.tom', 'machine_id'));
  if (file.existsSync()) return file.readAsStringSync().trim();
  final h = Platform.localHostname.split('.').first.toLowerCase();
  if (h.contains('macbook') || h.contains('mbp')) return 'mbp';
  if (h.startsWith('bomber')) return 'bomber';
  if (h.startsWith('bigbeast') || h.startsWith('h2883454')) return 'bigbeast';
  if (h.startsWith('legiondary01') || h.startsWith('legion')) {
    return 'legiondary01';
  }
  return h;
}

/// A `repos.yaml` that breaks the format; [problems] says where.
class ReposManifestException implements Exception {
  ReposManifestException(this.problems);

  /// One line per problem, `<where>: <what>`.
  final List<String> problems;

  @override
  String toString() => 'repos.yaml is not valid:\n  ${problems.join('\n  ')}';
}

/// What an entry is: one of ours, a fork, the AI state, the binaries layer,
/// or a third-party project pinned to a SHA.
enum RepoKind { code, fork, ai, binaries, upstream }

/// One repository of the tree.
class RepoEntry {
  const RepoEntry({
    required this.path,
    required this.url,
    required this.kind,
    this.branch,
    this.pin,
    this.hosts,
    this.description,
  });

  /// Relative to the root, with `/`.
  final String path;

  /// The origin remote, as written.
  final String url;

  final RepoKind kind;

  /// The branch it follows (every kind but upstream).
  final String? branch;

  /// The commit an upstream is checked out at.
  final String? pin;

  /// The fleet hosts that clone it; null: every host, empty: on demand only.
  final List<String>? hosts;

  /// What the repository holds and what it is for, one line; null when the
  /// entry has none (`tom_repos --check` reports that).
  final String? description;

  /// Whether the entry is cloned only when asked for (`hosts: []`).
  bool get onDemand => hosts != null && hosts!.isEmpty;

  /// Whether [host] clones the entry without being asked.
  bool isForHost(String host) => hosts == null || hosts!.contains(host);
}

/// A symlink of the tree: [path] points to [target] (relative to its folder).
class RepoLink {
  const RepoLink(this.path, this.target);
  final String path;
  final String target;
}

/// The parsed `repos.yaml`.
class ReposManifest {
  ReposManifest({
    required this.rootUrl,
    required this.rootBranch,
    required this.entries,
    required this.links,
    required this.unmanaged,
    this.rootDescription,
    this.notes = const [],
  });

  final String rootUrl;
  final String rootBranch;

  /// The root's `description`, null when it has none.
  final String? rootDescription;
  final List<RepoEntry> entries;
  final List<RepoLink> links;

  /// Paths of the clones a tool owns; never cloned, never walked.
  final List<String> unmanaged;

  /// What the reader passed over without failing, one line each
  /// (`repos/3: unknown key `foo` (ignored)`): keys it does not know and a
  /// newer `version:`. A check names them, so a misspelt key stays visible.
  final List<String> notes;

  /// The format version this reader knows.
  static const int knownVersion = 1;

  static final _path = RegExp(r'^(?!/)(?!.*\\)(?!(.*/)?\.\.(/|$))(?!.*/$).+$');
  static final _url = RegExp(r'^(git@[^:]+:.+|https://.+)$');
  static final _branch = RegExp(r'^[^\s~^:?*\[\\]+$');
  static final _sha = RegExp(r'^[0-9a-f]{40}$');
  static const _entryKeys = {
    'path',
    'url',
    'kind',
    'branch',
    'pin',
    'describe',
    'hosts',
    'notes',
    'description',
  };

  /// Parses [text], checking the rules of `repos.schema.json` and that no
  /// path is listed twice; throws [ReposManifestException] naming every
  /// problem. Unknown keys and a newer version are [notes], not problems.
  factory ReposManifest.parse(String text) {
    final problems = <String>[];
    final notes = <String>[];
    void unknownKeys(YamlMap map, Set<String> known, String where) {
      for (final key in map.keys) {
        if (!known.contains(key)) {
          notes.add('$where: unknown key `$key` (ignored)');
        }
      }
    }

    final Object? doc;
    try {
      doc = loadYaml(text);
    } on YamlException catch (e) {
      throw ReposManifestException(['(file): ${e.message}']);
    }
    if (doc is! YamlMap) {
      throw ReposManifestException(['(top): not a mapping']);
    }
    unknownKeys(doc, const {
      'version',
      'root',
      'repos',
      'links',
      'unmanaged',
    }, '(top)');
    final version = doc['version'];
    if (version is! int || version < 1) {
      problems.add('version: must be a whole number from 1');
    } else if (version > knownVersion) {
      notes.add(
        'version: $version is newer than this reader ($knownVersion): '
        'read as version $knownVersion',
      );
    }

    var rootUrl = '';
    var rootBranch = '';
    String? rootDescription;
    final root = doc['root'];
    if (root is! YamlMap) {
      problems.add('root: missing (url and branch)');
    } else {
      rootUrl = _string(root, 'url', 'root', problems, _url) ?? '';
      rootBranch = _string(root, 'branch', 'root', problems, _branch) ?? '';
      unknownKeys(root, const {'url', 'branch', 'description'}, 'root');
      rootDescription = _description(root, 'root', problems);
    }

    final entries = <RepoEntry>[];
    final repos = doc['repos'];
    if (repos is! YamlList) {
      problems.add('repos: missing (a list)');
    } else {
      for (var i = 0; i < repos.length; i++) {
        final entry = _entry(repos[i], 'repos/$i', problems, notes);
        if (entry != null) entries.add(entry);
      }
    }

    final links = <RepoLink>[];
    final rawLinks = doc['links'];
    if (rawLinks is YamlList) {
      for (var i = 0; i < rawLinks.length; i++) {
        final l = rawLinks[i];
        if (l is! YamlMap) {
          problems.add('links/$i: not a mapping');
          continue;
        }
        unknownKeys(l, const {'path', 'target', 'notes'}, 'links/$i');
        final path = _string(l, 'path', 'links/$i', problems, _path);
        final target = _string(l, 'target', 'links/$i', problems);
        if (path != null && target != null) links.add(RepoLink(path, target));
      }
    } else if (rawLinks != null) {
      problems.add('links: must be a list');
    }

    final unmanaged = <String>[];
    final rawUnmanaged = doc['unmanaged'];
    if (rawUnmanaged is YamlList) {
      for (var i = 0; i < rawUnmanaged.length; i++) {
        final u = rawUnmanaged[i];
        final path = u is YamlMap
            ? _string(u, 'path', 'unmanaged/$i', problems, _path)
            : null;
        if (u is! YamlMap) problems.add('unmanaged/$i: not a mapping');
        if (u is YamlMap) {
          unknownKeys(u, const {'path', 'notes'}, 'unmanaged/$i');
        }
        if (path != null) unmanaged.add(path);
      }
    } else if (rawUnmanaged != null) {
      problems.add('unmanaged: must be a list');
    }

    final seen = <String>{};
    for (final p in [...entries.map((e) => e.path), ...unmanaged]) {
      if (!seen.add(p)) problems.add('$p: listed twice');
    }

    if (problems.isNotEmpty) throw ReposManifestException(problems);
    return ReposManifest(
      rootUrl: rootUrl,
      rootBranch: rootBranch,
      entries: entries,
      links: links,
      unmanaged: unmanaged,
      rootDescription: rootDescription,
      notes: notes,
    );
  }

  /// The optional one-line `description` of [map]: absent is fine, an empty
  /// or multi-line one is a problem (the schema's rule).
  static String? _description(
    YamlMap map,
    String where,
    List<String> problems,
  ) {
    if (!map.containsKey('description')) return null;
    final text = '${map['description'] ?? ''}';
    if (text.isEmpty || text.contains('\n')) {
      problems.add('$where: `description` must be one non-empty line');
      return null;
    }
    return text;
  }

  static RepoEntry? _entry(
    Object? raw,
    String where,
    List<String> problems,
    List<String> notes,
  ) {
    if (raw is! YamlMap) {
      problems.add('$where: not a mapping');
      return null;
    }
    for (final key in raw.keys) {
      if (!_entryKeys.contains(key)) {
        notes.add('$where: unknown key `$key` (ignored)');
      }
    }
    final path = _string(raw, 'path', where, problems, _path);
    final url = _string(raw, 'url', where, problems, _url);
    final kindName = _string(raw, 'kind', where, problems);
    final kind = RepoKind.values.where((k) => k.name == kindName).firstOrNull;
    if (kindName != null && kind == null) {
      problems.add('$where: unknown kind `$kindName`');
    }
    String? branch;
    String? pin;
    if (kind == RepoKind.upstream) {
      pin = _string(raw, 'pin', where, problems, _sha);
      if (raw.containsKey('branch')) {
        problems.add('$where: an upstream has a pin, not a branch');
      }
    } else if (kind != null) {
      branch = _string(raw, 'branch', where, problems, _branch);
      if (raw.containsKey('pin') || raw.containsKey('describe')) {
        problems.add('$where: only an upstream has a pin or describe');
      }
    }
    List<String>? hosts;
    final rawHosts = raw['hosts'];
    if (rawHosts is YamlList) {
      hosts = [for (final h in rawHosts) '$h'];
    } else if (rawHosts != null) {
      problems.add('$where: hosts must be a list');
    }
    final description = _description(raw, where, problems);
    if (path == null || url == null || kind == null) return null;
    return RepoEntry(
      path: path,
      url: url,
      kind: kind,
      branch: branch,
      pin: pin,
      hosts: hosts,
      description: description,
    );
  }

  static String? _string(
    YamlMap map,
    String key,
    String where,
    List<String> problems, [
    RegExp? pattern,
  ]) {
    final value = map[key];
    if (value == null) {
      problems.add('$where: `$key` missing');
      return null;
    }
    final text = '$value';
    if (pattern != null && !pattern.hasMatch(text)) {
      problems.add('$where: `$key` is not valid (`$text`)');
      return null;
    }
    return text;
  }

  /// The nearest entry whose path is a prefix of [path]; '' for the root.
  String parentOf(String path) {
    var best = '';
    for (final e in entries) {
      if (path.startsWith('${e.path}/') && e.path.length > best.length) {
        best = e.path;
      }
    }
    return best;
  }

  /// Per parent ('' for the root), the sorted anchored ignore lines of its
  /// direct children: `/<rel>/` for an entry, `/<rel>` for a link, as
  /// `tom_repos --apply` writes them.
  Map<String, List<String>> ignoreBlocks({Set<String> exclude = const {}}) {
    final blocks = <String, Set<String>>{};
    String rel(String path, String parent) =>
        parent.isEmpty ? path : path.substring(parent.length + 1);
    for (final e in entries) {
      if (exclude.contains(e.path)) continue;
      final parent = parentOf(e.path);
      blocks.putIfAbsent(parent, () => {}).add('/${rel(e.path, parent)}/');
    }
    for (final l in links) {
      final parent = parentOf(l.path);
      blocks.putIfAbsent(parent, () => {}).add('/${rel(l.path, parent)}');
    }
    return {
      for (final entry in blocks.entries)
        entry.key: (entry.value.toList()..sort()),
    };
  }
}
