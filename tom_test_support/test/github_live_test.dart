/// The live gate and the credential contract.
///
/// A credential says a suite MAY reach the account, `TOM_LIVE` says it should
/// do so NOW, and a suite runs only on both. Injected environments and
/// headers, because `Platform.environment` cannot be set from inside a test
/// and a refusal should be predictable without holding a token of each kind.
library;

import 'package:test/test.dart';
import 'package:tom_test_support/github_live.dart';

/// A value no test would write by accident, so finding it in a sentence
/// means the sentence carried the token.
const _secret = 'ghp_SECRET0123456789abcdef';

void main() {
  final classic = tomClassifyGitHubCredential({'x-oauth-scopes': 'repo, gist'});
  final narrow = tomClassifyGitHubCredential({'x-oauth-scopes': 'gist'});
  final fineGrained = tomClassifyGitHubCredential(const {});

  group('TSUP-LIVE the live gate', () {
    test('TSUP-LIVE-1: a token alone enables nothing', () {
      expect(
        TomGitHubLiveConfig.fromEnvironment(
          environment: {tomGitHubTokenVar: _secret},
        ),
        isNull,
      );
    });

    test('TSUP-LIVE-2: the opt-in alone enables nothing either', () {
      expect(
        TomGitHubLiveConfig.fromEnvironment(environment: {tomLiveVar: '1'}),
        isNull,
      );
    });

    test('TSUP-LIVE-3: both together enable, with the workspace default '
        'repository', () {
      final config = TomGitHubLiveConfig.fromEnvironment(
        environment: {tomGitHubTokenVar: _secret, tomLiveVar: '1'},
      );
      expect(config, isNotNull);
      expect(config!.token, _secret);
      expect(config.repo, tomDefaultGitHubTestRepo);
      expect(config.repo2, isNull);
    });

    test("TSUP-LIVE-4: '0' and the empty string are not set", () {
      for (final value in ['0', '']) {
        expect(
          TomGitHubLiveConfig.fromEnvironment(
            environment: {tomGitHubTokenVar: _secret, tomLiveVar: value},
          ),
          isNull,
          reason: '$tomLiveVar=$value must read as unset',
        );
      }
      expect(tomLiveEnabled({tomLiveVar: '0'}), isFalse);
      expect(tomLiveEnabled({tomLiveVar: '1'}), isTrue);
    });

    test('TSUP-LIVE-5: the skip names both variables, so the gate is met '
        'where a developer meets it', () {
      expect(tomLiveSkipTitle('x'), contains(tomLiveVar));
      expect(tomLiveSkipTitle('x'), contains(tomGitHubTokenVar));
      expect(tomLiveSkipReason(), contains(tomLiveVar));
      expect(tomLiveSkipReason(), contains(tomGitHubRepoVar));
      expect(
        tomLiveSkipReason(tokenVar: tomGitHubRepoAdminTokenVar),
        isNot(contains(tomGitHubRepoVar)),
        reason: 'a suite with its own credential makes its own repositories',
      );
      expect(
        tomLiveSkipReason(because: 'It costs quota.'),
        endsWith('. It costs quota.'),
      );
    });
  });

  group('TSUP-CRED the credential contract', () {
    test('TSUP-CRED-1: a classic token with repo reaches every repository; '
        'a fine-grained one and a narrow classic one do not', () {
      expect(classic.reachesEveryRepository, isTrue);
      expect(narrow.reachesEveryRepository, isFalse);
      expect(fineGrained.isFineGrained, isTrue);
      expect(fineGrained.reachesEveryRepository, isFalse);
    });

    test('TSUP-CRED-2: a wide token is refused unless the opt-out says so', () {
      final refusal = tomGitHubCredentialRefusal(classic, wideAllowed: false);
      expect(refusal, contains(tomWideTokenVar));
      expect(tomGitHubCredentialRefusal(classic, wideAllowed: true), isNull);
      expect(tomGitHubCredentialRefusal(narrow, wideAllowed: false), isNull);
    });

    test('TSUP-CRED-3: repository administration needs repo and delete_repo '
        'on a classic token, and lets a fine-grained one through', () {
      expect(tomGitHubRepoAdminRefusal(classic), contains('delete_repo'));
      expect(
        tomGitHubRepoAdminRefusal(
          tomClassifyGitHubCredential({'x-oauth-scopes': 'repo, delete_repo'}),
        ),
        isNull,
      );
      expect(tomGitHubRepoAdminRefusal(fineGrained), isNull);
    });
  });

  group('TSUP-REDACT no token in a printable form', () {
    test('TSUP-REDACT-1: a config prints its repositories and withholds the '
        'token', () {
      final config = TomGitHubLiveConfig.fromEnvironment(
        environment: {
          tomGitHubTokenVar: _secret,
          tomLiveVar: '1',
          tomGitHubRepo2Var: 'o/r2',
        },
      )!;
      final printed = '$config';
      expect(printed, contains(tomDefaultGitHubTestRepo));
      expect(printed, contains('o/r2'));
      expect(printed, contains('<withheld>'));
      expect(printed, isNot(contains(_secret)));
    });

    test('TSUP-REDACT-2: negative control — the token is held, so the '
        'withholding is a choice and not an empty field', () {
      final config = TomGitHubLiveConfig(repo: 'o/r', token: _secret);
      expect(config.token, _secret);
      expect('$config', isNot(contains(_secret)));
    });

    test('TSUP-REDACT-3: no sentence the contract writes carries a value', () {
      final sentences = [
        tomLiveSkipTitle('x'),
        tomLiveSkipReason(),
        tomGitHubCredentialRefusal(classic, wideAllowed: false)!,
        tomGitHubRepoAdminRefusal(classic)!,
      ];
      for (final sentence in sentences) {
        expect(sentence, isNot(contains(_secret)));
        expect(sentence, isNot(contains('ghp_')));
      }
    });
  });
}
