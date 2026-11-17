/// The repository manifest `repos.yaml` of a Tom root, as `wssetup` reads it.
///
/// The file lists every repository of the tree: `path`, `url`, `kind`
/// (`code`, `fork`, `ai`, `binaries`, `upstream`), the `branch` it follows or,
/// for an upstream, its `pin`, and the `hosts` that clone it (absent: every
/// host; `[]`: on demand only); `links:` the symlinks, `unmanaged:` the clones
/// a tool makes and owns. Its JSON schema is
/// `.tom/json-schema/repos/repos.schema.json`; [ReposManifest.parse] checks the
/// same rules itself, so `wssetup` runs on a tree without `.tom`.
library;

import 'package:yaml/yaml.dart';

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
  });

  final String rootUrl;
  final String rootBranch;
  final List<RepoEntry> entries;
  final List<RepoLink> links;

  /// Paths of the clones a tool owns; never cloned, never walked.
  final List<String> unmanaged;

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
  };

  /// Parses [text], checking the rules of `repos.schema.json` and that no
  /// path is listed twice; throws [ReposManifestException] naming every
  /// problem.
  factory ReposManifest.parse(String text) {
    final problems = <String>[];
    final Object? doc;
    try {
      doc = loadYaml(text);
    } on YamlException catch (e) {
      throw ReposManifestException(['(file): ${e.message}']);
    }
    if (doc is! YamlMap) {
      throw ReposManifestException(['(top): not a mapping']);
    }
    for (final key in doc.keys) {
      if (!{'version', 'root', 'repos', 'links', 'unmanaged'}.contains(key)) {
        problems.add('(top): unknown key `$key`');
      }
    }
    if (doc['version'] != 1) problems.add('version: must be 1');

    var rootUrl = '';
    var rootBranch = '';
    final root = doc['root'];
    if (root is! YamlMap) {
      problems.add('root: missing (url and branch)');
    } else {
      rootUrl = _string(root, 'url', 'root', problems, _url) ?? '';
      rootBranch = _string(root, 'branch', 'root', problems, _branch) ?? '';
    }

    final entries = <RepoEntry>[];
    final repos = doc['repos'];
    if (repos is! YamlList) {
      problems.add('repos: missing (a list)');
    } else {
      for (var i = 0; i < repos.length; i++) {
        final entry = _entry(repos[i], 'repos/$i', problems);
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
    );
  }

  static RepoEntry? _entry(Object? raw, String where, List<String> problems) {
    if (raw is! YamlMap) {
      problems.add('$where: not a mapping');
      return null;
    }
    for (final key in raw.keys) {
      if (!_entryKeys.contains(key)) problems.add('$where: unknown key `$key`');
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
    if (path == null || url == null || kind == null) return null;
    return RepoEntry(
      path: path,
      url: url,
      kind: kind,
      branch: branch,
      pin: pin,
      hosts: hosts,
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
