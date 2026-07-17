// Copyright (c) 2024-2026. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

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
/// per-analyzer-major, per-Dart-SDK subdirectory
/// (`.tom/analyzer-cache/<major>/<dart-sdk-version>/`). Bundles written under
/// analyzer 10 live under `.../10/` and are never read by an analyzer-8 tool
/// (which looks under `.../8/`), so the two formats can never collide. The
/// nested `<dart-sdk-version>` segment adds the same guarantee *within* a
/// major, since the bundle format also drifts across point SDK upgrades that
/// keep the analyzer major fixed (see [SummaryCacheManager] for the full
/// rationale).
///
/// The analyzer package does not expose its own marketing version as a runtime
/// constant, and the Tom code generators that use this cache run
/// **AOT-compiled** — where `Isolate.resolvePackageUri` path-sniffing is
/// unavailable. A compile-time constant is therefore the only AOT-safe source
/// of truth. This package pins `analyzer: ^10.0.0` in its pubspec, so each
/// published build maps to exactly one analyzer major.
///
/// ## Maintenance
///
/// **Bump this constant in lockstep with the `analyzer` constraint in
/// `pubspec.yaml`.** When `tom_analyzer_shared` migrates to `analyzer: ^11.x`,
/// set this to `11`. The two must always agree; a mismatch reintroduces the
/// cross-major poison this guard exists to prevent.
const int analyzerMajorVersion = 10;
