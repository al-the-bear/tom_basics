# Tom Package Scanner

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause, see [LICENSE](LICENSE).

Static workspace scanner: walks a framework repo's direct-child packages —
Dart **and** TypeScript — and derives, for each, a publication **status**,
license token, version, description and external links. Built on
[`tom_build_base`](../tom_build_base)'s folder scanning and nature detection.
Powers the website's module-index generators.

---

## Overview

A multi-repo framework like Tom faces a recurring documentation problem: **what
is the real state of every package in the tree?** Which packages are released,
which are published to pub.dev, which are working-but-unpublished, and which are
still empty stubs? Answering that by hand goes stale the moment a package
changes; answering it by running `dart pub`/`gh`/`dart test` per package is slow
and needs network access.

`tom_package_scanner` answers it **statically**. Point a
[`PackageScanner`](#packagescanner) at a workspace root, name a repo, and it
returns one [`PackageInfo`](#packageinfo) per discovered package — each carrying
a derived [`ComponentStatus`](#the-status-ladder), a classified license token,
static [code metrics](#display-metrics), and the metadata the website needs to
render a module entry. The scanner makes **no process calls and no network
requests**: whether a repo is public is supplied by the caller, so the status
logic stays pure and unit-testable against fixture trees.

The four things it produces for every package:

| Output | Type | What it answers |
| ------ | ---- | --------------- |
| **Status** | `ComponentStatus` | Released? published? working? a stub? — the [status ladder](#the-status-ladder) |
| **License** | `String?` | A canonical SPDX-or-closed [token](#license-token), or `null` when unknown |
| **Metrics** | `PackageMetrics` | Static `lib/`/`src/` LOC, test-call count, test LOC ([§4.2.2](#display-metrics)) |
| **Metadata** | name, version, description, links | Harvested from `pubspec.yaml` / `package.json` |

The scanner was extracted from the website's `gen_modules` generator
(`enterprise_flutter_web`, spec §12 todo 7) so that both the module-index
generator and the status-report generator are thin users of **one** scanner —
the single source of truth for "what's in the tree".

> **Dart and TypeScript.** Discovery covers both ecosystems: a child folder is a
> package if it has a `pubspec.yaml` (Dart) **or** both `package.json` and
> `tsconfig.json` (TypeScript). TypeScript packages are never pub-publishable, so
> they never reach the `published` rung — they top out at `released`/`works` on
> their `src/` size. See [Scanning TypeScript packages](#scanning-typescript-packages).

---

## Installation

This is a **workspace-internal** package (`publish_to: none`); it is consumed by
path, not from pub.dev:

```yaml
dependencies:
  tom_package_scanner:
    path: ../../basics/tom_package_scanner
```

It depends (by path) on [`tom_build_base`](../tom_build_base) for folder scanning
and nature detection, plus `path` and `yaml`. Requires the Dart SDK `^3.10.4`.
The scanner reads the filesystem (`dart:io`) but never spawns a process and never
touches the network.

---

## Features

| Capability | API | Notes |
| ---------- | --- | ----- |
| Scan a repo's packages | `PackageScanner.scanRepo(repo, repoIsPublic:)` | Returns `List<PackageInfo>`, sorted by folder name |
| Derive publication status | `PackageInfo.status` / `.statusReason` | `released` / `published` / `works` / `not_started` |
| Classify a license body | `classifyLicense(text)` | SPDX-or-closed token, or `null` |
| Validate a license token | `isValidLicenseToken(token)` / `validLicenseTokens` | The website's accepted vocabulary |
| Static code metrics | `PackageInfo.metrics` | `loc`, `tests`, `testLoc` — no `dart test` |
| Capture metadata | `PackageInfo.name/.version/.description/.links` | From `pubspec.yaml` / `package.json` |
| Flag missing project config | `PackageInfo.hasProjectYaml` | `false` when no `tom_project.yaml` |

---

## Quick start

Scan one repo and print each package's derived status:

```dart
import 'package:tom_package_scanner/tom_package_scanner.dart';

void main() {
  final scanner = PackageScanner(
    sourceRoot: '../..',                       // filesystem base for repo trees
    pathPrefix: 'tom_agent_container/tom_ai',  // recorded in component paths
    locThreshold: 200,                         // lib/ LOC above which = "works"
  );

  // includedRepos are public by construction (the website seed intersects with
  // `gh repo list --visibility public`), so repoIsPublic is true for them.
  final packages = scanner.scanRepo('d4rt', repoIsPublic: true);

  for (final pkg in packages) {
    print('${pkg.dirName.padRight(14)} '
        '${pkg.status.yamlValue.padRight(12)} ${pkg.statusReason}');
  }
}
```

Output — one line per discovered package, sorted by folder name, each labelled
with its derived status and a human-readable reason:

```text
tom_internal   works        lib/ 250 LOC
tom_pub        published    public repo; pub version 1.2.3
tom_released   released     release marker
tom_stub       not_started  stub (10 LOC ≤ 200)
tom_ts_ext     works        src/ 250 LOC
```

Each row is a [`PackageInfo`](#packageinfo). Inspecting one in full:

```text
sourcePath : tom_agent_container/tom_ai/d4rt/tom_pub
name       : tom_pub
status     : published
version    : 1.2.3
license    : null
metrics    : PackageMetrics(loc: 5, tests: 0, testLoc: 0)
links      : {repository: https://github.com/al-the-bear/d4rt}
```

---

## Example projects

| Example | What it shows |
| ------- | ------------- |
| [Quick start](#quick-start) | Scan a repo; read each package's status |
| [The status ladder](#the-status-ladder) | The four rungs and how the first match wins |
| [License token](#license-token) | `classifyLicense` vocabulary and curated overrides |
| [Display metrics](#display-metrics) | Static LOC / test counts |
| [Scanning TypeScript packages](#scanning-typescript-packages) | `package.json` + `tsconfig.json` discovery |
| [`test/package_scanner_test.dart`](test/package_scanner_test.dart) | 35 fixture-tree cases covering every rule |

> This package has no standalone `example/` program — it is a library consumed by
> the website's `gen_modules` / `gen_status_report` generators. The runnable test
> suite is the executable reference for every rule below: it scaffolds fixture
> trees in a temp dir and asserts each status branch, license source, metric, and
> the Dart/TypeScript discovery rules.

---

## Usage

### The status ladder

`scanRepo` derives one of four `ComponentStatus` values (spec §4.2.1), checked
top-to-bottom — **the first match wins**:

| Status | Condition | Reason string |
| ------ | --------- | ------------- |
| `released` | `tom_project.yaml` `release.state: released`, **or** a `release.md` in the package dir | `release marker` |
| `published` | `repoIsPublic` **and** the package is publishable (`publish_to` ≠ `none` and a version is set) | `public repo; pub version X` |
| `works` | real source — non-blank, non-comment LOC **above** `locThreshold` | `lib/ NNN LOC` (`src/` for TypeScript) |
| `not_started` | path missing, no source dir, or a source stub at/below the threshold | `no lib/` / `stub (NN LOC ≤ 200)` |

The same package set, demonstrating each rung (from the [quick start](#quick-start)):
`tom_released` carries a release marker, `tom_pub` is a real pub package in a
public repo, `tom_internal` is real code but `publish_to: none`, and `tom_stub`
is a 10-line stub.

```dart
scanner.scanRepo('d4rt', repoIsPublic: true);
// tom_released → released   (release marker)
// tom_pub      → published  (public repo; pub version 1.2.3)
// tom_internal → works      (lib/ 250 LOC)
// tom_stub     → not_started (stub (10 LOC ≤ 200))
```

`repoIsPublic` only gates the `published` rung. The **same** publishable package
in a private repo falls through to its `lib/` size:

```dart
scanner.scanRepo('d4rt', repoIsPublic: false);
// tom_pub → not_started   (5-line lib/, no longer "published")
```

> **`published` vs. `publish_to: none`.** A package marked `publish_to: none`
> (an internal library that happens to live in a public repo) is **not**
> `published` — it falls through to `works` / `not_started` on its source size.
> This is a deliberate refinement of the spec §5.1 example: "published" here
> means *a real pub package*, the more useful signal for the public site.

### License token

`PackageInfo.license` prefers a human-curated `tom_project.yaml license:`; when
absent it classifies the package's `LICENSE` / `license.md` body via
`classifyLicense`. Classification is **body-driven, not header-driven** — a
BSD/MIT body that opens with "All rights reserved." (the Dart-SDK style) is still
classified by its grant clauses, so open-source licenses are checked before the
proprietary fall-throughs:

```dart
classifyLicense('MIT License\n\nPermission is hereby granted, free of charge');
// → 'MIT'
classifyLicense('Redistribution and use in source and binary forms\n'
    'Neither the name');                                  // → 'BSD-3-Clause'
classifyLicense('Apache License\nVersion 2.0');           // → 'Apache-2.0'
classifyLicense('TODO: Add your license here');           // → null  (placeholder)
```

The accepted vocabulary is a small SPDX set plus two closed-license tokens
(`proprietary`, `all-rights-reserved`); anything else returns `null` so a human
can be flagged rather than guessed at:

```dart
validLicenseTokens.contains('BSD-3-Clause'); // true
isValidLicenseToken('proprietary');          // true
isValidLicenseToken('not-a-license');        // false
```

`classifyLicense` is the **single source of truth** for license classification
across the website tooling; the website's `tool/seed/license_classifier.dart`
re-exports it.

### Display metrics

`PackageInfo.metrics` carries three **statically-measured** display metrics
(spec §4.2.2) — the scanner runs no `dart test` and makes no process calls, so
all three are counted directly off the source tree:

| Metric | Definition |
| ------ | ---------- |
| `loc` | non-blank, non-`//`-comment source lines in `lib/` (Dart) or `src/` (TypeScript), excluding generated files (`*.g.dart`, `*.freezed.dart`, `*.options.dart`) and TypeScript declarations (`*.d.ts`). **The same count the `works` >`locThreshold` rule uses**, so the ladder and the displayed LOC never disagree. |
| `tests` | count of `test(` / `testWidgets(` (Dart) or `test(` / `it(` (TypeScript) invocations under `test/`; full-line-comment lines are ignored. A static approximation of the test-case count. |
| `testLoc` | non-blank, non-comment test-dir lines, counted exactly like `loc`. |

These are display-only and never feed status, **except** `loc`, which also drives
the >`locThreshold` rule. `gen_modules` writes them per component plus a summed
module-level rollup; `gen_status_report` surfaces them as the LOC / Tests / Test
LOC columns.

### Scanning TypeScript packages

A child folder counts as a TypeScript package when it has **both** `package.json`
and `tsconfig.json` (and no `pubspec.yaml` — a folder with both is described as
Dart). TypeScript packages differ from Dart on three points:

- **Never `published`.** They are not pub packages, so `publishTo` is always
  `null` and the ladder skips the `published` rung — they top out at
  `released`/`works`.
- **Metrics come from `src/`.** `loc` counts production `src/*.ts`, excluding
  `*.d.ts` declarations and `*.test.ts` / `*.spec.ts` test files; tests and
  `testLoc` come from those test files plus any sibling `test/` dir.
- **Name is the folder name.** npm names can be scoped/aliased (`@tom/ext`); the
  folder is the stable identifier the rest of the catalog keys on.

```dart
// A folder with package.json + tsconfig.json + a 250-line src/extension.ts:
final ext = scanner.scanRepo('vscode', repoIsPublic: true).single;
ext.dirName;       // 'tom_ext'   (folder name, not the npm @tom/ext)
ext.publishTo;     // null        (never a pub package)
ext.status;        // ComponentStatus.works
ext.statusReason;  // 'src/ 250 LOC'
```

Curated `tom_project.yaml license:` still wins over the `package.json` `license`
field, exactly as for Dart.

### Tolerating a missing `tom_project.yaml`

Not every package carries a `tom_project.yaml`. The scanner synthesises the
record from `pubspec.yaml` / `package.json` and the `LICENSE` body alone, and
sets `PackageInfo.hasProjectYaml = false` so callers can flag those packages for
a human to triage.

---

## Architecture

```text
package:tom_package_scanner/tom_package_scanner.dart
│
├── PackageScanner                       the engine (sourceRoot, pathPrefix, locThreshold)
│   └── scanRepo(repo, repoIsPublic:) → List<PackageInfo>
│         ├── discovers Dart (pubspec.yaml) + TypeScript (package.json+tsconfig.json) dirs
│         ├── derives ComponentStatus via the status ladder
│         ├── measures PackageMetrics (static LOC / test counts)
│         └── resolves the license token
│
├── PackageInfo                          one immutable per-package record
├── ComponentStatus                      released / published / works / not_started
├── PackageMetrics                       loc / tests / testLoc (all static)
└── classifyLicense / validLicenseTokens the shared license vocabulary
            │
            └── delegates folder scanning + nature detection to
                package:tom_build_base
                ├── NatureDetector       DartProjectFolder / TomBuildFolder
                └── FsFolder             filesystem folder model
```

| Type / member | Role |
| ------------- | ---- |
| `PackageScanner` | The engine — scans a repo's direct-child packages, no process/network I/O |
| `PackageInfo` | Immutable per-package record (status, license, metrics, metadata, links) |
| `ComponentStatus` | The four-rung publication ladder with canonical `yamlValue` tokens |
| `PackageMetrics` | Static `loc` / `tests` / `testLoc` counts (§4.2.2) |
| `classifyLicense` | Body-driven license-text → canonical token |
| `validLicenseTokens` / `isValidLicenseToken` | The accepted SPDX-or-closed vocabulary |

The scanner holds only its three configuration fields and does no process or
network I/O: it reads the filesystem and returns value objects. Whether a repo is
public is the caller's input, keeping the status logic pure.

---

## Ecosystem

`tom_package_scanner` is one of the foundational packages under
[`tom_ai/basics/`](../). All `tom_ai/basics/` packages share a single repository,
[`tom_basics`](https://github.com/al-the-bear/tom_basics). It builds on
[`tom_build_base`](../tom_build_base) (folder scanning + nature detection) and is
consumed by the website's `gen_modules` and `gen_status_report` generators
(`enterprise_flutter_web`), which turn its `PackageInfo` records into the public
module index and status report. Its `classifyLicense` is re-exported by the
website's license-seed tooling as the single classification source of truth.

---

## Further documentation

- [LICENSE](LICENSE) — BSD-3-Clause licence text.
- [`test/package_scanner_test.dart`](test/package_scanner_test.dart) — 35
  fixture-tree cases that double as the executable specification.
- [`tom_build_base`](../tom_build_base) — the folder-scanning / nature-detection
  foundation this package builds on.
- [CHANGELOG.md](CHANGELOG.md) — release history.
- Source library docs — `PackageScanner`, `PackageInfo`, `ComponentStatus`,
  `PackageMetrics` and `classifyLicense` carry dartdoc with the full rule set and
  spec references (§4.2.1 / §4.2.2 / §12).

---

## Status

Stable (`1.0.0`). Workspace-internal (`publish_to: none`), consumed by path. The
public surface is one engine class plus four value/helper types; all 35 tests
pass and `dart analyze` is clean. No process calls, no network — the scan is pure
filesystem reads against the caller-supplied `repoIsPublic` signal.
