# tom_test_support

Test support any Tom package's suite can use: the repository and workspace
roots found by landmark, the Dart CLI a test may spawn, a wait for a
network-backed action, the live-GitHub credential contract, a disposable
Gitea in Docker for live git suites, and the driver that runs a Flutter
package's browser-only tests on Chrome from its ordinary suite.

License: BSD-3-Clause.

A package's `test/` directory cannot be imported from another package, so a
helper two packages' suites need is in a `lib/` that each of them names as a
**dev dependency**. Nothing a product links depends on this package.

Pure Dart: a `flutter_test` dependency would stop a pure-Dart package's suite
from resolving it. The Flutter half — `tester.pumpUntil(finder)` — is
`package:tom_reusable_ui/testing.dart`, which binds the wait here to a
`WidgetTester`. The default entry point uses `dart:io`, so it does not compile
for the web; nothing here runs in a browser.

## What is here

| Library | What it is |
| --- | --- |
| `roots.dart` | `tomFindRepositoryRoot` (the nearest `tom_repository.yaml`, or a failure naming the marker), `tomFindWorkspaceRoot` (the nearest `.tom_metadata/`, or null outside a workspace), `tomWorkspaceZtmp` (the workspace's scratch folder) and `tomFindUp`, the walk behind them. A root derived by counting `..` is right at one depth and, because what is looked for up there is usually optional, wrong at any other as a skip whose reason is untrue. |
| `dart_cli.dart` | `tomDartCli`, `requireTomDartCli`: the Dart CLI a test may spawn, located rather than taken from the runner. Under `flutter test` the runner is `flutter_tester`, which either never exits or answers wrongly; a test gets something named `dart`, or a failure naming the runner (`tomMissingDartReason`). |
| `pump_until.dart` | `tomPumpUntil`: ask a condition, let real time pass, pump a frame, until the condition holds or `TomPumpUntilTimeout` reports what was waited for and what the screen held. `pumpAndSettle` cannot wait for a load that finishes in real time while a progress indicator keeps scheduling frames. Framework-free; the `WidgetTester` binding is `tom_reusable_ui`'s. |
| `github_live.dart` | The live-GitHub contract. A live suite runs only on **two** variables — `GITHUB_TEST_TOKEN` (it *may* reach the account) and `TOM_LIVE` (it should do so *now*) — so a credentialed `dart test` skips every live suite at once: `TomGitHubLiveConfig.fromEnvironment`, `tomLiveSkipTitle`, `tomLiveSkipReason`. A classic token carrying `repo` reaches every repository the account can, so a suite that writes refuses one unless `TOM_ALLOW_WIDE_TOKEN` is set (`tomGitHubCredentialRefusal`); creating and deleting repositories needs a token of its own (`GITHUB_TEST_ADMIN_TOKEN`, `tomGitHubRepoAdminRefusal`); a suite that deliberately earns a secondary rate limit needs `TOM_EARN_SECONDARY_LIMIT`. The credential's class is `tom_github_api`'s reading (`GitHubCredential`); the policy over it is here (`TomGitHubCredentialClass`). |
| `gitea.dart` | `TomGiteaServer`: a disposable Gitea in Docker for a live git suite — `start` runs a container, makes an admin user, an access token and an initialised repository (`repositoryUrl`), `stop` removes it; `available` says whether `docker` answers, so a suite can skip without it. Gated by the suite on `TOM_LIVE` like the GitHub suites. |
| `browser_suite.dart` | `TomBrowserSuite`: a package's `@TestOn('browser')` files in `test/browser/` are skipped silently by an ordinary `flutter test`, so one VM test drives them with `flutter test --platform chrome` on the SDK it runs under (`FLUTTER_ROOT`). `skipReason` names what would make it run (`TOM_SKIP_BROWSER_TESTS=1`, no SDK, no directory); `failureOf` reports a failing exit, and a run that exited 0 without `All tests passed`, which is what a fully-skipped directory looks like. |
| `tom_test_support.dart` | All six. |

No token is held in a printable form: a `TomGitHubLiveConfig` prints its
repositories and `<withheld>`, and every sentence the contract writes names a
variable, never its value.

## Using it

```yaml
dev_dependencies:
  tom_test_support:
    path: ../../tom_ai/basics/tom_test_support
```

```dart
import 'package:test/test.dart';
import 'package:tom_test_support/github_live.dart';

void main() {
  final live = TomGitHubLiveConfig.fromEnvironment();
  test('round-trips through GitHub', () async {
    // ... uses live!.repo and live.token
  }, skip: live == null ? tomLiveSkipReason() : null);
}
```

Run one live suite directly with both variables set:

```bash
GITHUB_TEST_TOKEN=… TOM_LIVE=1 dart test test/github_storage_live_test.dart
```

## Example

`example/tom_test_support_example.dart` finds the repository it runs in, says
whether a live suite would run, and locates the Dart CLI:

```bash
dart run example/tom_test_support_example.dart
```

Status: 0.1.0 — green under `dart test`, with no network and no credential.
