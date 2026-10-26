/// Minimal GitHub user representation.
class GitHubUser {
  final String login;
  final int id;
  final String? avatarUrl;

  const GitHubUser({
    required this.login,
    required this.id,
    this.avatarUrl,
  });

  factory GitHubUser.fromJson(Map<String, dynamic> json) {
    return GitHubUser(
      login: json['login'] as String,
      id: json['id'] as int,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'login': login,
        'id': id,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      };

  @override
  String toString() => 'GitHubUser($login)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GitHubUser && other.id == id && other.login == login;

  @override
  int get hashCode => Object.hash(id, login);
}
