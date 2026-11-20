# Tom Test Support

Tom Test Support is the helper library Tom packages' test suites share: finding
the repository and workspace roots, locating the Dart CLI, waiting for a
condition, gating live GitHub suites, running a disposable Gitea, driving
browser-only tests, proxying for CORS, reaping exactly the processes a test
started, working in a clone of the workspace, and auditing the licences an
application links. It is framework-free — it answers skip reasons, failures and
values, and the caller's `package:test` or `flutter_test` asserts on them — and
it is meant to be a **dev dependency** only.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Roots by Landmark](#roots-by-landmark)
- [The Dart CLI](#the-dart-cli)
- [Waiting: tomPumpUntil and tomSettleUntil](#waiting-tompumpuntil-and-tomsettleuntil)
- [The Live-GitHub Contract](#the-live-github-contract)
- [A Disposable Gitea](#a-disposable-gitea)
- [Browser Suites](#browser-suites)
- [The CORS Proxy](#the-cors-proxy)
- [Process Trees](#process-trees)
- [The Workspace Clone](#the-workspace-clone)
- [The Licence Audit](#the-licence-audit)
- [Error Handling](#error-handling)
- [Best Practices](#best-practices)

## Overview

Each library is its own entry point; `tom_test_support.dart` exports them all.

| Symbol | Kind | Library | Purpose |
| ------ | ---- | ------- | ------- |
| `tomFindRepositoryRoot` | function | `roots.dart` | The nearest directory holding `tom_repository.yaml`; throws without one |
| `tomFindWorkspaceRoot` | function | `roots.dart` | The nearest directory holding `buildkit_master.yaml`, or null |
| `tomWorkspaceZtmp` | function | `roots.dart` | The workspace's `ztmp` folder, created on demand |
| `tomFindUp` | function | `roots.dart` | The upward walk for a landmark |
| `tomRepositoryMarker` / `tomWorkspaceMarker` | constants | `roots.dart` | `tom_repository.yaml` / `buildkit_master.yaml` |
| `tomDartCli` / `requireTomDartCli` | functions | `dart_cli.dart` | The Dart CLI a test may spawn: null / a `StateError` when there is none |
| `tomDartFrom` / `tomDartOnPath` | functions | `dart_cli.dart` | The two steps behind `tomDartCli` |
| `tomMissingDartReason` | function | `dart_cli.dart` | Why no Dart CLI was found, as a sentence |
| `tomPumpUntil` | function | `pump_until.dart` | Pump frames and let real time pass until a condition holds |
| `TomPumpUntilTimeout` | exception | `pump_until.dart` | What was waited for, how long, and what was on screen |
| `tomDefaultPumpUntilTimeout` / `tomDefaultPumpUntilStep` | constants | `pump_until.dart` | 2 minutes / 250 ms |
| `tomSettleUntil` | function | `settle.dart` | Read until a value is accepted, with back-off |
| `TomSettleTimeout` | exception | `settle.dart` | What was waited for and the last value read |
| `tomLiveSettleTimeout` / `tomLiveSettleSlowAfter` | constants | `settle.dart` | 30 s / 2 s |
| `TomGitHubLiveConfig` | class | `github_live.dart` | The live suite's repositories and token, or null when not enabled |
| `TomGitHubCredentialClass` | class | `github_live.dart` | A credential's family and scopes, and whether it reaches every repository |
| `tomClassifyGitHubCredential` | function | `github_live.dart` | A `TomGitHubCredentialClass` from response headers |
| `tomGitHubCredentialRefusal` / `tomGitHubRepoAdminRefusal` | functions | `github_live.dart` | Why a credential must not be used, or null |
| `tomLiveEnabled`, `tomWideTokenAllowed`, `tomEarnSecondaryLimitEnabled` | function / getters | `github_live.dart` | The opt-in flags |
| `tomGitHubRepoAdminToken` | getter | `github_live.dart` | The repository-administration token, or null |
| `tomLiveSkipTitle` / `tomLiveSkipReason` | functions | `github_live.dart` | The gate as a test title / a `skip:` reason |
| `tomGitHubTokenVar`, `tomLiveVar`, `tomGitHubRepoVar`, `tomGitHubRepo2Var`, `tomGitHubRepoAdminTokenVar`, `tomEarnSecondaryLimitVar`, `tomWideTokenVar`, `tomDefaultGitHubTestRepo` | constants | `github_live.dart` | The variable names and the default scratch repository |
| `TomGiteaServer` | class | `gitea.dart` | A disposable Gitea container |
| `TomBrowserSuite` | class | `browser_suite.dart` | Runs `test/browser/` on Chrome from a VM test |
| `TomCorsProxy` | class | `cors_proxy.dart` | A loopback reverse proxy that adds CORS headers |
| `processTreeOf` / `aliveAmong` | functions | `process_tree.dart` | A process and its descendants / which pids still run |
| `TomWorkspaceClone` | class | `workspace_clone.dart` | The machine's clone of the workspace for build-tool tests |
| `tomIsWorkspaceClone` / `tomRequireWorkspaceClone` | functions | `workspace_clone.dart` | Whether a directory is a clone's root / throw unless inside one |
| `tomMarkWorkspaceClone` / `tomWorkspaceCloneSkipFile` | function / constant | `workspace_clone.dart` | Write `tom_skip.yaml` into a clone's root (kept out of its git status), so the tools leave the clone out when they walk from above |
| `tomTestWorkspaceEnv` / `tomWorkspaceCloneMarker` | constants | `workspace_clone.dart` | `TOM_TEST_WORKSPACE` / `tom_workspace_clone.json` |
| `TomLicence` | enum | `licence_audit.dart` | The licences the audit recognises |
| `TomLinkedPackage` | typedef | `licence_audit.dart` | A linked package: name, root, whether it is the SDK's |
| `tomResolvedPackages` / `tomLinkedPackages` / `tomAuditLicences` | functions | `licence_audit.dart` | Resolve, walk, audit |
| `tomClassifyLicence` / `tomIsGplFamily` / `tomLicenceFileOf` | functions | `licence_audit.dart` | Recognise a licence text / find a package's licence file |

The default entry point uses `dart:io` and does not compile for the web. The
Flutter binding of `tomPumpUntil` (`tester.pumpUntil(finder)`) is in
`package:tom_ui_testing/tom_ui_testing.dart`.

## Quick Start

```dart
import 'package:tom_test_support/tom_test_support.dart';

void main() {
  print(tomFindRepositoryRoot().path); // the directory holding tom_repository.yaml
  final live = TomGitHubLiveConfig.fromEnvironment();
  print(live ?? tomLiveSkipReason()); // set GITHUB_TEST_TOKEN and TOM_LIVE …
  print(tomDartCli() ?? tomMissingDartReason('run this example')); // …/dart
}
```

## Roots by Landmark

A suite that needs a directory above its package — scratch space, sibling
packages — finds it by walking up for a marker file rather than by counting
`..` segments. A count is right at one depth only, and because what is looked
for up there is usually optional, a wrong count turns into a skip whose reason
is untrue.

```dart
final repo = tomFindRepositoryRoot(); // throws StateError without a marker
final workspace = tomFindWorkspaceRoot(); // null outside a workspace
final scratch = tomWorkspaceZtmp(); // <workspace>/ztmp, created if missing
```

- `tomFindRepositoryRoot({from})` answers the nearest directory at or above
  `from` (default: the current directory) holding `tom_repository.yaml`, and
  throws a `StateError` naming the marker when there is none.
- `tomFindWorkspaceRoot({from})` answers the nearest directory holding
  `buildkit_master.yaml`, or null — a repository cloned on its own has no
  workspace, and null says so.
- `tomWorkspaceZtmp({from})` answers `<workspace>/ztmp`, creating it, and throws
  when there is no workspace.
- `tomFindUp(start, holdsLandmark)` is the walk: the nearest directory at or
  above `start` for which `holdsLandmark` is true, or null at the file-system
  root.

## The Dart CLI

`Platform.resolvedExecutable` is the runner's binary. Under `dart test` that is
the Dart CLI; under `flutter test` it is `flutter_tester`, which never exits
when asked to `compile js` and answers wrongly as a stand-in. A test that spawns
Dart asks for it instead:

```dart
final dart = requireTomDartCli('compile a fixture'); // or a StateError
final result = await Process.run(dart, ['--version']);
```

`tomDartCli()` answers the runner when its name is `dart`, otherwise `dart` as
the `PATH` resolves it, otherwise null. `tomMissingDartReason(purpose)` is the
sentence for a skip or a failure, naming the runner. `tomDartFrom(running,
lookupOnPath)` and `tomDartOnPath()` are the two steps, separated so both are
testable.

## Waiting: tomPumpUntil and tomSettleUntil

Both waits ask their condition first, so a condition that already holds costs
nothing, and both fail with an exception that says what was waited for.

### tomPumpUntil

For a widget test waiting on something that finishes in real time while frames
keep being scheduled (where `pumpAndSettle` cannot help). The caller supplies
how to pass time and how to pump:

```dart
await tomPumpUntil(
  what: 'the comment list',
  matches: () => find.text('first comment').evaluate().isNotEmpty,
  passTime: (step) => tester.runAsync(() => Future<void>.delayed(step)),
  pumpFrame: () => tester.pump(),
  onScreen: () => find.byType(Text).evaluate().map((e) => e.widget).join(', '),
);
```

The defaults are a 2-minute `timeout` and a 250 ms `step`; `hint` adds a line to
the failure. On timeout it throws `TomPumpUntilTimeout` with `what`, `waited`,
`timeout`, `onScreen` and `hint`. `matches` must state a result ("the comment is
shown"), never the absence of work ("nothing is pending"), which holds before a
handler has even started.

### tomSettleUntil

For a live suite between a write and a read that depends on it: a remote served
from replicas promises no read-after-write consistency. It reads until `done`
accepts the value and returns that value:

```dart
final issue = await tomSettleUntil(
  what: 'the new label on issue 42',
  read: () => client.getIssue(repoSlug: repo, number: 42),
  done: (issue) => issue.labels.any((l) => l.name == 'triage'),
);
```

It backs off between reads (200 ms, growing by half up to 2 s). At `timeout`
(default `tomLiveSettleTimeout`, 30 s) it throws `TomSettleTimeout` with `what`,
the `last` value read and `spent` ("7 reads over 30.4 s"); `describeFailure`
replaces the message. A settle that succeeded but took longer than `slowAfter`
(default 2 s) hands one line to `report` (default `print`). A settle only reads;
the assertion comes after it.

## The Live-GitHub Contract

A live suite reaches a real GitHub account. It runs only when **two** variables
are set: `GITHUB_TEST_TOKEN` (it *may* reach the account) and `TOM_LIVE` (it
should do so *now*). A token in the environment is normal on a developer
machine, so the token alone enables nothing, and a plain `dart test` skips every
live suite with a reason naming both variables.

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

| Variable | Constant | Meaning |
| -------- | -------- | ------- |
| `GITHUB_TEST_TOKEN` | `tomGitHubTokenVar` | The credential of the live suites. |
| `TOM_LIVE` | `tomLiveVar` | Run live suites now. |
| `GITHUB_TEST_REPO` | `tomGitHubRepoVar` | The scratch repository; default `al-the-bear-automated/tom_github_api_test`. |
| `GITHUB_TEST_REPO_2` | `tomGitHubRepo2Var` | A second repository, for issue transfer. |
| `GITHUB_TEST_ADMIN_TOKEN` | `tomGitHubRepoAdminTokenVar` | A separate token for suites that create and delete repositories. |
| `TOM_ALLOW_WIDE_TOKEN` | `tomWideTokenVar` | Accept a classic token carrying `repo`. |
| `TOM_EARN_SECONDARY_LIMIT` | `tomEarnSecondaryLimitVar` | Allow a suite that deliberately earns a secondary rate limit. |

A flag counts as set when it is non-empty and not `0`.

- `TomGitHubLiveConfig.fromEnvironment({environment})` answers `repo`, `token`
  and `repo2`, or null when `TOM_LIVE` or the token is missing. Its `toString`
  names the repositories and prints the token as `<withheld>`.
- `tomLiveSkipTitle(what, {extraVars, tokenVar})` and
  `tomLiveSkipReason({extraVars, because, tokenVar})` word the gate the same way
  everywhere; `because` says what an extra gate protects against.
- `tomClassifyGitHubCredential(headers, {login})` reads a credential from the
  headers of any authenticated response: a classic token has `x-oauth-scopes`,
  a fine-grained one does not. `reachesEveryRepository` is true for a classic
  token with `repo` or `public_repo`.
- `tomGitHubCredentialRefusal(credential, wideAllowed: tomWideTokenAllowed)`
  answers the message to fail with when such a token would be used without
  `TOM_ALLOW_WIDE_TOKEN`, or null.
- `tomGitHubRepoAdminToken` answers the administration token only while
  `TOM_LIVE` is set; `tomGitHubRepoAdminRefusal(credential)` refuses a classic
  token lacking `repo` or `delete_repo`, so a suite never creates a repository
  it cannot delete.

## A Disposable Gitea

`TomGiteaServer` runs Gitea (`gitea/gitea:1.22.6`) in Docker for a live git
suite: one admin user, an access token and an initialised repository, removed
when the suite ends. Gate it on `TOM_LIVE` like the GitHub suites.

```dart
if (!await TomGiteaServer.available()) return; // docker does not answer
final gitea = await TomGiteaServer.start();
try {
  print(gitea.repositoryUrl); // http://127.0.0.1:<port>/tom/scratch.git
  // gitea.base, gitea.user and gitea.token reach the API
} finally {
  await gitea.stop();
}
```

## Browser Suites

An ordinary `flutter test` skips a package's `@TestOn('browser')` files
silently. `TomBrowserSuite` lets one VM test run them on Chrome and fail when
they do not pass:

```dart
final suite = TomBrowserSuite(); // test/browser in the current package
test('test/browser passes on Chrome', () async {
  final failure = TomBrowserSuite.failureOf(await suite.run());
  expect(failure, isNull, reason: failure);
}, skip: suite.skipReason);
```

- It uses the `flutter` of the SDK the suite runs under (`FLUTTER_ROOT`,
  `flutterExecutable`).
- `skipReason` is non-null when `TOM_SKIP_BROWSER_TESTS=1` is set, when
  `FLUTTER_ROOT` does not point at a `flutter` executable, or when the directory
  is missing; `run` throws a `StateError` in those cases.
- `run(defines: {...})` passes values to the page as `--dart-define`s, such as
  the address of a server the VM test started.
- `failureOf(result)` reports a non-zero exit, and also an exit 0 without
  `All tests passed` — what a fully skipped directory looks like.
- `TomBrowserSuite(directory: 'test/browser_live')` drives another folder.

## The CORS Proxy

A web page may read a response from another origin only when the response
allows it. `TomCorsProxy` is an in-process reverse proxy on a free loopback port
that adds the headers and answers the preflight `OPTIONS`:

```dart
final proxy = await TomCorsProxy.start(gitea.base);
// hand proxy.url to the page instead of gitea.base
await proxy.stop();
```

It allows any origin and the methods `GET`, `HEAD`, `POST` and `OPTIONS`, echoes
the requested headers, and answers `502` with the error when the target cannot
be reached. Redirects are passed back to the page, not followed.

## Process Trees

A cleanup that kills processes by name kills whatever runs beside the test.
`processTreeOf(pid)` answers a process and every descendant, walked with
`pgrep -P`; take it while the tree is intact, because a killed parent's children
are re-parented. `aliveAmong(pids)` answers which of them still run.

```dart
final child = await Process.start('flutter', ['test']);
final tree = processTreeOf(child.pid);
child.kill(ProcessSignal.sigkill);
for (final pid in aliveAmong(tree)) {
  Process.killPid(pid, ProcessSignal.sigkill);
}
```

Both are POSIX only; `processTreeOf` throws an `UnsupportedError` on Windows
rather than answer with an empty set.

## The Workspace Clone

Build-tool suites must not write into the live workspace other sessions work
in. `TomWorkspaceClone` hands out one clone of the workspace per machine,
beside it at `<parent>/<name>_testclone` (or where `TOM_TEST_WORKSPACE` says):

```dart
final clone = await TomWorkspaceClone.acquire();
try {
  // run the tool under test in clone.root
} finally {
  await clone.release();
}
```

- **`acquire({liveRoot, cloneRoot, lockTimeout, log})`** takes the machine's
  lock (a file beside the clone; another run waits up to `lockTimeout`, default
  30 minutes, then the call throws naming the holder), creates the clone on
  first use — this copies the whole workspace and takes minutes — and brings
  every repository, the superproject and each submodule recursively, to the
  commit and branch its live counterpart has checked out. Commits are fetched
  from the live repositories on this machine, so unpushed commits are included
  and uncommitted edits are not. Submodules are laid out as in the live tree
  (`.git` files pointing into `.git/modules`); `origin` carries the live URL and
  pushing is disabled.
- **`release()`** resets every repository to the recorded commit
  (`git reset --hard`, `git clean -ffd`; ignored files such as `.dart_tool/`
  stay) and gives the lock back. It is safe to call twice.
- `root` is the clone, `liveRoot` the workspace it follows; `findLiveRoot` and
  `locationFor` answer the defaults.
- The clone is marked by `.git/tom_workspace_clone.json`.
  `tomRequireWorkspaceClone(dir)` throws unless `dir` lies inside a clone — call
  it in a test helper before every write, so a helper handed the wrong root
  refuses instead of changing the live tree.

`acquire` refuses a clone location that overlaps the live workspace, and throws
when there is no workspace above the current directory.

## The Licence Audit

Checks that every package an application links carries a `LICENSE` the
application's own terms admit:

```dart
final packages = tomResolvedPackages('my_app'); // reads my_app/.dart_tool/package_config.json
final linked = tomLinkedPackages('my_app', packages);
final audit = tomAuditLicences(linked, admitted: TomLicence.permissive);
expect(audit.problems, isEmpty, reason: audit.problems.join('\n'));
```

- `tomResolvedPackages(package)` reads the package configuration of the package
  at `<repository root>/<package>`; run `pub get` there first.
- `tomLinkedPackages(start, packages)` follows `dependencies:` from `start` —
  not dev dependencies, which are not shipped.
- `tomAuditLicences(linked, admitted:)` answers the licence `granted` per
  package and the `problems`: no licence file, a text it does not recognise, or
  a licence outside `admitted`. A package of the Flutter SDK is judged by the
  `flutter` package's licence.
- `TomLicence` recognises BSD-3, BSD-2, MIT, Apache-2.0, ISC, zlib
  (`TomLicence.permissive`) and MPL-2.0 (`TomLicence.mpl2`). Admit
  `{...TomLicence.permissive, TomLicence.mpl2}` for an application that carries
  MPL-2.0 files with their notice.
- `tomClassifyLicence(text)` recognises a licence by its operative sentences,
  not by its name. The GNU family (GPL, AGPL, LGPL; `tomIsGplFamily`) is never
  recognised as admissible.
- `tomLicenceFileOf(dir)` finds `LICENSE`, `LICENSE.md`, `LICENSE.txt` or
  `COPYING`.

## Error Handling

| Situation | What happens |
| --------- | ------------ |
| No `tom_repository.yaml` above | `tomFindRepositoryRoot` throws `StateError`. |
| No workspace above | `tomFindWorkspaceRoot` answers null; `tomWorkspaceZtmp` and `TomWorkspaceClone.acquire` throw `StateError`. |
| No Dart CLI | `tomDartCli` answers null; `requireTomDartCli` throws `StateError` with `tomMissingDartReason`. |
| A wait's deadline passes | `TomPumpUntilTimeout` / `TomSettleTimeout`, naming what was waited for. |
| Live suite not enabled | `TomGitHubLiveConfig.fromEnvironment` answers null; use `tomLiveSkipReason` as the skip. |
| A too-wide or too-narrow credential | `tomGitHubCredentialRefusal` / `tomGitHubRepoAdminRefusal` answer the message to fail with. |
| A browser run that cannot happen | `skipReason` is non-null; `run` throws `StateError`. |
| A write helper outside a clone | `tomRequireWorkspaceClone` throws `StateError`. |
| The clone is held by another run | `acquire` waits up to `lockTimeout`, then throws naming the holder. |
| `processTreeOf` on Windows | `UnsupportedError`. |
| A missing package configuration or unresolved dependency | `tomResolvedPackages` / `tomLinkedPackages` throw `StateError`. |

## Best Practices

- **Depend on it as a dev dependency only.** Nothing a product links should
  import it.
- **Find roots by landmark**, never by counting `..`.
- **Spawn Dart through `requireTomDartCli`**, never `Platform.resolvedExecutable`.
- **Gate every live suite through `TomGitHubLiveConfig.fromEnvironment`** and use
  `tomLiveSkipReason`, so every live suite skips with the same sentence.
- **Settle before you assert** in a live suite, and keep the assertion after the
  settle.
- **Reap only the tree you started**, taken with `processTreeOf` before any
  signal.
- **Run build-tool tests in the workspace clone** and guard their writes with
  `tomRequireWorkspaceClone`.
