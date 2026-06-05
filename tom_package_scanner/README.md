# tom_package_scanner

Scan a workspace's framework repos and, for each Dart package, derive a
`PackageInfo`: its publication **status**, license token, version, description
and external links. Built on
[`tom_build_base`](../tom_build_base)'s `NatureDetector`.

Extracted from the website's `gen_modules` generator
(`enterprise_flutter_web`, spec §12 todo 7) so that both the module-index
generator and the status-report generator are thin users of one scanner.

## Usage

```dart
import 'package:tom_package_scanner/tom_package_scanner.dart';

final scanner = PackageScanner(
  sourceRoot: '../..',                       // filesystem base
  pathPrefix: 'tom_agent_container/tom_ai',  // recorded in component paths
  locThreshold: 200,
);

// includedRepos are public by construction (the seed intersects with
// `gh repo list --visibility public`), so repoIsPublic is true for them.
final packages = scanner.scanRepo('d4rt', repoIsPublic: true);
for (final pkg in packages) {
  print('${pkg.sourcePath}: ${pkg.status.yamlValue} (${pkg.statusReason})');
}
```

Discovery is **one level deep**: the direct child folders of a repo that carry
a `pubspec.yaml` are its packages (matching the license-audit convention). The
result is sorted by folder name for stable, diff-friendly output.

## Status ladder

`scanRepo` derives one of four `ComponentStatus` values (spec §4.2.1), checked
top-to-bottom — the first match wins:

| Status | Condition | Reason string |
|---|---|---|
| `released` | `tom_project.yaml` `release.state: released`, **or** a `RELEASED.md` in the package dir | `release marker` |
| `published` | `repoIsPublic` **and** the package is publishable (`publish_to` ≠ `none` and a version is set) | `public repo; pub version X` |
| `works` | real `lib/` code — non-blank, non-comment LOC **above** `locThreshold` | `lib/ NNN LOC` |
| `not_started` | path missing, no `lib/`, or a `lib/` stub at/below the threshold | `no lib/` / `stub (NN LOC ≤ 200)` |

LOC counting walks `lib/**/*.dart`, skipping blank lines, full-line `//`
comments, and generated files (`*.g.dart`, `*.freezed.dart`, `*.options.dart`).

> **`published` vs. `publish_to: none`.** A package marked `publish_to: none`
> (e.g. an internal library that lives in a public repo) is **not** `published`
> — it falls through to `works` / `not_started` on its `lib/` size. This is a
> deliberate refinement of the spec §5.1 example, which classified a
> `publish_to: none` package as published; "published" here means *a real pub
> package*, which is the more useful signal for the public site.

## License token

`PackageInfo.license` prefers a human-curated `tom_project.yaml license:`; when
absent it classifies the package's `LICENSE` / `license.md` body via
`classifyLicense` (body-driven, SPDX-or-closed vocabulary — the single source
of truth, re-exported by the website's `tool/seed/license_classifier.dart`).
Unrecognised or absent licenses yield `null`.

## Tolerating a missing `tom_project.yaml`

Eight Dart packages in the included repos have no `tom_project.yaml`. The
scanner synthesises their record from `pubspec.yaml` and the `LICENSE` body
alone; `PackageInfo.hasProjectYaml` is `false` so callers can flag them.

## Tests

```bash
dart test   # or: testkit :test
```

Fixture trees under `test/fixtures/` exercise each status branch (stub,
real-`lib/`, public publishable, release marker) and the missing-`tom_project.yaml`
case.
