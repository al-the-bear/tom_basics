import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/fixtures.dart';

void main() {
  group('GitHubIssue', () {
    test('GH-MDL-1: fromJson parses all fields [2026-02-13 10:00]', () {
      final json = createIssueJson(
        number: 42,
        title: 'Test issue',
        body: 'Issue body',
        state: 'open',
        comments: 3,
      );

      final issue = GitHubIssue.fromJson(json);

      expect(issue.number, 42);
      expect(issue.title, 'Test issue');
      expect(issue.body, 'Issue body');
      expect(issue.state, 'open');
      expect(issue.commentsCount, 3);
      expect(issue.labels, hasLength(2));
      expect(issue.user.login, 'testuser');
      expect(issue.assignee, isNull);
      expect(issue.closedAt, isNull);
      expect(issue.htmlUrl, contains('/issues/42'));
    });

    test('GH-MDL-2: fromJson handles null body [2026-02-13 10:00]', () {
      final json = createIssueJson(body: null);
      final issue = GitHubIssue.fromJson(json);
      expect(issue.body, isNull);
    });

    test('GH-MDL-3: fromJson parses closed issue with closedAt [2026-02-13 10:00]', () {
      final closedAt = DateTime.utc(2026, 2, 12, 15, 0, 0);
      final json = createIssueJson(
        state: 'closed',
        closedAt: closedAt,
      );

      final issue = GitHubIssue.fromJson(json);

      expect(issue.state, 'closed');
      expect(issue.closedAt, closedAt);
    });

    test('GH-MDL-4: fromJson handles empty labels list [2026-02-13 10:00]', () {
      final json = createIssueJson(labels: []);
      final issue = GitHubIssue.fromJson(json);
      expect(issue.labels, isEmpty);
    });

    test('GH-MDL-5: toJson produces valid round-trip data [2026-02-13 10:00]', () {
      final json = createIssueJson();
      final issue = GitHubIssue.fromJson(json);
      final output = issue.toJson();

      expect(output['number'], 42);
      expect(output['title'], json['title']);
      expect(output['state'], 'open');
      expect(output['labels'], isList);
    });

    test('GH-MDL-6: equality based on number [2026-02-13 10:00]', () {
      final issue1 = GitHubIssue.fromJson(createIssueJson(number: 42));
      final issue2 = GitHubIssue.fromJson(createIssueJson(number: 42, title: 'Different'));
      final issue3 = GitHubIssue.fromJson(createIssueJson(number: 99));

      expect(issue1, equals(issue2));
      expect(issue1, isNot(equals(issue3)));
    });

    test('GH-MDL-7: fromJson handles missing comments field [2026-02-13 10:00]', () {
      final json = createIssueJson();
      json.remove('comments');
      final issue = GitHubIssue.fromJson(json);
      expect(issue.commentsCount, 0);
    });
  });

  group('GitHubLabel', () {
    test('GH-MDL-8: fromJson parses label [2026-02-13 10:00]', () {
      final label = GitHubLabel.fromJson(testLabelNewJson);

      expect(label.id, 1);
      expect(label.name, 'new');
      expect(label.color, '0000ff');
      expect(label.description, 'Issue just filed');
    });

    test('GH-MDL-9: equality based on name [2026-02-13 10:00]', () {
      final label1 = GitHubLabel(name: 'bug', color: 'ff0000');
      final label2 = GitHubLabel(name: 'bug', color: '00ff00');
      final label3 = GitHubLabel(name: 'feature');

      expect(label1, equals(label2));
      expect(label1, isNot(equals(label3)));
    });

    test('GH-MDL-10: toJson round-trip [2026-02-13 10:00]', () {
      final label = GitHubLabel.fromJson(testLabelNewJson);
      final output = label.toJson();

      expect(output['name'], 'new');
      expect(output['color'], '0000ff');
    });
  });

  group('GitHubComment', () {
    test('GH-MDL-11: fromJson parses comment [2026-02-13 10:00]', () {
      final json = createCommentJson(
        id: 100,
        body: 'This is a comment',
      );

      final comment = GitHubComment.fromJson(json);

      expect(comment.id, 100);
      expect(comment.body, 'This is a comment');
      expect(comment.user.login, 'testuser');
    });

    test('GH-MDL-12: equality based on id [2026-02-13 10:00]', () {
      final c1 = GitHubComment.fromJson(createCommentJson(id: 100));
      final c2 = GitHubComment.fromJson(createCommentJson(id: 100, body: 'Different'));
      final c3 = GitHubComment.fromJson(createCommentJson(id: 200));

      expect(c1, equals(c2));
      expect(c1, isNot(equals(c3)));
    });
  });

  group('GitHubUser', () {
    test('GH-MDL-13: fromJson parses user [2026-02-13 10:00]', () {
      final user = GitHubUser.fromJson(testUserJson);

      expect(user.login, 'testuser');
      expect(user.id, 12345);
      expect(user.avatarUrl, isNotNull);
    });

    test('GH-MDL-14: equality based on id and login [2026-02-13 10:00]', () {
      final u1 = GitHubUser(login: 'test', id: 1);
      final u2 = GitHubUser(login: 'test', id: 1);
      final u3 = GitHubUser(login: 'other', id: 2);

      expect(u1, equals(u2));
      expect(u1, isNot(equals(u3)));
    });
  });

  group('GitHubSearchResult', () {
    test('GH-MDL-15: fromJson parses search result [2026-02-13 10:00]', () {
      final json = createSearchResultJson(totalCount: 5);
      final result = GitHubSearchResult.fromJson(json);

      expect(result.totalCount, 5);
      expect(result.incompleteResults, isFalse);
      expect(result.items, hasLength(1));
      expect(result.items.first.number, 42);
    });
  });

  group('GitHubRateLimit', () {
    test('GH-MDL-16: fromHeaders parses rate limit [2026-02-13 10:00]', () {
      final headers = {
        'x-ratelimit-limit': '5000',
        'x-ratelimit-remaining': '4999',
        'x-ratelimit-reset': '1739350000',
      };

      final rateLimit = GitHubRateLimit.fromHeaders(headers);

      expect(rateLimit.limit, 5000);
      expect(rateLimit.remaining, 4999);
      expect(rateLimit.isExceeded, isFalse);
    });

    test('GH-MDL-17: isExceeded when remaining is 0 [2026-02-13 10:00]', () {
      final headers = {
        'x-ratelimit-limit': '5000',
        'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '1739350000',
      };

      final rateLimit = GitHubRateLimit.fromHeaders(headers);

      expect(rateLimit.isExceeded, isTrue);
    });
  });
}
