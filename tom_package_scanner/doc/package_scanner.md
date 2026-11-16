# Tom Package Scanner — User Guide

Tom Package Scanner reads a repository folder on disk and describes every
package directly inside it: its publication status, license, version,
description, links and a few static code metrics. It reads files only. It
starts no process, makes no network request, and does not run `dart pub` or
`dart test`.

This guide describes how the scanner finds packages, how each field of the
result is derived, and where its limits are. The [README](../README.md) gives
the overview and installation; the runnable
[example](../example/tom_package_scanner_example.dart) builds a fixture repo in
a temporary directory and scans it.

## Contents

- [Concepts](#concepts)
- [Creating a scanner](#creating-a-scanner)
- [Scanning a repository](#scanning-a-repository)
- [The package record](#the-package-record)
- [How the status is derived](#how-the-status-is-derived)
- [How the license is resolved](#how-the-license-is-resolved)
- [How the metrics are counted](#how-the-metrics-are-counted)
- [TypeScript packages](#typescript-packages)
- [Behaviour, errors and limits](#behaviour-errors-and-limits)

## Concepts

| Term | Meaning |
| ---- | ------- |
| **Source root** | The filesystem folder the repository trees live under. |
| **Path prefix** | A POSIX path below the source root, e.g. `tom_agent_container/tom_ai`. It is used both to reach the repository on disk and as the start of each package's recorded `sourcePath`. |
| **Repository** | A folder below `<source root>/<path prefix>`, named by the caller, e.g. `d4rt`. |
| **Package** | A direct child folder of the repository that is a Dart package or a TypeScript package (see below). |
| **Status** | One of four publication states, `ComponentStatus`. |
| **LOC threshold** | The number of real source lines above which a package counts as real code rather than a stub. Default 200. |

A child folder is a package when it holds:

- a `pubspec.yaml` — a **Dart** package; or
- both a `package.json` and a `tsconfig.json` — a **TypeScript** package.

A folder with both a `pubspec.yaml` and a `package.json` is a Dart package.
Folders that are neither are skipped. Discovery is one level deep: packages
nested further down are not found.

## Creating a scanner

```dart
import 'package:tom_package_scanner/tom_package_scanner.dart';

final scanner = PackageScanner(
  sourceRoot: '/path/to/enterprise_flutter',
  pathPrefix: 'tom_agent_container/tom_ai',
  locThreshold: 200, // optional, default 200
);
```

The scanner holds only these three values, so it can be created once and used
for any number of repositories. The repository folder for `scanRepo('d4rt', …)`
is `<sourceRoot>/tom_agent_container/tom_ai/d4rt`; the path prefix is split on
`/` and joined with the platform separator, so it works on Windows as well.

## Scanning a repository

```dart
final packages = scanner.scanRepo('d4rt', repoIsPublic: true);
for (final pkg in packages) {
  print('${pkg.dirName}: ${pkg.status.yamlValue} (${pkg.statusReason})');
}
```

`scanRepo` returns one `PackageInfo` per package, sorted by folder name, so the
output is stable from run to run. The `repoIsPublic` flag says whether the
repository is public. The scanner does not find this out itself; the caller
already knows it (for example from a list of public repositories) and passes it
in. It affects only the `published` status.

A repository folder that does not exist gives an empty list.

## The package record

`PackageInfo` is an immutable value with these fields:

| Field | Type | Source |
| ----- | ---- | ------ |
| `repo` | `String` | The repository name passed to `scanRepo`. |
| `dirName` | `String` | The package folder's name. |
| `sourcePath` | `String` | `<pathPrefix>/<repo>/<dirName>`, always with `/`. |
| `name` | `String` | Dart: `name:` from `pubspec.yaml`, else the folder name. TypeScript: always the folder name. |
| `status` | `ComponentStatus` | See [How the status is derived](#how-the-status-is-derived). |
| `statusReason` | `String` | A short text explaining the status, e.g. `lib/ 250 LOC`. |
| `hasProjectYaml` | `bool` | Whether the package has a `buildkit.yaml`. |
| `metrics` | `PackageMetrics` | See [How the metrics are counted](#how-the-metrics-are-counted). |
| `version` | `String?` | `version:` from `pubspec.yaml` or `package.json`. |
| `description` | `String?` | `description:` from `pubspec.yaml` or `package.json`. |
| `publishTo` | `String?` | `publish_to:` from `pubspec.yaml`; always `null` for TypeScript. |
| `license` | `String?` | A license token, or `null`. See [How the license is resolved](#how-the-license-is-resolved). |
| `links` | `Map<String, String>` | `repository` and `homepage`, when set and not blank. |

`toString()` gives a one-line summary:
`PackageInfo(tom_ai/demo/tom_pub, published: public repo; pub version 1.2.3)`.

`ComponentStatus.yamlValue` is the token form of a status (`not_started`,
`works`, `published`, `released`), meant for writing into YAML or reports. The
enum values are declared from least to most mature, so `index` can be used to
compare them.

## How the status is derived

The rules are checked in this order; the first that matches decides.

| Order | Status | Rule | `statusReason` |
| ----- | ------ | ---- | -------------- |
| 1 | `released` | A `release.md` file in the package folder, or `release: { state: released }` in its `buildkit.yaml`. | `release marker` |
| 2 | `published` | `repoIsPublic` is `true` and the Dart package is publishable: it has a version and `publish_to` is not `none`. | `public repo; pub version 1.2.3` |
| 3 | `works` | The real source line count is above the LOC threshold. | `lib/ 250 LOC` (`src/` for TypeScript) |
| 4 | `not_started` | Anything else. | `stub (10 LOC ≤ 200)`, or `no lib/` when the source folder is missing |

Two consequences worth knowing:

- A package with `publish_to: none` is never `published`, even in a public
  repository. It is ranked by its source size instead.
- The same publishable package in a private repository falls through to rule 3
  or 4. A small published package in a private repository therefore shows as
  `not_started`.

```dart
// Fixture from the example: tom_pub has 5 lines in lib/.
scanner.scanRepo('demo', repoIsPublic: true);  // tom_pub -> published
scanner.scanRepo('demo', repoIsPublic: false); // tom_pub -> not_started, stub (5 LOC ≤ 200)
```

The line count used here is exactly `metrics.loc`, so the displayed metric and
the status always agree.

## How the license is resolved

1. A `license:` value in the package's `buildkit.yaml` is used as it is. It is
   not validated.
2. Otherwise the first file found of `LICENSE`, `LICENSE.md`, `LICENSE.txt`,
   `license.md` is read and passed to `classifyLicense`.
3. For TypeScript packages, when neither gives a token, the `license` field of
   `package.json` is used.
4. Otherwise `license` is `null`.

### `classifyLicense`

`classifyLicense(String text)` maps a license text to a token, or `null`. It
matches on the wording of the license body, case-insensitively, in this order:

| Text contains | Token |
| ------------- | ----- |
| `todo` and `license` (a placeholder) | `null` |
| `apache license` and `version 2.0` | `Apache-2.0` |
| `gnu affero general public license` | `AGPL-3.0` (with `version 3`), else `AGPL-2.0` |
| `gnu lesser general public license` | `LGPL-3.0` |
| `gnu general public license` | `GPL-3.0` |
| `mozilla public license` and `2.0` | `MPL-2.0` |
| `permission is hereby granted, free of charge` (without the BSD clause, or with `mit license`) | `MIT`, else `ISC` |
| `redistribution and use in source and binary forms` | `BSD-3-Clause` with `neither the name`, else `BSD-2-Clause` |
| the Unlicense public-domain sentence | `Unlicense` |
| `proprietary` or `confidential` | `proprietary` |
| `all rights reserved` | `all-rights-reserved` |

Open-source wordings are checked before the closed-license ones, so a BSD or
MIT license that starts with "All rights reserved." is still classified by its
grant clauses.

```dart
classifyLicense('MIT License\n\nPermission is hereby granted, free of charge'); // 'MIT'
classifyLicense('Apache License\nVersion 2.0');                                 // 'Apache-2.0'
classifyLicense('TODO: Add your license here');                                 // null
```

### The token vocabulary

| Name | Contents |
| ---- | -------- |
| `spdxLicenseTokens` | `BSD-3-Clause`, `BSD-2-Clause`, `MIT`, `Apache-2.0`, `AGPL-3.0`, `AGPL-2.0`, `GPL-3.0`, `LGPL-3.0`, `MPL-2.0`, `ISC`, `Unlicense` |
| `nonSpdxLicenseTokens` | `proprietary`, `all-rights-reserved` |
| `validLicenseTokens` | both sets together |
| `isValidLicenseToken(token)` | whether `token` is in `validLicenseTokens` |

Use `isValidLicenseToken` to check a curated `buildkit.yaml` value, which the
scanner passes through unchecked.

## How the metrics are counted

`PackageMetrics` holds three counts, all made by reading files:

| Metric | Dart package | TypeScript package |
| ------ | ------------ | ------------------ |
| `loc` | Real lines in `.dart` files under `lib/`. | Real lines in `.ts` files under `src/`, excluding test files. |
| `tests` | Occurrences of `test(` and `testWidgets(` under `test/`. | Occurrences of `test(` and `it(` in test files. |
| `testLoc` | Real lines in `.dart` files under `test/`. | Real lines in test files. |

A **real line** is a line that is not blank and does not start with `//` after
trimming. Lines inside `/* … */` blocks and `///` doc comments are handled as
follows: `///` lines start with `//` and are not counted; block comment lines
are counted.

Excluded files:

- Dart: `*.g.dart`, `*.freezed.dart`, `*.options.dart`.
- TypeScript: `*.d.ts` declaration files. Test files are `*.test.ts` and
  `*.spec.ts` anywhere under `src/`, plus every `.ts` file under `test/`.

The test count is an approximation: it counts call sites in the text, so a
`test(` inside a string or a helper called `test` is counted too, and a test
generated in a loop counts once.

## TypeScript packages

TypeScript packages follow the same rules with these differences:

- They are never `published`: `publishTo` is `null` and the publish rule is
  skipped. They reach `released` (release marker) or are ranked by `src/` size.
- `name` is the folder name, not the npm name, because npm names can be scoped
  (`@scope/name`).
- `links.repository` is read from `package.json` `repository`, given either as
  a string or as an object with a `url`. `links.homepage` comes from `homepage`.
- A `package.json` that is not valid JSON is treated as empty; the package is
  still listed, with no version, description or links.

## Behaviour, errors and limits

- **Missing pieces are tolerated.** A missing repository gives an empty list; a
  package without `lib/` (or `src/`) gets `not_started` with reason `no lib/`;
  a package without `buildkit.yaml` gets `hasProjectYaml == false` and is
  described from its `pubspec.yaml` or `package.json` alone.
- **Filesystem errors propagate.** A folder that cannot be listed or a file
  that cannot be read (permissions, invalid UTF-8) raises the `dart:io`
  exception from `scanRepo`.
- **Synchronous.** `scanRepo` uses synchronous file APIs and reads every source
  and test file of every package. On a large repository call it outside a
  latency-sensitive isolate.
- **One level only.** Only direct children of the repository folder are
  examined; packages in deeper folders (examples, samples, fixtures) are not.
- **No network.** Whether a version is actually on pub.dev is not checked:
  `published` means "a publishable package in a public repository".
- **Folder scanning comes from Tom Build Base.** Dart and `buildkit.yaml`
  detection use its `NatureDetector`, so a `pubspec.yaml` it cannot parse
  yields a package with only its folder name.
