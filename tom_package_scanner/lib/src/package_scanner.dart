import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart';

import 'component_status.dart';
import 'license_classifier.dart';
import 'package_info.dart';
import 'package_metrics.dart';

/// Scans a framework repo's direct-child Dart packages and derives each
/// package's publication status, license, version and links.
///
/// Built on `tom_build_base`'s [NatureDetector] for Dart-package /
/// `tom_project.yaml` detection. The scanner performs **no** process calls and
/// makes no network / `gh` requests: whether a repo is public is supplied by
/// the caller ([scanRepo]'s `repoIsPublic`), because the website's
/// `includedRepos` seed already resolved that (spec §12, todo 6) — re-deriving
/// it per package would be redundant I/O. This keeps the status logic pure and
/// unit-testable against fixture trees.
///
/// Package discovery is **one level deep**: the direct child folders of a repo
/// that carry a `pubspec.yaml`, matching the convention established by the
/// license audit. Packages without a `tom_project.yaml` are tolerated — their
/// record is synthesised from `pubspec.yaml` and the `LICENSE` body alone.
class PackageScanner {
  PackageScanner({
    required this.sourceRoot,
    required this.pathPrefix,
    this.locThreshold = 200,
  });

  /// Filesystem base the repo trees live under (e.g. `../..`, the
  /// `enterprise_flutter/` container relative to `website/`).
  final String sourceRoot;

  /// Logical path prefix recorded in each component's `path`, and prepended
  /// under [sourceRoot] to reach a repo on disk, e.g.
  /// `tom_agent_container/tom_ai`. Always POSIX-separated.
  final String pathPrefix;

  /// `lib/` LOC strictly above which a package counts as real code ("works")
  /// rather than a stub ("not_started").
  final int locThreshold;

  static const _licenseNames = [
    'LICENSE',
    'LICENSE.md',
    'LICENSE.txt',
    'license.md',
  ];
  static const _releaseMarker = 'RELEASED.md';

  final NatureDetector _natures = NatureDetector();

  /// Scan every direct-child Dart package of [repo] (a submodule path under
  /// [pathPrefix]). [repoIsPublic] feeds the `published` branch.
  ///
  /// Returns the packages sorted by [PackageInfo.dirName] for stable,
  /// diff-friendly output. An absent repo dir yields an empty list.
  List<PackageInfo> scanRepo(String repo, {required bool repoIsPublic}) {
    final repoDir = Directory(_repoPath(repo));
    if (!repoDir.existsSync()) return const [];

    final packages = <PackageInfo>[];
    for (final entity in repoDir.listSync()) {
      if (entity is! Directory) continue;
      if (!File(p.join(entity.path, 'pubspec.yaml')).existsSync()) continue;
      packages.add(_describe(repo, entity.path, repoIsPublic: repoIsPublic));
    }
    packages.sort((a, b) => a.dirName.compareTo(b.dirName));
    return packages;
  }

  /// Filesystem path to a repo dir.
  String _repoPath(String repo) =>
      p.joinAll([sourceRoot, ...p.posix.split(pathPrefix), repo]);

  /// Build a [PackageInfo] for one package directory.
  PackageInfo _describe(String repo, String dir, {required bool repoIsPublic}) {
    final natures = _natures.detectNatures(FsFolder(path: dir));
    final dart = natures.whereType<DartProjectFolder>().firstOrNull;
    final tom = natures.whereType<TomBuildFolder>().firstOrNull;

    final dirName = p.basename(dir);
    final pubspec = dart?.pubspec ?? const <String, dynamic>{};
    final version = dart?.version;
    final publishTo = pubspec['publish_to'] as String?;
    final license = _resolveLicense(dir, tom);

    // Measure once; `loc` is reused by the status ladder so the >200-rule and
    // the displayed metric never disagree (spec §4.2.1 / §4.2.2).
    final metrics = _measure(dir);

    final status = _deriveStatus(
      dir,
      dart: dart,
      tom: tom,
      repoIsPublic: repoIsPublic,
      libLoc: metrics.loc,
    );

    return PackageInfo(
      repo: repo,
      dirName: dirName,
      sourcePath: p.posix.joinAll([pathPrefix, repo, dirName]),
      name: dart?.projectName ?? dirName,
      status: status.status,
      statusReason: status.reason,
      hasProjectYaml: tom != null,
      metrics: metrics,
      version: version,
      description: pubspec['description'] as String?,
      publishTo: publishTo,
      license: license,
      links: _links(pubspec),
    );
  }

  /// Derive a package's [ComponentStatus] and a human-readable reason.
  ///
  /// Ladder (spec §4.2.1): release marker → public + publishable → real `lib/`
  /// → stub.
  ({ComponentStatus status, String reason}) _deriveStatus(
    String dir, {
    required DartProjectFolder? dart,
    required TomBuildFolder? tom,
    required bool repoIsPublic,
    required int libLoc,
  }) {
    if (_hasReleaseMarker(dir, tom)) {
      return (status: ComponentStatus.released, reason: 'release marker');
    }
    if (repoIsPublic && (dart?.isPublishable ?? false)) {
      return (
        status: ComponentStatus.published,
        reason: 'public repo; pub version ${dart!.version}',
      );
    }
    final loc = libLoc;
    if (loc > locThreshold) {
      return (status: ComponentStatus.works, reason: 'lib/ $loc LOC');
    }
    final hasLib = Directory(p.join(dir, 'lib')).existsSync();
    return (
      status: ComponentStatus.notStarted,
      reason: hasLib ? 'stub ($loc LOC ≤ $locThreshold)' : 'no lib/',
    );
  }

  /// A package is released when its `tom_project.yaml` declares
  /// `release.state: released`, or when a `RELEASED.md` sits in its dir.
  bool _hasReleaseMarker(String dir, TomBuildFolder? tom) {
    if (File(p.join(dir, _releaseMarker)).existsSync()) return true;
    final release = tom?.config['release'];
    if (release is Map) return release['state'] == 'released';
    return false;
  }

  /// Prefer a human-curated `tom_project.yaml license:`; otherwise classify the
  /// `LICENSE` / `license.md` body. Returns `null` when neither yields a token.
  String? _resolveLicense(String dir, TomBuildFolder? tom) {
    final declared = tom?.config['license'];
    if (declared is String && declared.trim().isNotEmpty) return declared.trim();
    final file = _findLicense(dir);
    return file == null ? null : classifyLicense(file.readAsStringSync());
  }

  File? _findLicense(String dir) {
    for (final name in _licenseNames) {
      final f = File(p.join(dir, name));
      if (f.existsSync()) return f;
    }
    return null;
  }

  Map<String, String> _links(Map<String, dynamic> pubspec) {
    final links = <String, String>{};
    for (final key in const ['repository', 'homepage']) {
      final value = pubspec[key];
      if (value is String && value.trim().isNotEmpty) links[key] = value.trim();
    }
    return links;
  }

  /// Matches a `test(` / `testWidgets(` invocation (whole word, optional space).
  static final _testCall = RegExp(r'\b(test|testWidgets)\s*\(');

  /// Measure the §4.2.2 display metrics: `loc` (real `lib/` Dart lines), `tests`
  /// (count of `test(` / `testWidgets(` calls in `test/`) and `testLoc` (real
  /// `test/` Dart lines). All static — no `dart test`, no process calls.
  PackageMetrics _measure(String dir) => PackageMetrics(
        loc: _codeLines(p.join(dir, 'lib')),
        tests: _testCount(p.join(dir, 'test')),
        testLoc: _codeLines(p.join(dir, 'test')),
      );

  /// Count real Dart lines under [dirPath] — non-blank, non-full-line-comment
  /// lines — excluding generated files (`*.g.dart`, `*.freezed.dart`,
  /// `*.options.dart`). Used for both `lib/` (`loc`, incl. the >200-rule) and
  /// `test/` (`testLoc`).
  int _codeLines(String dirPath) {
    var total = 0;
    for (final file in _dartFiles(dirPath)) {
      for (final raw in file.readAsStringSync().split('\n')) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('//')) continue;
        total++;
      }
    }
    return total;
  }

  /// Count `test(` / `testWidgets(` invocations under [dirPath], ignoring
  /// full-line comments. A static approximation of the test-case count (§4.2.2);
  /// the scanner runs no `dart test`.
  int _testCount(String dirPath) {
    var count = 0;
    for (final file in _dartFiles(dirPath)) {
      for (final raw in file.readAsStringSync().split('\n')) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('//')) continue;
        count += _testCall.allMatches(line).length;
      }
    }
    return count;
  }

  /// Non-generated `.dart` files under [dirPath] (recursive); empty when the
  /// directory is absent.
  Iterable<File> _dartFiles(String dirPath) sync* {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.dart')) continue;
      if (name.endsWith('.g.dart') ||
          name.endsWith('.freezed.dart') ||
          name.endsWith('.options.dart')) {
        continue;
      }
      yield entity;
    }
  }
}
