/// What a token is, as GitHub reports it on the wire.
///
/// GitHub distinguishes the two token families in one place: every
/// authenticated REST response carries **`x-oauth-scopes`** for a **classic**
/// PAT — listing its scopes, possibly as an empty string — and omits the
/// header entirely for a **fine-grained** one, whose permissions are
/// per-repository and are not expressible as a scope list. So the class is
/// read off the header's *presence*, and the scopes off its value.
///
/// **The fine-grained branch is unverified.** Everything here was observed
/// against a classic PAT (`x-oauth-scopes: gist, notifications, project, repo,
/// write:packages`). That a fine-grained PAT omits the header is GitHub's
/// documented behaviour and has never been met by this client — no fleet
/// host holds one — so [isFineGrained] states the inference and does not
/// claim a measurement.
class GitHubCredential {
  /// The account the token authenticates as (`GET /user`'s `login`).
  final String login;

  /// True when no `x-oauth-scopes` header came back — the fine-grained
  /// family, by inference (see the class doc).
  final bool isFineGrained;

  /// The classic token's scopes, lowercased and trimmed; empty for a
  /// fine-grained token, which reports none.
  final List<String> scopes;

  const GitHubCredential({
    required this.login,
    required this.isFineGrained,
    required this.scopes,
  });

  /// Reads the class off a response's headers, matched case-insensitively:
  /// `package:http` lowercases header names, but a caller may hand over a map
  /// from elsewhere, and matching loosely removes a way to be silently wrong.
  factory GitHubCredential.fromHeaders(
    Map<String, String> headers, {
    required String login,
  }) {
    String? raw;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'x-oauth-scopes') {
        raw = entry.value;
        break;
      }
    }
    if (raw == null) {
      return GitHubCredential(login: login, isFineGrained: true, scopes: const []);
    }
    return GitHubCredential(
      login: login,
      isFineGrained: false,
      scopes: raw
          .split(',')
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList(growable: false),
    );
  }

  /// "classic PAT with scopes: repo, project" / "fine-grained PAT (…)".
  String describe() {
    if (isFineGrained) {
      return 'fine-grained PAT (permissions are per-repository and are not '
          'reported on the wire)';
    }
    final listed = scopes.isEmpty ? '(none)' : scopes.join(', ');
    return 'classic PAT with scopes: $listed';
  }

  @override
  String toString() => 'GitHubCredential($login: ${describe()})';
}
