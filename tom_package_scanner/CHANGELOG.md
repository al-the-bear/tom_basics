# Changelog

## 1.1.0

- **The project file is `buildkit.yaml`** (tom_build_base ^2.25.0): the curated
  `license:`, the `release.state: released` marker and
  `PackageInfo.hasProjectYaml` come from the package's `buildkit.yaml`.
  `tom_project.yaml` is retired and no longer read.

## 1.0.0

- Initial release. `PackageScanner` walks a framework repo's direct-child Dart
  packages and produces a `PackageInfo` per package: derived `ComponentStatus`
  (released → published → works → not_started), classified license token,
  version, description and external links. Built on `tom_build_base`'s
  `NatureDetector`. Tolerates packages without a `tom_project.yaml`. Extracted
  from the website's `gen_modules` generator (enterprise_flutter_web, spec §12
  todo 7).
