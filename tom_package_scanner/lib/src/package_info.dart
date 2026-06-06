import 'component_status.dart';
import 'package_metrics.dart';

/// Everything the website needs to know about one Dart package discovered in a
/// framework repo.
///
/// Produced by `PackageScanner`. Immutable; the generators turn it into a
/// module-record component entry.
class PackageInfo {
  PackageInfo({
    required this.repo,
    required this.dirName,
    required this.sourcePath,
    required this.name,
    required this.status,
    required this.statusReason,
    required this.hasProjectYaml,
    this.metrics = const PackageMetrics(),
    this.version,
    this.description,
    this.publishTo,
    this.license,
    Map<String, String>? links,
  }) : links = links ?? const {};

  /// The framework repo (submodule path) this package belongs to, e.g. `d4rt`.
  final String repo;

  /// The package folder's basename, e.g. `tom_d4rt`.
  final String dirName;

  /// The package path recorded in the module record, carrying the tree prefix
  /// and always using POSIX separators, e.g.
  /// `tom_agent_container/tom_ai/d4rt/tom_d4rt`.
  final String sourcePath;

  /// The `name:` from `pubspec.yaml` (falls back to [dirName]).
  final String name;

  /// Derived publication status.
  final ComponentStatus status;

  /// Human-readable justification for [status] (drives the status report).
  final String statusReason;

  /// Whether the package carries a `tom_project.yaml`.
  final bool hasProjectYaml;

  /// Display metrics measured from the package's `lib/` and `test/` (§4.2.2).
  final PackageMetrics metrics;

  /// `version:` from `pubspec.yaml`, if any.
  final String? version;

  /// `description:` from `pubspec.yaml`, if any.
  final String? description;

  /// `publish_to:` from `pubspec.yaml` (`none` for unpublished packages, absent
  /// for the pub.dev default).
  final String? publishTo;

  /// Classified license token — from `tom_project.yaml license:` when present,
  /// otherwise from the `LICENSE` body — or `null` when unknown.
  final String? license;

  /// External links (`repository`, `homepage`) harvested from `pubspec.yaml`.
  final Map<String, String> links;

  @override
  String toString() =>
      'PackageInfo($sourcePath, ${status.yamlValue}: $statusReason)';
}
