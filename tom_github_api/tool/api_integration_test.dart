/// Comprehensive integration tests for tom_github_api against real GitHub API.
///
/// Configuration:
///   - GITHUB_TEST_TOKEN: Personal access token with repo scope
///   - GITHUB_TEST_REPO: Repository slug (default: al-the-bear-automated/tom_github_api_test)
///
/// Run: dart run tool/api_integration_test.dart
library;

import 'dart:io';

import 'package:tom_github_api/tom_github_api.dart';

// Configuration
final _token = Platform.environment['GITHUB_TEST_TOKEN'] ?? '';
final _repo = Platform.environment['GITHUB_TEST_REPO'] ?? 'al-the-bear-automated/tom_github_api_test';

// Test state
int _passCount = 0;
int _failCount = 0;
final _errors = <String>[];

void main() async {
  print('╔══════════════════════════════════════════════════════════════════╗');
  print('║        tom_github_api Comprehensive Integration Tests           ║');
  print('╚══════════════════════════════════════════════════════════════════╝\n');

  if (_token.isEmpty) {
    print('❌ GITHUB_TEST_TOKEN environment variable not set');
    exit(1);
  }

  print('Repository: $_repo');
  print('Token: ${_token.substring(0, 10)}...${_token.substring(_token.length - 4)}\n');

  final client = GitHubApiClient(token: _token);

  try {
    // ─────────────────────────────────────────────────────────────────────
    // SECTION 1: LABEL OPERATIONS
    // ─────────────────────────────────────────────────────────────────────
    await _section('1. LABEL OPERATIONS');

    // Clean up any existing test labels
    await _cleanupLabels(client);

    // 1.1 Create labels
    await _test('1.1 Create label with all fields', () async {
      final label = await client.createLabel(
        repoSlug: _repo,
        name: 'api-test-bug',
        color: 'ff0000',
        description: 'Bug reports from API tests',
      );
      _assert(label.name == 'api-test-bug', 'name matches');
      _assert(label.color == 'ff0000', 'color matches');
      _assert(label.description == 'Bug reports from API tests', 'description matches');
    });

    await _test('1.2 Create label without description', () async {
      final label = await client.createLabel(
        repoSlug: _repo,
        name: 'api-test-feature',
        color: '00ff00',
      );
      _assert(label.name == 'api-test-feature', 'name matches');
    });

    await _test('1.3 Create duplicate label throws validation error', () async {
      try {
        await client.createLabel(
          repoSlug: _repo,
          name: 'api-test-bug',
          color: 'ff0000',
        );
        _fail('Should have thrown GitHubValidationException');
      } on GitHubValidationException catch (e) {
        _assert(e.statusCode == 422, 'status is 422');
        _assert(e.errors != null && e.errors!.isNotEmpty, 'has validation errors');
      }
    });

    // 1.2 List labels
    await _test('1.4 List labels returns created labels', () async {
      final labels = await client.listLabels(repoSlug: _repo);
      final names = labels.map((l) => l.name).toSet();
      _assert(names.contains('api-test-bug'), 'contains api-test-bug');
      _assert(names.contains('api-test-feature'), 'contains api-test-feature');
    });

    // 1.3 Update label
    await _test('1.5 Update label name and color', () async {
      final label = await client.updateLabel(
        repoSlug: _repo,
        name: 'api-test-feature',
        newName: 'api-test-enhancement',
        color: '0000ff',
        description: 'Enhancement requests',
      );
      _assert(label.name == 'api-test-enhancement', 'name updated');
      _assert(label.color == '0000ff', 'color updated');
    });

    // ─────────────────────────────────────────────────────────────────────
    // SECTION 2: ISSUE OPERATIONS
    // ─────────────────────────────────────────────────────────────────────
    await _section('2. ISSUE OPERATIONS');

    // 2.1 Create issue
    late int issueNumber;
    await _test('2.1 Create issue with title only', () async {
      final issue = await client.createIssue(
        repoSlug: _repo,
        title: 'API Test: Basic issue ${DateTime.now().millisecondsSinceEpoch}',
      );
      issueNumber = issue.number;
      _assert(issue.number > 0, 'has valid number');
      _assert(issue.state == 'open', 'state is open');
      _assert(issue.body == null || issue.body!.isEmpty, 'body is empty');
    });

    late int fullIssueNumber;
    await _test('2.2 Create issue with all fields', () async {
      final issue = await client.createIssue(
        repoSlug: _repo,
        title: 'API Test: Full issue ${DateTime.now().millisecondsSinceEpoch}',
        body: 'This issue has a body.\n\n**Markdown** is supported.',
        labels: ['api-test-bug'],
      );
      fullIssueNumber = issue.number;
      _assert(issue.body != null && issue.body!.contains('Markdown'), 'body preserved');
      _assert(issue.labels.any((l) => l.name == 'api-test-bug'), 'label attached');
    });

    // 2.2 Get issue
    await _test('2.3 Get issue by number', () async {
      final issue = await client.getIssue(
        repoSlug: _repo,
        number: fullIssueNumber,
      );
      _assert(issue.number == fullIssueNumber, 'number matches');
      _assert(issue.title.contains('Full issue'), 'title matches');
    });

    await _test('2.4 Get nonexistent issue throws 404', () async {
      try {
        await client.getIssue(
          repoSlug: _repo,
          number: 999999,
        );
        _fail('Should have thrown GitHubNotFoundException');
      } on GitHubNotFoundException catch (e) {
        _assert(e.statusCode == 404, 'status is 404');
      }
    });

    // 2.3 Update issue
    await _test('2.5 Update issue title', () async {
      final issue = await client.updateIssue(
        repoSlug: _repo,
        number: issueNumber,
        title: 'API Test: Updated title',
      );
      _assert(issue.title == 'API Test: Updated title', 'title updated');
    });

    await _test('2.6 Update issue body', () async {
      final issue = await client.updateIssue(
        repoSlug: _repo,
        number: issueNumber,
        body: 'New body content',
      );
      _assert(issue.body == 'New body content', 'body updated');
    });

    // 2.4 Add/remove labels from issue
    await _test('2.7 Add labels to issue', () async {
      final labels = await client.addLabelsToIssue(
        repoSlug: _repo,
        issueNumber: issueNumber,
        labels: ['api-test-bug', 'api-test-enhancement'],
      );
      _assert(labels.length >= 2, 'has multiple labels');
      final names = labels.map((l) => l.name).toSet();
      _assert(names.contains('api-test-bug'), 'has bug label');
      _assert(names.contains('api-test-enhancement'), 'has enhancement label');
    });

    await _test('2.8 Remove label from issue', () async {
      await client.removeLabelFromIssue(
        repoSlug: _repo,
        issueNumber: issueNumber,
        label: 'api-test-enhancement',
      );
      final issue = await client.getIssue(repoSlug: _repo, number: issueNumber);
      final names = issue.labels.map((l) => l.name).toSet();
      _assert(!names.contains('api-test-enhancement'), 'enhancement label removed');
    });

    // 2.5 Close/reopen issue
    await _test('2.9 Close issue', () async {
      final issue = await client.closeIssue(
        repoSlug: _repo,
        number: issueNumber,
      );
      _assert(issue.state == 'closed', 'state is closed');
    });

    await _test('2.10 Reopen issue', () async {
      final issue = await client.reopenIssue(
        repoSlug: _repo,
        number: issueNumber,
      );
      _assert(issue.state == 'open', 'state is open');
    });

    // 2.6 List issues with filters
    await _test('2.11 List open issues', () async {
      final issues = await client.listIssues(
        repoSlug: _repo,
        state: 'open',
      );
      _assert(issues.isNotEmpty, 'has open issues');
      _assert(issues.every((i) => i.state == 'open'), 'all are open');
    });

    await _test('2.12 List issues with label filter', () async {
      final issues = await client.listIssues(
        repoSlug: _repo,
        labels: ['api-test-bug'],
      );
      _assert(issues.isNotEmpty, 'found issues with label');
    });

    await _test('2.13 List all issues (pagination)', () async {
      final allIssues = await client.listAllIssues(repoSlug: _repo);
      _assert(allIssues.isNotEmpty, 'found all issues');
    });

    // ─────────────────────────────────────────────────────────────────────
    // SECTION 3: COMMENT OPERATIONS
    // ─────────────────────────────────────────────────────────────────────
    await _section('3. COMMENT OPERATIONS');

    late int commentId;
    await _test('3.1 Add comment to issue', () async {
      final comment = await client.addComment(
        repoSlug: _repo,
        issueNumber: issueNumber,
        body: 'Test comment from API integration test.\n\nTimestamp: ${DateTime.now()}',
      );
      commentId = comment.id;
      _assert(comment.id > 0, 'has valid id');
      _assert(comment.body.contains('Test comment'), 'body preserved');
      _assert(comment.user.login.isNotEmpty, 'has user');
    });

    await _test('3.2 Add second comment', () async {
      final comment = await client.addComment(
        repoSlug: _repo,
        issueNumber: issueNumber,
        body: 'Second test comment',
      );
      _assert(comment.id != commentId, 'different id');
    });

    await _test('3.3 List comments for issue', () async {
      final comments = await client.listComments(
        repoSlug: _repo,
        issueNumber: issueNumber,
      );
      _assert(comments.length >= 2, 'has at least 2 comments');
    });

    await _test('3.4 List all comments (pagination)', () async {
      final allComments = await client.listAllComments(
        repoSlug: _repo,
        issueNumber: issueNumber,
      );
      _assert(allComments.length >= 2, 'found all comments');
    });

    // ─────────────────────────────────────────────────────────────────────
    // SECTION 4: SEARCH OPERATIONS
    // ─────────────────────────────────────────────────────────────────────
    await _section('4. SEARCH OPERATIONS');

    await _test('4.1 Search issues in repo', () async {
      final result = await client.searchIssues(
        query: 'repo:$_repo is:issue',
      );
      _assert(result.totalCount > 0, 'found issues');
      _assert(result.items.isNotEmpty, 'has items');
    });

    await _test('4.2 Search with label qualifier', () async {
      final result = await client.searchIssues(
        query: 'repo:$_repo label:api-test-bug',
      );
      _assert(result.totalCount > 0, 'found labeled issues');
    });

    await _test('4.3 Search with state qualifier', () async {
      final result = await client.searchIssues(
        query: 'repo:$_repo is:open',
      );
      _assert(result.items.every((i) => i.state == 'open'), 'all open');
    });

    await _test('4.4 Search with text query', () async {
      final result = await client.searchIssues(
        query: 'repo:$_repo "API Test"',
      );
      _assert(result.totalCount > 0, 'found by text');
    });

    // ─────────────────────────────────────────────────────────────────────
    // SECTION 5: OWNER/REPO PARAMETER FORMS
    // ─────────────────────────────────────────────────────────────────────
    await _section('5. PARAMETER FORMS');

    await _test('5.1 repoSlug form works', () async {
      final issue = await client.getIssue(
        repoSlug: _repo,
        number: issueNumber,
      );
      _assert(issue.number == issueNumber, 'found by slug');
    });

    await _test('5.2 owner/repo form works', () async {
      final parts = _repo.split('/');
      final issue = await client.getIssue(
        owner: parts[0],
        repo: parts[1],
        number: issueNumber,
      );
      _assert(issue.number == issueNumber, 'found by owner/repo');
    });

    await _test('5.3 Invalid repoSlug throws ArgumentError', () async {
      try {
        await client.getIssue(repoSlug: 'invalid-no-slash', number: 1);
        _fail('Should have thrown ArgumentError');
      } on ArgumentError {
        _pass();
      }
    });

    await _test('5.4 Missing repo throws ArgumentError', () async {
      try {
        await client.getIssue(owner: 'owner-only', number: 1);
        _fail('Should have thrown ArgumentError');
      } on ArgumentError {
        _pass();
      }
    });

    // ─────────────────────────────────────────────────────────────────────
    // SECTION 6: ERROR HANDLING
    // ─────────────────────────────────────────────────────────────────────
    await _section('6. ERROR HANDLING');

    await _test('6.1 404 returns GitHubNotFoundException', () async {
      try {
        await client.getIssue(repoSlug: _repo, number: 999999);
        _fail('Should have thrown');
      } on GitHubNotFoundException catch (e) {
        _assert(e.statusCode == 404, 'correct status');
        _assert(e.message.isNotEmpty, 'has message');
      }
    });

    await _test('6.2 Invalid repo returns 404', () async {
      try {
        await client.listIssues(repoSlug: 'nonexistent-owner/nonexistent-repo');
        _fail('Should have thrown');
      } on GitHubNotFoundException {
        _pass();
      }
    });

    await _test('6.3 Validation error has error details', () async {
      try {
        await client.createLabel(
          repoSlug: _repo,
          name: 'api-test-bug', // Already exists
          color: 'ff0000',
        );
        _fail('Should have thrown');
      } on GitHubValidationException catch (e) {
        _assert(e.statusCode == 422, 'correct status');
        _assert(e.errors != null, 'has errors array');
      }
    });

    // ─────────────────────────────────────────────────────────────────────
    // SECTION 7: RATE LIMIT TRACKING
    // ─────────────────────────────────────────────────────────────────────
    await _section('7. RATE LIMIT TRACKING');

    await _test('7.1 Rate limit info available after request', () async {
      await client.listLabels(repoSlug: _repo);
      final rateLimit = client.lastRateLimit;
      _assert(rateLimit != null, 'rate limit tracked');
      _assert(rateLimit!.limit > 0, 'has limit');
      _assert(rateLimit.remaining >= 0, 'has remaining');
      _assert(rateLimit.resetAt.isAfter(DateTime(2020)), 'has valid reset time');
    });

    await _test('7.2 Rate limit isExceeded works', () async {
      final rateLimit = client.lastRateLimit!;
      _assert(rateLimit.isExceeded == (rateLimit.remaining <= 0), 'isExceeded correct');
    });

    // ─────────────────────────────────────────────────────────────────────
    // CLEANUP
    // ─────────────────────────────────────────────────────────────────────
    await _section('8. CLEANUP');

    // Close test issues
    await _test('8.1 Close test issues', () async {
      await client.closeIssue(repoSlug: _repo, number: issueNumber);
      await client.closeIssue(repoSlug: _repo, number: fullIssueNumber);
      _pass();
    });

    // Delete test labels
    await _test('8.2 Delete test labels', () async {
      await client.deleteLabel(repoSlug: _repo, name: 'api-test-bug');
      await client.deleteLabel(repoSlug: _repo, name: 'api-test-enhancement');
      _pass();
    });

    // ─────────────────────────────────────────────────────────────────────
    // SUMMARY
    // ─────────────────────────────────────────────────────────────────────
    _printSummary();

    // Final rate limit status
    final rateLimit = client.lastRateLimit;
    if (rateLimit != null) {
      print('\nRate Limit: ${rateLimit.remaining}/${rateLimit.limit} remaining');
      print('Resets at: ${rateLimit.resetAt}');
    }
  } finally {
    client.close();
  }

  exit(_failCount > 0 ? 1 : 0);
}

// ═══════════════════════════════════════════════════════════════════════════
// TEST HELPERS
// ═══════════════════════════════════════════════════════════════════════════

Future<void> _section(String name) async {
  print('\n┌─────────────────────────────────────────────────────────────────┐');
  print('│ $name${' ' * (64 - name.length)}│');
  print('└─────────────────────────────────────────────────────────────────┘');
}

Future<void> _test(String name, Future<void> Function() body) async {
  stdout.write('  $name... ');
  try {
    await body();
    if (_failCount == 0 || !_errors.last.startsWith(name)) {
      print('✓');
      _passCount++;
    }
  } on GitHubException catch (e) {
    print('✗');
    _errors.add('$name: GitHubException(${e.statusCode}): ${e.message}');
    _failCount++;
  } catch (e) {
    print('✗');
    _errors.add('$name: $e');
    _failCount++;
  }
}

void _assert(bool condition, String message) {
  if (!condition) {
    throw AssertionError('Assertion failed: $message');
  }
}

void _pass() {
  // Explicit pass, no-op
}

void _fail(String message) {
  throw AssertionError(message);
}

void _printSummary() {
  print('\n╔══════════════════════════════════════════════════════════════════╗');
  print('║                          SUMMARY                                 ║');
  print('╠══════════════════════════════════════════════════════════════════╣');
  print('║  Passed: $_passCount${' ' * (57 - _passCount.toString().length)}║');
  print('║  Failed: $_failCount${' ' * (57 - _failCount.toString().length)}║');
  print('╚══════════════════════════════════════════════════════════════════╝');

  if (_errors.isNotEmpty) {
    print('\nFailures:');
    for (final error in _errors) {
      print('  ❌ $error');
    }
  } else {
    print('\n✅ All tests passed!');
  }
}

Future<void> _cleanupLabels(GitHubApiClient client) async {
  final labels = await client.listLabels(repoSlug: _repo);
  for (final label in labels) {
    if (label.name.startsWith('api-test-')) {
      try {
        await client.deleteLabel(repoSlug: _repo, name: label.name);
        print('  (cleaned up existing label: ${label.name})');
      } catch (_) {
        // Ignore cleanup errors
      }
    }
  }
}
