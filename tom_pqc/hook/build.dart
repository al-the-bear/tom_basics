// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// Builds tom_pqc's native library from the vendored C, for the target the
/// Dart or Flutter build asks for: the backend interface (`native/tom_pqc.c`
/// with mlkem-native and `native/tom_pqc_mldsa.c` with mldsa-native, each one
/// compilation unit) and the OS random generator
/// (`native/tom_pqc_random.c`). Portable C only, no assembly; nothing is
/// fetched, and the package ships no binaries.
library;

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    final apple = os == OS.macOS || os == OS.iOS;
    await CBuilder.library(
      name: 'tom_pqc',
      assetName: 'src/native_backend.dart',
      sources: [
        'native/tom_pqc.c',
        'native/tom_pqc_mldsa.c',
        'native/tom_pqc_random.c',
      ],
      includes: ['native'],
      std: 'c99',
      // The randomness: BCryptGenRandom on Windows (bcrypt.lib),
      // SecRandomCopyBytes on Apple platforms (the Security framework, linked
      // through `flags`: CBuilder passes `frameworks` to Objective-C builds
      // only); getrandom(2) needs nothing on Linux.
      libraries: os == OS.windows ? const ['bcrypt'] : const [],
      flags: [
        // Only the backend interface (TOM_PQC_EXPORT) is exported; MSVC
        // exports nothing it is not told to, so it needs no flag.
        if (os != OS.windows) '-fvisibility=hidden',
        if (apple) ...['-framework', 'Security'],
      ],
    ).run(
      input: input,
      output: output,
      logger: Logger.detached('tom_pqc')
        ..level = Level.INFO
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}
