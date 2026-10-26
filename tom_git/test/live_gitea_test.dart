/// tom_git against a self-hosted Gitea in Docker: the same scenario the
/// GitHub suite runs, on a second implementation of the protocol.
///
/// Runs with `TOM_LIVE` set and `docker` available; the server is created for
/// the run and removed after it.
@Tags(['live'])
@Timeout(Duration(minutes: 6))
library;

import 'package:test/test.dart';
import 'package:tom_git/tom_git.dart';
import 'package:tom_test_support/github_live.dart';

import 'package:tom_test_support/gitea.dart';
import 'support/live_scenario.dart';

Future<void> main() async {
  if (!tomLiveEnabled() || !await TomGiteaServer.available()) {
    test(
      'GIT-LIVE-GITEA',
      () {},
      skip:
          'set $tomLiveVar and have docker running to run the Gitea '
          'live suite',
    );
    return;
  }
  final server = await TomGiteaServer.start();
  tearDownAll(server.stop);
  liveScenario(
    'GIT-LIVE-GITEA',
    url: server.repositoryUrl,
    credentials: (_) async => GitCredentials(server.user, server.token),
    expectDefaultBranch: 'main',
  );
}
