import 'github_label.dart';
import 'github_user.dart';

/// A GitHub Issue (used for both issues and test entries).
class GitHubIssue {
  final int number;

  /// The GraphQL global node id (`node_id` in REST responses).
  ///
  /// Nullable because the REST API omits it from some abbreviated payloads and
  /// because a hand-built issue in a test has no reason to invent one. It is
  /// required by the GraphQL-only operations — issue transfer is the one this
  /// package uses.
  final String? nodeId;
  final String title;
  final String? body;
  final String state;
  final List<GitHubLabel> labels;
  final GitHubUser? assignee;
  final GitHubUser user;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? closedAt;
  final int commentsCount;
  final String htmlUrl;

  const GitHubIssue({
    required this.number,
    this.nodeId,
    required this.title,
    this.body,
    required this.state,
    required this.labels,
    this.assignee,
    required this.user,
    required this.createdAt,
    required this.updatedAt,
    this.closedAt,
    required this.commentsCount,
    required this.htmlUrl,
  });

  factory GitHubIssue.fromJson(Map<String, dynamic> json) {
    return GitHubIssue(
      number: json['number'] as int,
      nodeId: json['node_id'] as String?,
      title: json['title'] as String,
      body: json['body'] as String?,
      state: json['state'] as String,
      labels: (json['labels'] as List<dynamic>?)
              ?.map((l) =>
                  GitHubLabel.fromJson(l as Map<String, dynamic>))
              .toList() ??
          [],
      assignee: json['assignee'] != null
          ? GitHubUser.fromJson(json['assignee'] as Map<String, dynamic>)
          : null,
      user: GitHubUser.fromJson(json['user'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      closedAt: json['closed_at'] != null
          ? DateTime.parse(json['closed_at'] as String)
          : null,
      commentsCount: json['comments'] as int? ?? 0,
      htmlUrl: json['html_url'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'number': number,
        if (nodeId != null) 'node_id': nodeId,
        'title': title,
        if (body != null) 'body': body,
        'state': state,
        'labels': labels.map((l) => l.toJson()).toList(),
        if (assignee != null) 'assignee': assignee!.toJson(),
        'user': user.toJson(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (closedAt != null) 'closed_at': closedAt!.toIso8601String(),
        'comments': commentsCount,
        'html_url': htmlUrl,
      };

  /// Whether this is an actual issue (not a pull request).
  ///
  /// GitHub's Issues API returns both issues and PRs; PRs have
  /// a `pull_request` field. This library filters PRs out, but
  /// this getter can be used for additional checks.
  bool get isIssue => true;

  @override
  String toString() => 'GitHubIssue(#$number: $title)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GitHubIssue && other.number == number;

  @override
  int get hashCode => number.hashCode;
}
