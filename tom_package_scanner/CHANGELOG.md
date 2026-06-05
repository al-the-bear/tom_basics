# Changelog

## 1.0.0

- Initial release. `PackageScanner` walks a framework repo's direct-child Dart
  packages and produces a `PackageInfo` per package: derived `ComponentStatus`
  (released → published → works → not_started), classified license token,
  version, description and external links. Built on `tom_build_base`'s
  `NatureDetector`. Tolerates packages without a `tom_project.yaml`. Extracted
  from the website's `gen_modules` generator (enterprise_flutter_web, spec §12
  todo 7).
