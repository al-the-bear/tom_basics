import 'github_user.dart';

/// A comment on a GitHub Issue.
class GitHubComment {
  final int id;
  final String body;
  final GitHubUser user;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GitHubComment({
    required this.id,
    required this.body,
    required this.user,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GitHubComment.fromJson(Map<String, dynamic> json) {
    return GitHubComment(
      id: json['id'] as int,
      body: json['body'] as String,
      user: GitHubUser.fromJson(json['user'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'body': body,
        'user': user.toJson(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  @override
  String toString() => 'GitHubComment(#$id by ${user.login})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is GitHubComment && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
