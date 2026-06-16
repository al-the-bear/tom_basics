import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart';

import 'component_status.dart';
import 'license_classifier.dart';
import 'package_info.dart';
import 'package_metrics.dart';

/// Scans a framework repo's direct-child packages — **Dart** (`pubspec.yaml`)
/// and **TypeScript** (`package.json` + `tsconfig.json`) — and derives each
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
/// that are either a Dart package (`pubspec.yaml`) or a TypeScript package
/// (`package.json` **and** `tsconfig.json`), matching the convention
/// established by the license audit. Packages without a `tom_project.yaml` are
/// tolerated — their record is synthesised from `pubspec.yaml` / `package.json`
/// and the `LICENSE` body alone.
///
/// TypeScript packages never carry a pub version and are not pub-publishable,
/// so they never reach the `published` rung of the status ladder; they top out
/// at `released` (a `release.md` / `tom_project.yaml` marker) and otherwise
/// rank by `src/` LOC. They also have no API surface — the website's
/// doc-indexer gates that on a Dart `lib/<name>.dart`, so no extra signalling
/// is needed here.
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
  /// A `release.md` in the package dir marks the package as released. The file
  /// doubles as a documentation file (the release notes added when the project
  /// is released), so the website surfaces it alongside the authored guides.
  static const _releaseMarker = 'release.md';

  final NatureDetector _natures = NatureDetector();

  /// Scan every direct-child package of [repo] (a submodule path under
  /// [pathPrefix]) — Dart and TypeScript alike. [repoIsPublic] feeds the
  /// `published` branch (Dart only).
  ///
  /// Returns the packages sorted by [PackageInfo.dirName] for stable,
  /// diff-friendly output. An absent repo dir yields an empty list.
  List<PackageInfo> scanRepo(String repo, {required bool repoIsPublic}) {
    final repoDir = Directory(_repoPath(repo));
    if (!repoDir.existsSync()) return const [];

    final packages = <PackageInfo>[];
    for (final entity in repoDir.listSync()) {
      if (entity is! Directory) continue;
      if (!_isPackageDir(entity.path)) continue;
      packages.add(_describe(repo, entity.path, repoIsPublic: repoIsPublic));
    }
    packages.sort((a, b) => a.dirName.compareTo(b.dirName));
    return packages;
  }

  /// Filesystem path to a repo dir.
  String _repoPath(String repo) =>
      p.joinAll([sourceRoot, ...p.posix.split(pathPrefix), repo]);

  /// Whether [dir] is a scannable package: a Dart package (`pubspec.yaml`) or a
  /// TypeScript package (`package.json` **and** `tsconfig.json`).
  bool _isPackageDir(String dir) =>
      _isDartPackageDir(dir) ||
      (File(p.join(dir, 'package.json')).existsSync() &&
          File(p.join(dir, 'tsconfig.json')).existsSync());

  /// Whether [dir] carries a `pubspec.yaml` (a Dart package). A package with
  /// both `pubspec.yaml` and `package.json` is described as Dart.
  bool _isDartPackageDir(String dir) =>
      File(p.join(dir, 'pubspec.yaml')).existsSync();

  /// Build a [PackageInfo] for one package directory, dispatching on language.
  PackageInfo _describe(String repo, String dir, {required bool repoIsPublic}) =>
      _isDartPackageDir(dir)
          ? _describeDart(repo, dir, repoIsPublic: repoIsPublic)
          : _describeTypeScript(repo, dir, repoIsPublic: repoIsPublic);

  /// Build a [PackageInfo] for a Dart package.
  PackageInfo _describeDart(
    String repo,
    String dir, {
    required bool repoIsPublic,
  }) {
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
      isPublishable: dart?.isPublishable ?? false,
      publishVersion: dart?.version,
      repoIsPublic: repoIsPublic,
      sourceLoc: metrics.loc,
      tom: tom,
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

  /// Build a [PackageInfo] for a TypeScript package.
  ///
  /// TypeScript packages are not pub packages: [PackageInfo.publishTo] is
  /// always `null`, and the status ladder skips the `published` rung (they top
  /// out at `released`/`works`). The name is the directory name (npm package
  /// names can be scoped/aliased; the folder is the stable identifier the rest
  /// of the catalog keys on). Metrics come from `src/`/`test/` `.ts` files.
  PackageInfo _describeTypeScript(
    String repo,
    String dir, {
    required bool repoIsPublic,
  }) {
    final natures = _natures.detectNatures(FsFolder(path: dir));
    final tom = natures.whereType<TomBuildFolder>().firstOrNull;

    final dirName = p.basename(dir);
    final pkg = _readPackageJson(dir);
    final version = pkg['version'] as String?;
    final license = _resolveLicense(dir, tom) ?? pkg['license'] as String?;

    final metrics = _measureTypeScript(dir);

    final status = _deriveStatus(
      dir,
      isPublishable: false,
      publishVersion: null,
      repoIsPublic: repoIsPublic,
      sourceLoc: metrics.loc,
      tom: tom,
      sourceDirName: 'src',
    );

    return PackageInfo(
      repo: repo,
      dirName: dirName,
      sourcePath: p.posix.joinAll([pathPrefix, repo, dirName]),
      name: dirName,
      status: status.status,
      statusReason: status.reason,
      hasProjectYaml: tom != null,
      metrics: metrics,
      version: version,
      description: pkg['description'] as String?,
      publishTo: null,
      license: license,
      links: _linksFromPackageJson(pkg),
    );
  }

  /// Derive a package's [ComponentStatus] and a human-readable reason.
  ///
  /// Ladder (spec §4.2.1): release marker → public + publishable → real source
  /// → stub. [isPublishable]/[publishVersion] drive the `published` rung
  /// (TypeScript passes `false`/`null`, so it never reaches it). [sourceDirName]
  /// is the production-source folder name (`lib` for Dart, `src` for
  /// TypeScript) used in the reason text and the stub/no-source check.
  ({ComponentStatus status, String reason}) _deriveStatus(
    String dir, {
    required bool isPublishable,
    required String? publishVersion,
    required bool repoIsPublic,
    required int sourceLoc,
    required TomBuildFolder? tom,
    String sourceDirName = 'lib',
  }) {
    if (_hasReleaseMarker(dir, tom)) {
      return (status: ComponentStatus.released, reason: 'release marker');
    }
    if (repoIsPublic && isPublishable) {
      return (
        status: ComponentStatus.published,
        reason: 'public repo; pub version $publishVersion',
      );
    }
    if (sourceLoc > locThreshold) {
      return (
        status: ComponentStatus.works,
        reason: '$sourceDirName/ $sourceLoc LOC',
      );
    }
    final hasSource = Directory(p.join(dir, sourceDirName)).existsSync();
    return (
      status: ComponentStatus.notStarted,
      reason: hasSource
          ? 'stub ($sourceLoc LOC ≤ $locThreshold)'
          : 'no $sourceDirName/',
    );
  }

  /// A package is released when its `tom_project.yaml` declares
  /// `release.state: released`, or when a `release.md` sits in its dir.
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

  /// Parse `package.json` into a map, or an empty map when absent/malformed.
  Map<String, dynamic> _readPackageJson(String dir) {
    final file = File(p.join(dir, 'package.json'));
    if (!file.existsSync()) return const {};
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  /// Extract `repository`/`homepage` links from a parsed `package.json`. npm's
  /// `repository` may be a bare URL string or a `{ "type", "url" }` object, so
  /// both shapes resolve to a `repository` link.
  Map<String, String> _linksFromPackageJson(Map<String, dynamic> pkg) {
    final links = <String, String>{};
    final repository = pkg['repository'];
    if (repository is String && repository.trim().isNotEmpty) {
      links['repository'] = repository.trim();
    } else if (repository is Map && repository['url'] is String) {
      final url = (repository['url'] as String).trim();
      if (url.isNotEmpty) links['repository'] = url;
    }
    final homepage = pkg['homepage'];
    if (homepage is String && homepage.trim().isNotEmpty) {
      links['homepage'] = homepage.trim();
    }
    return links;
  }

  /// Matches a `test(` / `testWidgets(` invocation (whole word, optional space).
  static final _testCall = RegExp(r'\b(test|testWidgets)\s*\(');

  /// Matches a `test(` / `it(` invocation in TypeScript test files (Jest/Mocha
  /// style), the TypeScript analogue of [_testCall].
  static final _tsTestCall = RegExp(r'\b(test|it)\s*\(');

  /// Measure the §4.2.2 display metrics: `loc` (real `lib/` Dart lines), `tests`
  /// (count of `test(` / `testWidgets(` calls in `test/`) and `testLoc` (real
  /// `test/` Dart lines). All static — no `dart test`, no process calls.
  PackageMetrics _measure(String dir) => PackageMetrics(
        loc: _codeLines(p.join(dir, 'lib')),
        tests: _testCount(p.join(dir, 'test')),
        testLoc: _codeLines(p.join(dir, 'test')),
      );

  /// Count real Dart lines under [dirPath], excluding generated files. Used for
  /// both `lib/` (`loc`, incl. the >200-rule) and `test/` (`testLoc`).
  int _codeLines(String dirPath) {
    var total = 0;
    for (final file in _dartFiles(dirPath)) {
      total += _realLines(file);
    }
    return total;
  }

  /// Count `test(` / `testWidgets(` invocations under [dirPath]. A static
  /// approximation of the test-case count (§4.2.2); the scanner runs no
  /// `dart test`.
  int _testCount(String dirPath) {
    var count = 0;
    for (final file in _dartFiles(dirPath)) {
      count += _countCalls(file, _testCall);
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

  /// Measure the §4.2.2 metrics for a TypeScript package. `loc` counts the
  /// production `src/` `.ts` (excluding `*.d.ts` declarations and `*.test.ts` /
  /// `*.spec.ts` test files); `tests`/`testLoc` come from those test files plus
  /// any sibling `test/` dir. The `loc` total feeds the status ladder, so the
  /// >200-rule sees production code only.
  PackageMetrics _measureTypeScript(String dir) {
    var loc = 0;
    var tests = 0;
    var testLoc = 0;
    for (final file in _tsFiles(p.join(dir, 'src'))) {
      if (_isTsTestFile(file)) {
        testLoc += _realLines(file);
        tests += _countCalls(file, _tsTestCall);
      } else {
        loc += _realLines(file);
      }
    }
    for (final file in _tsFiles(p.join(dir, 'test'))) {
      testLoc += _realLines(file);
      tests += _countCalls(file, _tsTestCall);
    }
    return PackageMetrics(loc: loc, tests: tests, testLoc: testLoc);
  }

  /// Non-declaration `.ts` files under [dirPath] (recursive); empty when the
  /// directory is absent. `*.d.ts` declaration files are skipped — they are
  /// generated/type-only, not source LOC.
  Iterable<File> _tsFiles(String dirPath) sync* {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.ts') || name.endsWith('.d.ts')) continue;
      yield entity;
    }
  }

  /// Whether [file] is a TypeScript test file (`*.test.ts` / `*.spec.ts`).
  bool _isTsTestFile(File file) {
    final name = p.basename(file.path);
    return name.endsWith('.test.ts') || name.endsWith('.spec.ts');
  }

  /// Count real (non-blank, non-full-line-comment) lines in [file]. Shared by
  /// the Dart and TypeScript LOC counters.
  int _realLines(File file) {
    var total = 0;
    for (final raw in file.readAsStringSync().split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('//')) continue;
      total++;
    }
    return total;
  }

  /// Count [pattern] matches in [file], ignoring blank and full-line-comment
  /// lines. Shared by the Dart and TypeScript test-call counters.
  int _countCalls(File file, RegExp pattern) {
    var count = 0;
    for (final raw in file.readAsStringSync().split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('//')) continue;
      count += pattern.allMatches(line).length;
    }
    return count;
  }
}
