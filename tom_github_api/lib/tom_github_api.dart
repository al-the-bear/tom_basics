/// A Dart library for interacting with the GitHub REST API v3.
///
/// Covers Issues, Labels, Comments, Search and Workflow operations (used by
/// `tom_issue_kit` and `tom_test_kit`), plus repository **contents** and the
/// low-level **git data** API — refs, commits, trees and blobs — which is what
/// lets a caller land a multi-file change as one atomic commit.
library;

export 'src/api/github_contents_api.dart';
export 'src/api/github_git_api.dart';
export 'src/auth/github_auth.dart';
export 'src/auth/github_device_flow.dart';
export 'src/github_api_client.dart';
export 'src/github_exception.dart';
export 'src/http/github_retry_policy.dart';
export 'src/models/github_comment.dart';
export 'src/models/github_conditional.dart';
export 'src/models/github_content.dart';
export 'src/models/github_git_objects.dart';
export 'src/models/github_graphql.dart';
export 'src/models/github_issue.dart';
export 'src/models/github_label.dart';
export 'src/models/github_rate_limit.dart';
export 'src/models/github_repository.dart';
export 'src/models/github_search_result.dart';
export 'src/models/github_credential.dart';
export 'src/models/github_user.dart';
export 'src/models/github_webhook.dart';
