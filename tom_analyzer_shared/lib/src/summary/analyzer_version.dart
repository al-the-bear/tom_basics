// Copyright (c) 2024-2026. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:analyzer/src/dart/analysis/driver.dart' show AnalysisDriver;

/// The major version of the `analyzer` package this build of
/// `tom_analyzer_shared` was compiled against.
///
/// ## Why this exists
///
/// Summary `.sum` bundles are serialized in an analyzer-version-specific binary
/// format (`package:analyzer/src/summary2/`). A bundle written by analyzer N is
/// **not** decodable by analyzer M when the format changed between them — e.g.
/// an analyzer-8 bundle crashes analyzer 10's `bundle_reader` with a
/// `RangeError` in `_readDirectiveUri`. Because cache files are keyed by
/// `package@version` (and *not* by analyzer version), a cache populated under
/// one analyzer major silently poisons a tool that later runs under a different
/// analyzer major.
///
/// To prevent that, [SummaryCacheManager] partitions the cache into a
/// per-analyzer-major, per-toolchain subdirectory
/// (`.tom/analyzer-cache/<major>/<dart-sdk-version>+d<data-version>/`).
/// Bundles written under analyzer 10 live under `.../10/` and are never read
/// by an analyzer-8 tool (which looks under `.../8/`), so the two formats can
/// never collide. The nested toolchain segment adds the same guarantee
/// *within* a major, since the bundle format also drifts across analyzer
/// minors and point SDK upgrades that keep the major fixed — its
/// [analyzerDataVersion] is the exact key (see [SummaryCacheManager] for the
/// full rationale).
///
/// The analyzer package does not expose its own marketing version as a runtime
/// constant, and the Tom code generators that use this cache run
/// **AOT-compiled** — where `Isolate.resolvePackageUri` path-sniffing is
/// unavailable. A compile-time constant is therefore the only AOT-safe source
/// of truth. This package pins `analyzer: ^14.1.0` in its pubspec, so each
/// published build maps to exactly one analyzer major.
///
/// ## Maintenance
///
/// **Bump this constant in lockstep with the `analyzer` constraint in
/// `pubspec.yaml`.** When `tom_analyzer_shared` migrates to the next analyzer
/// major, set this to that major. The two must always agree; a mismatch
/// reintroduces the cross-major poison this guard exists to prevent
/// (`test/summary/analyzer_version_test.dart` holds them together).
const int analyzerMajorVersion = 14;

/// The `<major>.<minor>.<patch>` Dart SDK version of the running toolchain.
///
/// Parsed from [Platform.version] (e.g. `"3.12.2 (stable) (…)"` → `"3.12.2"`),
/// returning `"unknown"` when the string is unparseable. This is the second
/// cache-partition segment (see [SummaryCacheManager]) and the single source of
/// truth for it — [SummaryCacheManager] and the cache garbage collector both
/// derive the current toolchain's partition from this function.
String currentDartSdkVersion() {
  final match = RegExp(r'^(\d+\.\d+\.\d+)').firstMatch(Platform.version);
  return match?.group(1) ?? 'unknown';
}

/// The data version of the `analyzer` this build is linked with
/// (`AnalysisDriver.DATA_VERSION`): the analyzer raises it whenever what it
/// stores — summary bundles among it — changes format.
///
/// It is the exact key of the summary format. The major
/// ([analyzerMajorVersion]) and the Dart SDK version ([currentDartSdkVersion])
/// are not enough: analyzer 14.5.0 (739) and 14.7.0 (752) on one Dart SDK
/// write bundles the other cannot read. Being a constant of the linked
/// analyzer, it is right in an AOT-compiled tool, where the package's own
/// resolution cannot be looked up.
const int analyzerDataVersion = AnalysisDriver.DATA_VERSION;

/// The toolchain a summary was written by, as one path-safe key:
/// `<dart-sdk-version>+d<analyzer-data-version>` (e.g. `3.13.7+d752`). The
/// second segment of the cache partition, and what a stamp beside a summary
/// records. Both parts default to the running toolchain.
String currentToolchainKey({String? dartSdkVersion, int? dataVersion}) =>
    '${dartSdkVersion ?? currentDartSdkVersion()}'
    '+d${dataVersion ?? analyzerDataVersion}';

/// The data version of the analyzer resolved among [packageRoots] (name →
/// package root, as `readPackageRoots` returns them), read from its
/// `AnalysisDriver` source, or null when the packages resolve no analyzer or
/// the constant cannot be found. Tells whether summaries this tool writes can
/// be read by the analyzer another package (an app shipping them) runs on.
int? analyzerDataVersionInPackageRoots(Map<String, String> packageRoots) {
  final root = packageRoots['analyzer'];
  if (root == null) return null;
  final driver = File(
    p.join(root, 'lib', 'src', 'dart', 'analysis', 'driver.dart'),
  );
  if (!driver.existsSync()) return null;
  final match = RegExp(
    r'static const int DATA_VERSION = (\d+);',
  ).firstMatch(driver.readAsStringSync());
  return match == null ? null : int.parse(match.group(1)!);
}
