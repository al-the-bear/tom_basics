/// Test support for code that talks to GitHub: an in-memory GitHub.
///
/// [FakeGitHubServer] serves the git data API (refs, commits, trees, blobs
/// with real content addressing and the non-fast-forward refusal), the
/// contents API, and issues, labels, comments and search, behind an
/// `http.Client` that any caller — a [GitHubApiClient] included — is handed in
/// place of the network. The canned responses ([rateLimited],
/// [secondaryRateLimited], [serverError], [unauthorized]) drive a caller's
/// backoff and failure paths.
///
/// This is a separate entry point so that nothing importing
/// `package:tom_github_api/tom_github_api.dart` links a test double. Import it
/// from tests only.
library;

import 'tom_github_api.dart';

export 'src/testing/fake_github_server.dart';
