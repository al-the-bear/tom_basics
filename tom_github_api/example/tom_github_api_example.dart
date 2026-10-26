import 'package:tom_github_api/tom_github_api.dart';

void main() async {
  final token = GitHubAuth.resolveTokenOrThrow();
  final client = GitHubApiClient(token: token);

  try {
    final issues = await client.listIssues(
      owner: 'al-the-bear',
      repo: 'tom_issues',
    );
    for (final issue in issues) {
      print('#${issue.number}: ${issue.title}');
    }
  } finally {
    client.close();
  }
}
