/// A repository as `GET /repos/{owner}/{repo}` answers.
///
/// [fullName] is the field worth knowing about: GitHub keeps a **redirect**
/// from a repository's pre-rename name, so a request for the old name succeeds
/// and answers with the *current* `full_name`. A caller that only checks
/// whether the request succeeded therefore cannot tell a live name from a
/// rename redirect — and a redirect stops working the day someone creates a new
/// repository under the freed-up name.
class GitHubRepository {
  /// GitHub's numeric id. Stable across renames, which is what makes it the
  /// only reliable way to ask "are these two names the same repository?".
  final int id;

  /// `owner/name` as the repository is spelled **today**.
  final String fullName;

  /// The bare repository name, without the owner.
  final String name;

  /// The owning user or organization.
  final String owner;

  /// The branch a request falls back to when it names none.
  final String defaultBranch;

  /// The GraphQL global node id.
  final String nodeId;

  /// Whether the repository is itself a fork of another.
  final bool isFork;

  const GitHubRepository({
    required this.id,
    required this.fullName,
    required this.name,
    required this.owner,
    required this.defaultBranch,
    required this.nodeId,
    required this.isFork,
  });

  factory GitHubRepository.fromJson(Map<String, dynamic> json) {
    final fullName = json['full_name'] as String;
    return GitHubRepository(
      id: json['id'] as int,
      fullName: fullName,
      name: json['name'] as String,
      owner: (json['owner'] as Map<String, dynamic>?)?['login'] as String? ??
          fullName.split('/').first,
      defaultBranch: json['default_branch'] as String,
      nodeId: json['node_id'] as String,
      isFork: json['fork'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'name': name,
        'owner': {'login': owner},
        'default_branch': defaultBranch,
        'node_id': nodeId,
        'fork': isFork,
      };

  @override
  String toString() => 'GitHubRepository($fullName, id: $id)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is GitHubRepository && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
