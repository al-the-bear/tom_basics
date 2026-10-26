/// JSON fixtures matching real GitHub API responses.
library;

const testUserJson = {
  'login': 'testuser',
  'id': 12345,
  'avatar_url': 'https://avatars.githubusercontent.com/u/12345',
};

const testLabelNewJson = {
  'id': 1,
  'name': 'new',
  'color': '0000ff',
  'description': 'Issue just filed',
};

const testLabelHighJson = {
  'id': 2,
  'name': 'severity:high',
  'color': 'ff8800',
  'description': 'High severity',
};

const testLabelAnalyzedJson = {
  'id': 3,
  'name': 'analyzed',
  'color': '800080',
  'description': 'Root cause identified',
};

Map<String, dynamic> createIssueJson({
  int number = 42,
  String title = 'Array parser crashes on empty arrays',
  String? body = 'The parser throws RangeError when given []',
  String state = 'open',
  List<Map<String, dynamic>>? labels,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? closedAt,
  int comments = 0,
  String? nodeId,
}) {
  final now = DateTime.utc(2026, 2, 12, 10, 0, 0);
  return {
    'number': number,
    'title': title,
    // Emitted only when asked for, so every existing caller is unchanged.
    // `GitHubIssue.nodeId` is the GraphQL handle a transfer needs, and no
    // fixture produced one — which is why the only tests that exercised it
    // built their payloads by hand.
    if (nodeId != null) 'node_id': nodeId,
    if (body != null) 'body': body,
    'state': state,
    'labels': labels ?? [testLabelNewJson, testLabelHighJson],
    'assignee': null,
    'user': testUserJson,
    'created_at': (createdAt ?? now).toIso8601String(),
    'updated_at': (updatedAt ?? now).toIso8601String(),
    if (closedAt != null) 'closed_at': closedAt.toIso8601String(),
    'comments': comments,
    'html_url': 'https://github.com/al-the-bear/tom_issues/issues/$number',
  };
}

Map<String, dynamic> createCommentJson({
  int id = 100,
  String body = 'Root cause: missing empty check',
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final now = DateTime.utc(2026, 2, 12, 11, 0, 0);
  return {
    'id': id,
    'body': body,
    'user': testUserJson,
    'created_at': (createdAt ?? now).toIso8601String(),
    'updated_at': (updatedAt ?? now).toIso8601String(),
  };
}

Map<String, dynamic> createSearchResultJson({
  int totalCount = 1,
  bool incompleteResults = false,
  List<Map<String, dynamic>>? items,
}) {
  return {
    'total_count': totalCount,
    'incomplete_results': incompleteResults,
    'items': items ?? [createIssueJson()],
  };
}

Map<String, dynamic> createLabelJson({
  int id = 1,
  String name = 'bug',
  String color = 'ff0000',
  String? description,
}) {
  return {
    'id': id,
    'name': name,
    'color': color,
    if (description != null) 'description': description,
  };
}

/// Error response body matching GitHub API format.
Map<String, dynamic> createErrorJson({
  String message = 'Not Found',
  String? documentationUrl,
  List<Map<String, dynamic>>? errors,
}) {
  return {
    'message': message,
    if (documentationUrl != null) 'documentation_url': documentationUrl,
    if (errors != null) 'errors': errors,
  };
}
