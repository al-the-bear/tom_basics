/// The live-GitHub **credential contract**, with no test framework in it.
///
/// A live suite reaches a real GitHub account. Whether it may, and whether it
/// should right now, is decided here once, so a rule is not enforced in one
/// package's suites and absent in another's. What *registers* a live test
/// needs `package:test` (or `flutter_test`, for a Flutter package), so that
/// stays with the suite; this library needs `dart:io` and the GitHub client's
/// reading of a credential, and nothing else.
///
/// Nothing here holds a token in a printable form: [TomGitHubLiveConfig]'s
/// `toString` names the repositories and withholds the token, and every
/// sentence below names a variable, never its value.
library;

import 'dart:io';

import 'package:tom_github_api/tom_github_api.dart';

/// The credential for the live suites. **The requirement is a set of
/// permissions, not a kind of token.**
///
/// **Contents: read & write** covers every git-data call a storage backend
/// makes (blobs, trees, commits, refs) and the `PUT /contents/{path}` that
/// authors a repository's first commit; **Issues: read & write** covers an
/// issue-backed store; **Metadata: read** is what `GET /repos/{o}/{r}` needs
/// and comes with a fine-grained token mandatorily. A classic PAT's `repo`
/// subsumes all three.
///
/// A classic PAT carrying `repo` can write to every repository the account
/// can reach, and keeping a suite to the scratch repository by [tomGitHubRepoVar]
/// and a per-run branch is a convention rather than a boundary — so a suite
/// that creates branches refuses one ([tomGitHubCredentialRefusal]) unless
/// [tomWideTokenVar] says otherwise.
///
/// Three things need more than the set above, and each has a gate of its own:
/// transferring an issue wants Issues: write on **two** repositories
/// ([tomGitHubRepo2Var]); creating and deleting repositories wants
/// **account**-level Administration, on its own token
/// ([tomGitHubRepoAdminTokenVar]); and the Projects v2 GraphQL surface wants
/// user/org-level Projects, which is not a repository permission.
const tomGitHubTokenVar = 'GITHUB_TEST_TOKEN';

/// The opt-in that says **now**, where [tomGitHubTokenVar] only says *may*.
///
/// A token in the environment is the normal state of a developer machine — it
/// is there for `gh`, for an app, for a runner started an hour ago — and it is
/// what every test run inherits. With the token alone enabling the live
/// suites, a plain `dart test` over a package starts all of them at once; held
/// off one repository by a lock, together they outlast what a `setUpAll` may
/// take, and the run ends in failures about scheduling and nothing else.
///
/// So a live suite runs only when BOTH are set. A package's live runner sets
/// this one for its child, which keeps the sanctioned path one command; a
/// developer running one suite directly sets it by hand:
///
/// ```bash
/// TOM_LIVE=1 dart test test/github_storage_live_test.dart
/// ```
///
/// A plain `dart test` with the token and without this reports every live
/// suite as an immediate, legible skip naming both variables: consent to a
/// permission is not consent to spend the time.
const tomLiveVar = 'TOM_LIVE';

/// Whether [tomLiveVar] is set in [environment] (default: this process').
bool tomLiveEnabled([Map<String, String>? environment]) =>
    _flag((environment ?? Platform.environment)[tomLiveVar]);

/// `owner/repo` of a scratch repository the token can write to.
const tomGitHubRepoVar = 'GITHUB_TEST_REPO';

/// Optional second repository, same owner, for the issue-transfer test.
const tomGitHubRepo2Var = 'GITHUB_TEST_REPO_2';

/// The workspace's shared scratch repository.
const tomDefaultGitHubTestRepo = 'al-the-bear-automated/tom_github_api_test';

/// The credential for suites that **create and delete whole repositories** —
/// a token of its own, never [tomGitHubTokenVar].
///
/// A fine-grained PAT needs account-level **Administration: write** (plus
/// Contents), and a classic PAT needs `delete_repo` on top of `repo`, which
/// does not imply it. Putting that on the token every live suite reads would
/// let every credentialed machine delete repositories; on a variable of its
/// own it sits on a token exactly the suites that need it read. Configuring it
/// is also the agreement, so no separate opt-in is needed.
const tomGitHubRepoAdminTokenVar = 'GITHUB_TEST_ADMIN_TOKEN';

/// The repository-administration token, or null when
/// [tomGitHubRepoAdminTokenVar] is unset or empty — or when [tomLiveVar] is
/// not set, because a suite reading it reaches the real account like every
/// other live suite and the gate is about *when*, not about which token.
String? get tomGitHubRepoAdminToken {
  if (!tomLiveEnabled()) return null;
  final value = Platform.environment[tomGitHubRepoAdminTokenVar];
  return (value == null || value.isEmpty) ? null : value;
}

/// Why [credential] must not be used to create repositories, or null when it
/// may.
///
/// Decided before anything is created, because the failure it prevents is
/// asymmetric and permanent: `POST /user/repos` needs only `repo`, and
/// `DELETE /repos/{o}/{r}` needs `delete_repo`, so a classic token with the
/// first and not the second makes a repository in a real account and then
/// cannot remove it. A fine-grained token is let through — its permissions are
/// not reported on the wire, and refusing it would refuse the intended
/// credential; a deletion it cannot perform is the suite's to raise, loudly.
String? tomGitHubRepoAdminRefusal(TomGitHubCredentialClass credential) {
  if (credential.isFineGrained) return null;
  final missing = [
    if (!credential.scopes.contains('repo')) '`repo` (to create)',
    if (!credential.scopes.contains('delete_repo')) '`delete_repo` (to delete)',
  ];
  if (missing.isEmpty) return null;
  return '$tomGitHubRepoAdminTokenVar is a ${credential.describe()}, which '
      'lacks ${missing.join(' and ')}. This suite creates a repository per '
      'test and deletes it afterwards; without both it would leave '
      'repositories behind in a real account, so nothing has been created. '
      'Add the missing scope to the token, or use a fine-grained PAT with '
      'account-level Administration: write plus Contents: read & write.';
}

/// The opt-in for a live suite that **deliberately earns a secondary rate
/// limit**.
///
/// A gate of its own for the reason [tomGitHubRepoAdminTokenVar] is:
/// configuring [tomGitHubTokenVar] for the round-trip suites is not agreeing
/// to have the account refused by GitHub for a while. The limit is
/// account-wide, so while it holds every other client of the token is refused
/// too, and an escalation to a content-creation block can last tens of
/// minutes.
const tomEarnSecondaryLimitVar = 'TOM_EARN_SECONDARY_LIMIT';

/// Whether [tomEarnSecondaryLimitVar] is set.
bool get tomEarnSecondaryLimitEnabled =>
    _flag(Platform.environment[tomEarnSecondaryLimitVar]);

/// The opt-out for a credential wider than the live contract.
///
/// Set it and a classic PAT carrying `repo` is accepted instead of refused. It
/// exists so the refusal is a *contract*, not a wall: a developer who has only
/// a classic token can still run the suites, and has to say so — which is the
/// difference between a boundary and a convention.
const tomWideTokenVar = 'TOM_ALLOW_WIDE_TOKEN';

/// Whether [tomWideTokenVar] is set.
bool get tomWideTokenAllowed => _flag(Platform.environment[tomWideTokenVar]);

bool _flag(String? value) => value != null && value.isNotEmpty && value != '0';

/// What kind of credential the live suites were handed, and how far it
/// reaches.
///
/// GitHub distinguishes the two token families on the wire and nowhere else:
/// every authenticated REST response carries **`x-oauth-scopes`** for a
/// **classic** PAT — listing its scopes, possibly as an empty string — and
/// omits the header for a **fine-grained** one, whose permissions are
/// per-repository and not expressible as a scope list. The reading is the
/// client's ([GitHubCredential]); what the live suites refuse on the strength
/// of it is policy and lives here.
class TomGitHubCredentialClass {
  /// The fact, as the client parsed it.
  final GitHubCredential credential;

  const TomGitHubCredentialClass(this.credential);

  /// True when no `x-oauth-scopes` header came back — the fine-grained
  /// family, by inference.
  bool get isFineGrained => credential.isFineGrained;

  /// The classic token's scopes, lowercased and trimmed; empty for a
  /// fine-grained token.
  List<String> get scopes => credential.scopes;

  /// Whether this credential can write to **every repository the account can
  /// reach**, rather than to the scratch repository alone.
  ///
  /// `repo` is classic's all-or-nothing repository scope: there is no classic
  /// scope for "one repository", which is the reason the fine-grained family
  /// exists. `public_repo` is narrower but still account-wide across public
  /// repositories, so it counts too.
  bool get reachesEveryRepository =>
      !isFineGrained &&
      (scopes.contains('repo') || scopes.contains('public_repo'));

  /// The credential in words, without its secret.
  String describe() => credential.describe();
}

/// Classifies a credential from the headers of any authenticated response.
///
/// A pure function over headers so it can be tested without a network and
/// without a token — which matters here, because what it decides is a
/// *refusal*, and a refusal exercised against one real token only is a
/// refusal nobody can predict.
TomGitHubCredentialClass tomClassifyGitHubCredential(
  Map<String, String> headers, {
  String login = '',
}) => TomGitHubCredentialClass(
  GitHubCredential.fromHeaders(headers, login: login),
);

/// What a live suite should do when handed [credential].
///
/// Null when the run may proceed, or the message to fail with. Split from the
/// enforcement so the decision is testable offline.
String? tomGitHubCredentialRefusal(
  TomGitHubCredentialClass credential, {
  required bool wideAllowed,
}) {
  if (!credential.reachesEveryRepository) return null;
  if (wideAllowed) return null;
  return 'The live suites were handed a ${credential.describe()}.\n'
      "`repo` is classic's all-or-nothing repository scope, so this token can "
      'write to EVERY repository the account can reach. The suites are kept to '
      'the scratch repository by the $tomGitHubRepoVar convention and a '
      'per-run branch — which is a convention, not a boundary: a bug in a '
      'locator, or a mistaken default, would be free to write anywhere.\n'
      'Mint a fine-grained PAT scoped to the one scratch repository, with '
      'Contents: read & write (and Issues: read & write for an issue-backed '
      'suite), or set $tomWideTokenVar=1 to accept the wider blast radius '
      'deliberately.';
}

/// Credentials for a live GitHub suite, or null when none are configured.
class TomGitHubLiveConfig {
  final String repo;
  final String token;
  final String? repo2;

  const TomGitHubLiveConfig({
    required this.repo,
    required this.token,
    this.repo2,
  });

  /// Reads [environment] (default: this process'), or returns null when
  /// [tomGitHubTokenVar] or [tomLiveVar] is unset.
  ///
  /// Two gates, for two different facts: the token says the suite *may* reach
  /// the account, and [tomLiveVar] says it should do so *now*. The repository
  /// has a workspace default and gates nothing.
  static TomGitHubLiveConfig? fromEnvironment({
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    if (!tomLiveEnabled(env)) return null;
    final token = env[tomGitHubTokenVar];
    if (token == null || token.isEmpty) return null;
    final repo = env[tomGitHubRepoVar];
    final repo2 = env[tomGitHubRepo2Var];
    return TomGitHubLiveConfig(
      repo: (repo == null || repo.isEmpty) ? tomDefaultGitHubTestRepo : repo,
      token: token,
      repo2: (repo2 == null || repo2.isEmpty) ? null : repo2,
    );
  }

  /// The repositories, and that a token is held — never the token, so a
  /// config that reaches a log or a failure message carries no secret.
  @override
  String toString() =>
      'TomGitHubLiveConfig(repo: $repo'
      '${repo2 == null ? '' : ', repo2: $repo2'}, token: <withheld>)';
}

/// The gates a live suite needs, as a sentence — "set X and Y to run Z".
///
/// A pure function rather than a string built at each call site, because a
/// suite that is silently off is indistinguishable from one that passed, and
/// two wordings would let a reader scanning a run for "skipped" find one and
/// miss the other.
///
/// [tokenVar] is the credential variable that enables the suite — the shared
/// [tomGitHubTokenVar] for every suite but one that reads its own.
String tomLiveSkipTitle(
  String what, {
  List<String> extraVars = const [],
  String tokenVar = tomGitHubTokenVar,
}) =>
    'set ${[tokenVar, tomLiveVar, ...extraVars].join(' and ')} '
    'to run $what';

/// Why a live suite did not run, for the reporter's `skip:` field.
///
/// [because] says what an extra gate is protecting against: a suite whose
/// second gate is unexplained gets switched on by whoever reads the name and
/// guesses.
String tomLiveSkipReason({
  List<String> extraVars = const [],
  String? because,
  String tokenVar = tomGitHubTokenVar,
}) =>
    'set ${[tokenVar, tomLiveVar, ...extraVars].join(' and ')}'
    // Only the shared token's suites work in the scratch repository; one with
    // its own credential makes its repositories itself.
    '${tokenVar == tomGitHubTokenVar ? ' (and optionally $tomGitHubRepoVar, '
              'default $tomDefaultGitHubTestRepo)' : ''} to enable'
    // Said here because the skip is where a developer meets the gate.
    ' — $tomLiveVar is what a package\'s live runner sets for its child, or '
    'set it by hand to run one suite'
    '${because == null ? '' : '. $because'}';
