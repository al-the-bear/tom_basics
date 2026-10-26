/// tom_git against GitHub: list, clone, commit, push, a lost race, delete —
/// on a branch of its own in the scratch repository, removed at the end.
///
/// Runs on `GITHUB_TEST_TOKEN` with `TOM_LIVE` set (package:tom_test_support's
/// live contract). Nothing here needs a git binary.
@Tags(['live'])
@Timeout(Duration(minutes: 5))
library;

import 'package:test/test.dart';
import 'package:tom_git/tom_git.dart';
import 'package:tom_test_support/github_live.dart';

import 'support/live_scenario.dart';

void main() {
  final config = TomGitHubLiveConfig.fromEnvironment();
  if (config == null) {
    test('GIT-LIVE-GH', () {}, skip: tomLiveSkipTitle('the GitHub live suite'));
    return;
  }
  liveScenario(
    'GIT-LIVE-GH',
    url: Uri.parse('https://github.com/${config.repo}.git'),
    credentials: (_) async => GitCredentials.token(config.token),
  );
}
