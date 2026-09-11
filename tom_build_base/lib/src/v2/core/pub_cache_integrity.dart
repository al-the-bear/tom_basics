import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// How a locked package fails to be usable from the pub cache.
enum PubCacheProblemKind {
  /// No directory at all. `dart pub get` re-downloads it.
  missingDirectory,

  /// The directory is there but carries no `pubspec.yaml`. Pub treats the
  /// directory's existence as "installed" and resolves straight past it, so
  /// this shape survives a `dart pub get` that reports success.
  missingPubspec,
}

/// One locked package that the pub cache cannot supply.
class PubCacheProblem {
  PubCacheProblem({
    required this.package,
    required this.version,
    required this.expectedPath,
    required this.kind,
  });

  /// Package name as the lock file spells it.
  final String package;

  /// Locked version.
  final String version;

  /// Where the cache should hold it.
  final String expectedPath;

  final PubCacheProblemKind kind;

  /// What the reader has to do, which differs by shape.
  String get remedy => switch (kind) {
        PubCacheProblemKind.missingDirectory => 'dart pub get',
        // Pub skips a directory that exists, so resolving alone repairs
        // nothing — it has to be gone before the resolve.
        PubCacheProblemKind.missingPubspec =>
          'rm -rf $expectedPath && dart pub get',
      };

  String get _what => switch (kind) {
        PubCacheProblemKind.missingDirectory => 'missing from the pub cache',
        PubCacheProblemKind.missingPubspec => 'in the pub cache but empty '
            '(no pubspec.yaml)',
      };

  @override
  String toString() => '$package $version is $_what\n'
      '    expected: $expectedPath\n'
      '    repair:   $remedy';
}

/// Checks that every hosted package a project has locked is really in the
/// pub cache.
///
/// A missing one produces no resolution error: the lock is satisfiable, so
/// `dart pub get` reports success, and the failure surfaces much later as
/// `Error: Undefined name '<Symbol>'` at every use site — followed by
/// `AOT compilation failed` when compiling. That points at the file using the
/// symbol, so it reads as an API that was renamed upstream, and nothing in it
/// mentions the cache. One stat per dependency turns that into a line of
/// output naming the package (scd8_aicx).
///
/// Only `source: hosted` entries are checked. A `path` or `sdk` dependency
/// does not live in the cache, and a missing one already fails on its own
/// terms.
class PubCacheIntegrity {
  /// The pub cache location, from `PUB_CACHE` or the platform default.
  static String defaultPubCachePath({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final explicit = env['PUB_CACHE'];
    if (explicit != null && explicit.trim().isNotEmpty) return explicit;
    if (Platform.isWindows) {
      final localAppData = env['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return p.join(localAppData, 'Pub', 'Cache');
      }
    }
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    return p.join(home, '.pub-cache');
  }

  /// Every hosted package in [projectPath]'s `pubspec.lock` the cache cannot
  /// supply, in lock order. Empty when the project has not resolved yet —
  /// nothing is locked, so nothing can be missing from it.
  static List<PubCacheProblem> checkProject({
    required String projectPath,
    String? pubCachePath,
    Map<String, String>? environment,
  }) =>
      checkLockFile(
        lockFilePath: p.join(projectPath, 'pubspec.lock'),
        pubCachePath: pubCachePath,
        environment: environment,
      );

  /// As [checkProject], for an explicit lock file path.
  static List<PubCacheProblem> checkLockFile({
    required String lockFilePath,
    String? pubCachePath,
    Map<String, String>? environment,
  }) {
    final lock = File(lockFilePath);
    if (!lock.existsSync()) return const [];

    final Object? parsed;
    try {
      parsed = loadYaml(lock.readAsStringSync());
    } on YamlException {
      // An unreadable lock is not this check's finding to report: whatever
      // wrote it, or pub itself, will say so far more precisely.
      return const [];
    }
    if (parsed is! YamlMap) return const [];
    final packages = parsed['packages'];
    if (packages is! YamlMap) return const [];

    final cacheRoot =
        pubCachePath ?? defaultPubCachePath(environment: environment);
    final hostedRoot = Directory(p.join(cacheRoot, 'hosted'));
    final problems = <PubCacheProblem>[];

    for (final entry in packages.entries) {
      final details = entry.value;
      if (details is! YamlMap) continue;
      if (details['source'] != 'hosted') continue;

      final name = _hostedName(details) ?? entry.key.toString();
      final version = details['version']?.toString() ?? '';
      final folder = '$name-$version';
      final expected = p.join(
        hostedRoot.path,
        _hostDirectory(details),
        folder,
      );

      final found = _locate(hostedRoot, expected, folder);
      if (found == null) {
        problems.add(PubCacheProblem(
          package: name,
          version: version,
          expectedPath: expected,
          kind: PubCacheProblemKind.missingDirectory,
        ));
      } else if (!File(p.join(found, 'pubspec.yaml')).existsSync()) {
        problems.add(PubCacheProblem(
          package: name,
          version: version,
          expectedPath: found,
          kind: PubCacheProblemKind.missingPubspec,
        ));
      }
    }
    return problems;
  }

  /// A report naming each package, where it should be, and the repair.
  static String describe(
    List<PubCacheProblem> problems, {
    String? projectPath,
  }) {
    if (problems.isEmpty) return '';
    final where = projectPath == null ? '' : ' for $projectPath';
    final buffer = StringBuffer()
      ..writeln('${problems.length} locked package(s)$where cannot be read '
          'from the pub cache.')
      ..writeln('This is NOT an API change: the compiler would report it as '
          "`Undefined name` at every use site, because the package's code is "
          'simply not on disk.');
    for (final problem in problems) {
      buffer.writeln('  - $problem');
    }
    return buffer.toString().trimRight();
  }

  /// The directory pub is expected to keep a hosted package under.
  ///
  /// Pub derives it from the host, encoding anything unusual. Reproducing that
  /// encoding is not worth it — [_locate] falls back to looking for the
  /// package under any host directory — so the plain host is used for the
  /// path a report quotes.
  static String _hostDirectory(YamlMap details) {
    final description = details['description'];
    final url = description is YamlMap ? description['url']?.toString() : null;
    if (url == null) return 'pub.dev';
    final host = Uri.tryParse(url)?.host;
    return (host == null || host.isEmpty) ? 'pub.dev' : host;
  }

  static String? _hostedName(YamlMap details) {
    final description = details['description'];
    if (description is YamlMap) return description['name']?.toString();
    return null;
  }

  /// [expected] if it exists, else the same `<name>-<version>` folder under
  /// any other host directory, else null.
  static String? _locate(
    Directory hostedRoot,
    String expected,
    String folder,
  ) {
    if (Directory(expected).existsSync()) return expected;
    if (!hostedRoot.existsSync()) return null;
    for (final host in hostedRoot.listSync().whereType<Directory>()) {
      final candidate = p.join(host.path, folder);
      if (Directory(candidate).existsSync()) return candidate;
    }
    return null;
  }
}
