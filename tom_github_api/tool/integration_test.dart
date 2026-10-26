/// Integration test against real GitHub API.
///
/// Run: dart run tool/integration_test.dart
library;

import 'dart:io';

import 'package:tom_github_api/tom_github_api.dart';

final _token = Platform.environment['GITHUB_TEST_TOKEN'] ?? '';
const _repo = 'al-the-bear-automated/tom_github_api_test';

void main() async {
  print('=== tom_github_api Integration Test ===\n');

  final client = GitHubApiClient(token: _token);

  try {
    // 1. Create an issue
    print('1. Creating issue...');
    final issue = await client.createIssue(
      repoSlug: _repo,
      title: 'Integration test issue ${DateTime.now().toIso8601String()}',
      body: 'This issue was created by the tom_github_api integration test.\n\nIt will be closed automatically.',
    );
    print('   ✓ Created issue #${issue.number}: ${issue.title}');
    print('   URL: ${issue.htmlUrl}\n');

    // 2. Create labels (if they don't exist)
    print('2. Ensuring test labels exist...');
    final labels = await client.listLabels(repoSlug: _repo);
    final labelNames = labels.map((l) => l.name).toSet();

    if (!labelNames.contains('test-label')) {
      try {
        await client.createLabel(
          repoSlug: _repo,
          name: 'test-label',
          color: '0000ff',
          description: 'Label for integration testing',
        );
        print('   ✓ Created label: test-label');
      } on GitHubValidationException {
        print('   - Label test-label already exists');
      }
    } else {
      print('   - Label test-label already exists');
    }

    // 3. Add label to issue
    print('\n3. Adding label to issue...');
    final updatedLabels = await client.addLabelsToIssue(
      repoSlug: _repo,
      issueNumber: issue.number,
      labels: ['test-label'],
    );
    print('   ✓ Issue now has ${updatedLabels.length} label(s): ${updatedLabels.map((l) => l.name).join(', ')}');

    // 4. Add a comment
    print('\n4. Adding comment...');
    final comment = await client.addComment(
      repoSlug: _repo,
      issueNumber: issue.number,
      body: 'This is an automated test comment.\n\nTimestamp: ${DateTime.now()}',
    );
    print('   ✓ Added comment #${comment.id}');

    // 5. List comments
    print('\n5. Listing comments...');
    final comments = await client.listComments(
      repoSlug: _repo,
      issueNumber: issue.number,
    );
    print('   ✓ Found ${comments.length} comment(s)');

    // 6. Search for the issue
    print('\n6. Searching issues...');
    final searchResult = await client.searchIssues(
      query: 'repo:$_repo is:issue',
    );
    print('   ✓ Search found ${searchResult.totalCount} issue(s)');

    // 7. List all issues
    print('\n7. Listing all open issues...');
    final allIssues = await client.listIssues(
      repoSlug: _repo,
      state: 'open',
    );
    print('   ✓ Found ${allIssues.length} open issue(s)');

    // 8. Close the issue
    print('\n8. Closing issue...');
    final closedIssue = await client.closeIssue(
      repoSlug: _repo,
      number: issue.number,
    );
    print('   ✓ Issue #${closedIssue.number} state: ${closedIssue.state}');

    // 9. Check rate limit
    print('\n9. Rate limit status:');
    final rateLimit = client.lastRateLimit;
    if (rateLimit != null) {
      print('   Limit: ${rateLimit.limit}');
      print('   Remaining: ${rateLimit.remaining}');
      print('   Resets at: ${rateLimit.resetAt}');
    }

    print('\n=== All tests passed! ===');
  } on GitHubException catch (e) {
    print('\n❌ GitHub API error: $e');
    if (e is GitHubValidationException && e.errors != null) {
      print('   Errors: ${e.errors}');
    }
    rethrow;
  } finally {
    client.close();
  }
}
