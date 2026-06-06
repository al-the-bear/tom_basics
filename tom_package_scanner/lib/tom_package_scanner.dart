/// Scans a workspace's framework repos and, for each Dart package, derives its
/// publication status, license token, version and links.
///
/// The website's module-index generators (`gen_modules`, `gen_status_report`)
/// are thin users of [PackageScanner]: they supply a workspace root and the
/// `includedRepos` set and turn the resulting [PackageInfo] records into
/// content. See the package README for the status ladder and the license
/// vocabulary.
library;

export 'src/component_status.dart';
export 'src/license_classifier.dart';
export 'src/package_info.dart';
export 'src/package_metrics.dart';
export 'src/package_scanner.dart';
