/// A run of a GitHub Actions workflow.
class GitHubWorkflowRun {
  final int id;

  /// `queued`, `in_progress`, `completed`, ...
  final String status;

  /// `success`, `failure`, `cancelled`, ...; null until the run completed.
  final String? conclusion;

  final DateTime? createdAt;
  final String? htmlUrl;

  /// What started the run, e.g. `workflow_dispatch`.
  final String? event;

  const GitHubWorkflowRun({
    required this.id,
    required this.status,
    this.conclusion,
    this.createdAt,
    this.htmlUrl,
    this.event,
  });

  /// Whether the run has finished (its [conclusion] is set).
  bool get isCompleted => status == 'completed';

  factory GitHubWorkflowRun.fromJson(Map<String, dynamic> json) {
    final created = json['created_at'] as String?;
    return GitHubWorkflowRun(
      id: json['id'] as int,
      status: json['status'] as String? ?? 'unknown',
      conclusion: json['conclusion'] as String?,
      createdAt: created == null ? null : DateTime.parse(created),
      htmlUrl: json['html_url'] as String?,
      event: json['event'] as String?,
    );
  }

  @override
  String toString() => 'GitHubWorkflowRun($id, $status, $conclusion)';
}
