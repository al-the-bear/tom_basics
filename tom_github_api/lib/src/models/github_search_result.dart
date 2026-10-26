import 'github_issue.dart';

/// Result of a GitHub Issues search query.
class GitHubSearchResult {
  final int totalCount;
  final bool incompleteResults;
  final List<GitHubIssue> items;

  const GitHubSearchResult({
    required this.totalCount,
    required this.incompleteResults,
    required this.items,
  });

  factory GitHubSearchResult.fromJson(Map<String, dynamic> json) {
    return GitHubSearchResult(
      totalCount: json['total_count'] as int,
      incompleteResults: json['incomplete_results'] as bool? ?? false,
      items: (json['items'] as List<dynamic>)
          .map((i) => GitHubIssue.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  String toString() =>
      'GitHubSearchResult($totalCount results, ${items.length} items)';
}
