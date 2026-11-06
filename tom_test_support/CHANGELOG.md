# Changelog

## 0.5.0

- `licence_audit.dart`: the licence audit of the packages an application
  resolves — `tomResolvedPackages`, `tomLinkedPackages` (the `dependencies:`
  walk), `tomClassifyLicence` and `tomAuditLicences` with the licences the
  application admits (`TomLicence.permissive`, plus `TomLicence.mpl2` where
  its notice is carried). Moved here from `tom_webwork_testkit`'s
  `editor_licence_path.dart`, so a BSD-3 application (Tom Forge) runs the
  same audit as a GPL one (Webwork).

## 0.4.0

- `process_tree.dart`: `processTreeOf` (a process and every descendant, by
  `pgrep -P`) and `aliveAmong` — so a test or a test runner reaps what it
  spawned and nothing else, never a process matched by its name. Moved here
  from `tom_webwork_app`'s test support; the live runner in
  `tom_webwork_core` uses it too.

## 0.3.0

- `TomBrowserSuite.run(defines:)`: values the VM test knows only at run time —
  the address and token of a server it started — reach the browser code as
  `--dart-define`s.
- `TomCorsProxy` (`cors_proxy.dart`): a reverse proxy that adds the CORS
  headers a web page needs and answers its preflight, for browser suites
  against servers that send none — Gitea's `[cors]` setting covers its `/api`
  routes and not git's smart-HTTP endpoints.

## 0.2.0

- The wait a live suite makes between a write and the read that depends on
  it (`settle.dart`): `tomSettleUntil` reads until a condition holds or
  `tomLiveSettleTimeout` passes, backing off between reads, and reports a
  settle slower than `tomLiveSettleSlowAfter`; `TomSettleTimeout` names what
  was waited for and the last value read. One policy for every package's live
  suites, moved here from `tom_webwork_core`'s test support.

## 0.1.0

- The repository and workspace roots, found by landmark (`roots.dart`).
- The Dart CLI a test may spawn, located rather than taken from the runner
  (`dart_cli.dart`).
- A framework-free wait for a network-backed action (`pump_until.dart`).
- The live-GitHub credential contract (`github_live.dart`).
- A disposable Gitea in Docker for live git suites (`gitea.dart`).
- The driver that runs a Flutter package's browser-only tests on Chrome from
  its ordinary suite (`browser_suite.dart`).
