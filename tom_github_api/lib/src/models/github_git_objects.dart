/// A git reference (`refs/heads/main`) and the object it points at.
class GitHubGitRef {
  final String ref;
  final String sha;

  const GitHubGitRef({required this.ref, required this.sha});

  factory GitHubGitRef.fromJson(Map<String, dynamic> json) => GitHubGitRef(
        ref: json['ref'] as String,
        sha: (json['object'] as Map<String, dynamic>)['sha'] as String,
      );

  @override
  String toString() => 'GitHubGitRef($ref -> $sha)';
}

/// A commit as the git data API returns it — the object graph, not the
/// human-facing commit view of the repos API.
class GitHubGitCommit {
  final String sha;
  final String treeSha;
  final List<String> parentShas;
  final String message;

  const GitHubGitCommit({
    required this.sha,
    required this.treeSha,
    required this.parentShas,
    required this.message,
  });

  factory GitHubGitCommit.fromJson(Map<String, dynamic> json) => GitHubGitCommit(
        sha: json['sha'] as String,
        treeSha: (json['tree'] as Map<String, dynamic>)['sha'] as String,
        parentShas: [
          for (final p in (json['parents'] as List<dynamic>? ?? const []))
            (p as Map<String, dynamic>)['sha'] as String,
        ],
        message: json['message'] as String? ?? '',
      );

  @override
  String toString() => 'GitHubGitCommit($sha, tree: $treeSha)';
}

/// File modes git records in a tree. Only these four are legal in a tree
/// entry, which is why this is an enum and not a free string.
enum GitHubTreeEntryMode {
  file('100644'),
  executable('100755'),
  subdirectory('040000'),
  symlink('120000'),
  submodule('160000');

  final String code;
  const GitHubTreeEntryMode(this.code);

  static GitHubTreeEntryMode parse(String raw) =>
      GitHubTreeEntryMode.values.firstWhere(
        (m) => m.code == raw,
        orElse: () => throw ArgumentError('Unknown git tree mode: $raw'),
      );
}

/// One entry in a git tree.
///
/// A **deletion** in a `createTree` call is this entry with a null [sha] — git
/// reads "path present, object absent" as "remove it from the base tree".
class GitHubTreeEntry {
  final String path;
  final GitHubTreeEntryMode mode;

  /// `blob` or `tree`.
  final String type;

  /// The object sha, or `null` to delete [path] from the base tree.
  final String? sha;

  final int? size;

  const GitHubTreeEntry({
    required this.path,
    this.mode = GitHubTreeEntryMode.file,
    this.type = 'blob',
    this.sha,
    this.size,
  });

  /// A tree entry that removes [path] relative to the base tree.
  const GitHubTreeEntry.deletion(this.path)
      : mode = GitHubTreeEntryMode.file,
        type = 'blob',
        sha = null,
        size = null;

  factory GitHubTreeEntry.fromJson(Map<String, dynamic> json) => GitHubTreeEntry(
        path: json['path'] as String,
        mode: GitHubTreeEntryMode.parse(json['mode'] as String),
        type: json['type'] as String,
        sha: json['sha'] as String?,
        size: (json['size'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'mode': mode.code,
        'type': type,
        // `sha: null` is meaningful here (a deletion) and must be sent, not
        // omitted — omitting it would make the entry invalid instead.
        'sha': sha,
      };

  bool get isBlob => type == 'blob';

  @override
  String toString() => 'GitHubTreeEntry($path, $type, sha: $sha)';
}

/// A git tree listing.
class GitHubTree {
  final String sha;
  final List<GitHubTreeEntry> entries;

  /// GitHub caps a recursive tree response; when this is set the listing is
  /// incomplete and must be walked level by level instead.
  final bool truncated;

  const GitHubTree({
    required this.sha,
    required this.entries,
    required this.truncated,
  });

  factory GitHubTree.fromJson(Map<String, dynamic> json) => GitHubTree(
        sha: json['sha'] as String,
        entries: [
          for (final e in (json['tree'] as List<dynamic>? ?? const []))
            GitHubTreeEntry.fromJson(e as Map<String, dynamic>),
        ],
        truncated: json['truncated'] as bool? ?? false,
      );

  /// Blob entries whose path is inside [prefix] (a `/`-separated directory
  /// path, without a trailing slash), keyed by path relative to [prefix].
  Map<String, GitHubTreeEntry> blobsUnder(String prefix) {
    final root = prefix.isEmpty ? '' : '$prefix/';
    return {
      for (final e in entries)
        if (e.isBlob && e.path.startsWith(root))
          e.path.substring(root.length): e,
    };
  }
}
