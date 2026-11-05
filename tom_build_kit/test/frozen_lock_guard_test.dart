// REPO-WIDE GUARD (tom_build_kit) — no package in tom_ai/basics resolves a
// tom_* version behind one already in the pub cache.
//
// This is the tom_ai/basics repo's own copy of the d4rt repo's
// `tom_d4rt_ast/test/scc45_resolution_guard_test.dart`, which is the model and
// carries the full history of the defect family. It follows the tom_ai/core
// copy (`tom_core_kernel/test/frozen_lock_guard_test.dart`) and adds the
// model's held-back ranges (`tom_d4rt_ast/tool/stale_locks.dart`
// `heldBackVersions`). What follows states only what this copy needs to be
// read on its own.
//
// WHY A FROZEN LOCK MATTERS. `dart pub get` is LOCK-PRESERVING: a lower-bound
// constraint admits every newer release without ever selecting one once a lock
// exists. `pubspec.lock` is gitignored, so the staleness is per-machine and
// invisible in any diff: two hosts run the same suite against different
// dependency sets and nothing records which. A suite green against a frozen
// lock certifies a version nobody installs.
//
// THE CACHE IS THE DISCRIMINATOR. A newer version sitting in
// `~/.pub-cache/hosted/pub.dev/` proves pub had it on hand and did not take
// it. Comparing against a sibling's pubspec instead cannot tell a frozen lock
// from an unpublished sibling. The inference is one-directional: a cold cache
// under-reports, so a pass is a floor, and the sensitivity line printed on
// every run says how strong it is on this machine.
//
// THE CACHE PROVES A VERSION WAS ON HAND, NOT THAT IT WAS ADMISSIBLE. A newer
// release can require something no package here can take (tom_analyzer_shared
// 0.8.0 needs analyzer ^14 while tom_d4rt holds its consumers on ^10). Such a
// range is HELD BACK, with the todo that lifts it; FL-4 fails once a hold no
// longer holds any lock back.
//
// WHAT THIS REPO HAD. Filed 2026-09-22 (build_tom frozenlocks_aivu): 3 frozen
// resolutions across 3 packages (tom_analyzer_shared and tom_build_kit on
// tom_build_base, tom_crypto on tom_basics). Re-measured 2026-11-06 on mbp
// before this file was added: none left — the publishes since had re-resolved
// them.
//
// WHY IT LIVES HERE. tom_build_kit is the repo's build orchestrator, owned by
// the same quest as tom_build_base, the package most often found frozen
// workspace-wide. The test only reads sibling locks and skips when the repo
// root is not reachable, so it costs a consumer of the published package
// nothing.
//
// MANY GUARDS, NOT ONE. A single workspace guard would need one exception list
// spanning a dozen repos with no owner; each repo carries its own copy with
// its own owner-named list. `_bin/check_frozen_locks.py tom_ai/basics` asks
// the same question read-only from outside.
//
// ZERO NEW DEPENDENCIES, like the model: the lock is parsed by indentation,
// since it is machine-written and its shape is fixed.
import 'dart:io';

import 'package:test/test.dart';

/// Packages whose presence identifies the tom_ai/basics repo root.
const _repoMarkers = ['tom_basics', 'tom_build_base', 'tom_build_kit'];

/// Only this workspace's own packages: a third-party dependency cannot suffer
/// an unpropagated publish from here.
const _ownedPrefix = 'tom_';

/// Top-level packages exempted from FL-2, each with the todo that unfreezes
/// it. AN EXCEPTION WITHOUT AN OWNER IS A LEAK: if you add one and cannot name
/// who unfreezes it, find that out first. FL-3 fails once an entry stops
/// describing a frozen lock.
const Map<String, String> _frozenLockExceptions = <String, String>{};

/// A range of cached versions of one package that no lock here can take.
class _HeldBack {
  const _HeldBack({
    required this.from,
    required this.owner,
    required this.reason,
  });

  /// The first held-back version: it and every later one are ignored.
  final String from;

  /// The todo whose work lets the locks take them, and deletes this entry.
  final String owner;

  /// Why no lock here can resolve them.
  final String reason;
}

/// Cached versions FL-2 ignores, by package name. FL-4 fails once one no
/// longer holds any lock back.
const Map<String, _HeldBack> _heldBackVersions = <String, _HeldBack>{};

/// Below this many distinct cached `tom_*` packages, a pass means nothing: the
/// discriminator can only see a freeze whose newer version is cached here.
const int _minimumCachedPackages = 5;

class _Resolution {
  const _Resolution(this.name, this.source, this.version, this.dependency);
  final String name;
  final String source;
  final String version;

  /// The lock's own classification: `direct main`, `direct dev`, `direct
  /// overridden` or `transitive`.
  final String dependency;

  bool get isDirect => dependency.startsWith('direct');
}

class _StaleLock {
  const _StaleLock(this.package, this.dependency, this.locked, this.cached);
  final String package;
  final String dependency;
  final String locked;
  final String cached;

  @override
  String toString() =>
      '$package locks $dependency $locked while $cached is already in the '
      'pub cache';
}

Directory? _repoRoot() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    if (_repoMarkers.every((p) => Directory('${dir.path}/$p').existsSync())) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

/// Directories whose packages are nobody's to upgrade: build output and the
/// untracked scratch under `ztmp/` and `testlog/`.
bool _pruned(Directory dir) {
  final name = dir.path.split(Platform.pathSeparator).last;
  return name.startsWith('.') ||
      name == 'build' ||
      name == 'node_modules' ||
      name == 'ztmp' ||
      name == 'testlog';
}

/// Every directory under [root] holding a pubspec and a lock.
///
/// Walks nested packages too: a fixture or sample under a package carries its
/// own ignored lock, and a guard that inspected only top-level packages would
/// report green through exactly the case that hides.
List<Directory> _packagesUnder(Directory root) {
  final found = <Directory>[];
  void walk(Directory dir, int depth) {
    if (depth > 5 || _pruned(dir)) return;
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        File('${dir.path}/pubspec.lock').existsSync()) {
      found.add(dir);
    }
    for (final child in dir.listSync().whereType<Directory>()) {
      walk(child, depth + 1);
    }
  }

  walk(root, 0);
  return found;
}

List<_Resolution> _lockedTomPackages(Directory package) {
  final lock = File('${package.path}/pubspec.lock');
  if (!lock.existsSync()) return const [];
  final namePattern = RegExp(r'^  ([A-Za-z0-9_]+):\s*$');
  final fieldPattern = RegExp(
    r'^    (dependency|source|version):\s*"?([^"]*)"?\s*$',
  );
  final out = <_Resolution>[];
  String? current, source, version, dependency;
  void flush() {
    if (current != null &&
        current!.startsWith(_ownedPrefix) &&
        source != null &&
        version != null) {
      out.add(_Resolution(current!, source!, version!, dependency ?? ''));
    }
    current = source = version = dependency = null;
  }

  for (final line in lock.readAsLinesSync()) {
    final name = namePattern.firstMatch(line);
    if (name != null) {
      flush();
      current = name.group(1);
      continue;
    }
    final field = fieldPattern.firstMatch(line);
    if (field == null || current == null) continue;
    switch (field.group(1)) {
      case 'source':
        source = field.group(2);
      case 'version':
        version = field.group(2);
      default:
        dependency = field.group(2);
    }
  }
  flush();
  return out;
}

int _compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Pub's own order: `PUB_CACHE` when set and non-empty, then the platform
/// default. The Windows default matters: a guard that looked only at
/// `$HOME/.pub-cache` reports an empty cache there, and so passes blind.
Directory _pubCacheRoot() {
  final explicit = Platform.environment['PUB_CACHE'];
  if (explicit != null && explicit.trim().isNotEmpty) {
    return Directory(explicit);
  }
  if (Platform.isWindows) {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) {
      return Directory('$local\\Pub\\Cache');
    }
  }
  return Directory('${Platform.environment['HOME'] ?? ''}/.pub-cache');
}

Directory get _hostedCache =>
    Directory('${_pubCacheRoot().path}/hosted/pub.dev');

/// The newest stable cached version of [name], or with [below] the newest one
/// older than it.
String? _newestCachedVersion(String name, {String? below}) {
  final dir = _hostedCache;
  if (!dir.existsSync()) return null;
  final prefix = '$name-';
  final stable = dir
      .listSync()
      .whereType<Directory>()
      .map((d) => d.path.split(Platform.pathSeparator).last)
      .where((n) => n.startsWith(prefix))
      .map((n) => n.substring(prefix.length))
      .where((v) => !v.contains('-') && RegExp(r'^\d').hasMatch(v))
      .where((v) => below == null || _compareVersions(v, below) < 0)
      .toList();
  if (stable.isEmpty) return null;
  stable.sort(_compareVersions);
  return stable.last;
}

String _relativeTo(Directory root, Directory dir) =>
    (dir.path.startsWith(root.path)
            ? dir.path.substring(root.path.length + 1)
            : dir.path)
        .replaceAll(r'\', '/');

/// Every lock under [root] resolving a hosted `tom_*` older than the cache
/// holds, skipping top-level packages in [exceptions] and the [heldBack]
/// ranges.
List<_StaleLock> _staleLocks(
  Directory root, {
  Map<String, String> exceptions = const {},
  Map<String, _HeldBack> heldBack = _heldBackVersions,
}) {
  final out = <_StaleLock>[];
  for (final package in _packagesUnder(root)) {
    final rel = _relativeTo(root, package);
    if (exceptions.containsKey(rel.split('/').first)) continue;
    for (final res in _lockedTomPackages(package)) {
      if (res.source != 'hosted') continue;
      final newest = _newestCachedVersion(
        res.name,
        below: heldBack[res.name]?.from,
      );
      if (newest != null && _compareVersions(res.version, newest) < 0) {
        out.add(_StaleLock(rel, res.name, res.version, newest));
      }
    }
  }
  return out;
}

/// Dependency names [package]'s pubspec declares with a `path:` key.
Set<String> _declaredPathDependencies(Directory package) {
  final keyPattern = RegExp(r'^(\s+)([A-Za-z0-9_]+):\s*$');
  final declared = <String>{};
  String? openKey;
  var openIndent = 0;
  for (final raw in File('${package.path}/pubspec.yaml').readAsLinesSync()) {
    final line = raw.split('#').first;
    if (line.trim().isEmpty) continue;
    final indent = line.length - line.trimLeft().length;
    if (openKey != null) {
      if (indent > openIndent) {
        if (line.trimLeft().startsWith('path:')) declared.add(openKey);
        continue;
      }
      openKey = null;
    }
    if (keyPattern.firstMatch(line) case final m?) {
      openKey = m.group(2);
      openIndent = m.group(1)!.length;
    }
  }
  return declared;
}

void main() {
  final root = _repoRoot();

  group('frozen locks (tom_ai/basics): resolutions match declarations', () {
    var cachedPackages = 0;

    setUpAll(() {
      final cache = _hostedCache;
      final byPackage = <String, int>{};
      if (cache.existsSync()) {
        for (final entry in cache.listSync().whereType<Directory>()) {
          final dir = entry.path.split(Platform.pathSeparator).last;
          if (!dir.startsWith(_ownedPrefix)) continue;
          final dash = dir.lastIndexOf('-');
          if (dash <= 0) continue;
          byPackage.update(
            dir.substring(0, dash),
            (n) => n + 1,
            ifAbsent: () => 1,
          );
        }
      }
      cachedPackages = byPackage.length;
      // Printed on every run: a pass is a statement about THIS machine's cache,
      // and the number is what makes a green interpretable.
      // ignore: avoid_print
      print(
        '[frozen locks] pub-cache sensitivity: '
        '${byPackage.values.fold(0, (a, b) => a + b)} tom_* version '
        'directories across $cachedPackages packages, '
        '${byPackage.values.where((n) => n > 1).length} holding more than '
        'one version.',
      );
    });

    bool canDiscriminate(String caseName) {
      if (cachedPackages >= _minimumCachedPackages) return true;
      markTestSkipped(
        '$caseName cannot answer on this machine: its pub cache '
        'holds $cachedPackages distinct tom_* package(s), below the '
        '$_minimumCachedPackages needed to tell a frozen lock from a current '
        'one. A pass here would be indistinguishable from a clean repo.',
      );
      return false;
    }

    bool rootReachable() {
      if (root != null) return true;
      markTestSkipped(
        'tom_ai/basics repo root not reachable — nothing to check',
      );
      return false;
    }

    test('FL-1: no undeclared path resolution', () {
      if (!rootReachable()) return;
      final offenders = <String>[];
      for (final package in _packagesUnder(root!)) {
        // An overrides file is a declaration too.
        if (File('${package.path}/pubspec_overrides.yaml').existsSync()) {
          continue;
        }
        final declared = _declaredPathDependencies(package);
        for (final res in _lockedTomPackages(package)) {
          // DIRECT only: a transitive source is decided by the dependency that
          // declares it. The defect this catches — a declaration dropped while
          // the lock keeps resolving the path — is always a direct one.
          if (!res.isDirect) continue;
          if (res.source == 'path' && !declared.contains(res.name)) {
            offenders.add(
              '${_relativeTo(root, package)} resolves ${res.name} '
              'from path (${res.version}) but declares no path dependency',
            );
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'These test against a local working tree while their '
            'pubspec advertises a published version. Run `pub get` in each; '
            'pub discards a path resolution the pubspec no longer declares.\n'
            '${offenders.join('\n')}',
      );
    });

    test('FL-2: no lock is behind a version already in the pub cache', () {
      if (!rootReachable() || !canDiscriminate('FL-2')) return;
      final offenders = _staleLocks(
        root!,
        exceptions: _frozenLockExceptions,
      ).map((s) => s.toString()).toList();
      expect(
        offenders,
        isEmpty,
        reason:
            '`pub get` is lock-preserving, so these locks were passed '
            'over by a resolution that had the newer version on hand.\n'
            'REMEDY: `dart pub upgrade` (or `flutter pub upgrade`) in each '
            'package, AND in every nested sample or fixture under it; then '
            'run the suite. If an upgrade does NOT move a version, the cause '
            'is the other one — a constraint holding it (hold the range in '
            '`_heldBackVersions`, naming the todo that lifts it), or '
            'unpublished work in the sibling working tree (publish it) — not '
            'something a re-resolve fixes.\n${offenders.join('\n')}',
      );
    });

    test('FL-3: every exception is still load-bearing', () {
      if (!rootReachable()) return;
      // Measured with NO exceptions applied: the question is which packages
      // are still frozen, and the exception list would hide exactly those.
      final stillFrozen = _staleLocks(
        root!,
      ).map((s) => s.package.split('/').first).toSet();
      final obsolete = _frozenLockExceptions.keys.toSet().difference(
        stillFrozen,
      );
      expect(
        obsolete,
        isEmpty,
        reason:
            'Exempted but no longer frozen — the exemption now grants '
            'only the right to freeze again unnoticed. Delete: '
            '${obsolete.join(', ')}',
      );
    });

    test('FL-4: every held-back range still holds a lock back', () {
      if (!rootReachable() || !canDiscriminate('FL-4')) return;
      // Measured with NO holds applied, for the reason FL-3 measures without
      // exceptions: the holds would hide exactly the locks being asked about.
      final lagging = _staleLocks(
        root!,
        exceptions: _frozenLockExceptions,
        heldBack: const {},
      );
      final obsolete = [
        for (final entry in _heldBackVersions.entries)
          if (!lagging.any(
            (s) =>
                s.dependency == entry.key &&
                _compareVersions(s.cached, entry.value.from) >= 0,
          ))
            '${entry.key} >= ${entry.value.from} (owner ${entry.value.owner})',
      ];
      expect(
        obsolete,
        isEmpty,
        reason:
            'These holds no longer hold any lock back: every package now '
            'resolves the held-back range, so its constraint has been '
            'lifted. Delete the entries; a hold that outlives its reason '
            'hides the next real lag.\n${obsolete.join('\n')}',
      );
    });
  });
}
