// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Runtime location of the Dart SDK for analyzer-based tooling.
///
/// The Dart analyzer derives the SDK directory from
/// [Platform.resolvedExecutable] when no explicit `sdkPath` is given. That is
/// correct when a tool runs under `dart run` (the executable is the `dart`
/// binary, so the SDK is its grandparent), but **wrong** for an AOT-compiled
/// executable produced by `dart compile exe`: there `resolvedExecutable` points
/// at the tool itself (e.g. `$TOM_BINARY_PATH/<plat>/reflectiongenerator.exe`),
/// so the analyzer looks for `lib/_internal/allowed_experiments.json` next to
/// the binary and fails with a `PathNotFoundException`.
///
/// [resolveDartSdkPath] locates the real SDK using a few PATH/environment
/// heuristics so compiled Tom tools work when invoked via `buildkit`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Cached SDK path — resolved once, reused across calls within a process.
String? _cachedSdkPath;

/// Set in tests to bypass the process-lifetime cache.
bool _cacheEnabled = true;

/// Resolves the Dart SDK root directory, or `null` to let the analyzer fall
/// back to its default (executable-relative) detection.
///
/// Resolution order (first match wins):
/// 1. `DART_SDK` environment variable.
/// 2. `DART_HOME` environment variable.
/// 3. [Platform.resolvedExecutable] — correct under `dart run`, where it points
///    at the `dart` binary inside the SDK. For compiled binaries this points at
///    the tool itself and is silently skipped (it won't look like an SDK).
/// 4. The `dart` executable on `PATH` (`which`/`where`), with symlinks
///    resolved. Handles both the standalone layout (`<sdk>/bin/dart`) and the
///    Flutter wrapper (`<flutter>/bin/dart` → `<flutter>/bin/cache/dart-sdk`).
/// 5. The `flutter` executable on `PATH` → `<flutter>/bin/cache/dart-sdk`.
///
/// Every candidate is validated with [looksLikeDartSdk] before being returned,
/// so a stale environment variable or an unrelated `dart` on `PATH` never
/// yields a bogus path. The result is cached for the lifetime of the process.
String? resolveDartSdkPath() {
  if (_cacheEnabled && _cachedSdkPath != null) return _cachedSdkPath;

  final resolved = _resolveUncached();
  if (_cacheEnabled) _cachedSdkPath = resolved;
  return resolved;
}

String? _resolveUncached() {
  // 1. DART_SDK environment variable.
  final dartSdkEnv = Platform.environment['DART_SDK'];
  if (looksLikeDartSdk(dartSdkEnv)) return dartSdkEnv;

  // 2. DART_HOME environment variable.
  final dartHomeEnv = Platform.environment['DART_HOME'];
  if (looksLikeDartSdk(dartHomeEnv)) return dartHomeEnv;

  // 3. Platform.resolvedExecutable — points at the `dart` binary under
  //    `dart run`; harmlessly skipped for compiled binaries.
  try {
    final fromExe = _sdkFromDartExecutable(Platform.resolvedExecutable);
    if (fromExe != null) return fromExe;
  } catch (_) {
    // resolvedExecutable can throw in some embedders — ignore.
  }

  // 4. `dart` on PATH.
  final dartOnPath = _firstOnPath('dart');
  if (dartOnPath != null) {
    final sdk = _sdkFromDartExecutable(dartOnPath);
    if (sdk != null) return sdk;
  }

  // 5. `flutter` on PATH → <flutter>/bin/cache/dart-sdk.
  final flutterOnPath = _firstOnPath('flutter');
  if (flutterOnPath != null) {
    var flutterPath = flutterOnPath;
    try {
      flutterPath = File(flutterPath).resolveSymbolicLinksSync();
    } catch (_) {
      // Keep the unresolved path.
    }
    // flutter lives at <flutter>/bin/flutter → root is the grandparent.
    final dartSdk = p.join(p.dirname(p.dirname(flutterPath)), 'bin', 'cache',
        'dart-sdk');
    if (looksLikeDartSdk(dartSdk)) return dartSdk;
  }

  // Let the analyzer use its default (may fail for compiled binaries).
  return null;
}

/// Returns the first match for [command] on `PATH`, or `null`.
String? _firstOnPath(String command) {
  try {
    final locator = Platform.isWindows ? 'where' : 'which';
    final result = Process.runSync(locator, [command]);
    if (result.exitCode != 0) return null;
    final firstLine = (result.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return firstLine.isEmpty ? null : firstLine;
  } catch (_) {
    return null;
  }
}

/// Derives the Dart SDK root from a path to a `dart` executable.
///
/// Handles the standalone SDK (`<sdk>/bin/dart`, SDK is the grandparent) and
/// the Flutter wrapper (`<flutter>/bin/dart`, real SDK at
/// `<flutter>/bin/cache/dart-sdk`). Symlinks (Homebrew, fvm, …) are resolved
/// first. Returns `null` when no SDK-shaped directory is found.
String? _sdkFromDartExecutable(String dartPath) {
  var resolved = dartPath;
  try {
    resolved = File(dartPath).resolveSymbolicLinksSync();
  } catch (_) {
    // Keep the unresolved path.
  }

  final binDir = p.dirname(resolved);

  // Standalone SDK: <sdk>/bin/dart.
  final standaloneSdk = p.dirname(binDir);
  if (looksLikeDartSdk(standaloneSdk)) return standaloneSdk;

  // Flutter wrapper: <flutter>/bin/dart → <flutter>/bin/cache/dart-sdk.
  final flutterSdk = p.join(binDir, 'cache', 'dart-sdk');
  if (looksLikeDartSdk(flutterSdk)) return flutterSdk;

  return null;
}

/// Whether [dir] looks like a Dart SDK root.
///
/// Checks for `lib/_internal/allowed_experiments.json`, the file the analyzer's
/// `FolderBasedDartSdk` reads when initializing the library map — the exact
/// file whose absence triggers the compiled-binary failure.
bool looksLikeDartSdk(String? dir) {
  if (dir == null || dir.isEmpty) return false;
  return File(p.join(dir, 'lib', '_internal', 'allowed_experiments.json'))
      .existsSync();
}

/// Test-only: clears the process-lifetime cache and optionally disables it.
///
/// Not part of the public contract; exposed for unit tests that need to
/// exercise [resolveDartSdkPath] deterministically.
void debugResetDartSdkLocatorCache({bool enableCache = true}) {
  _cachedSdkPath = null;
  _cacheEnabled = enableCache;
}
