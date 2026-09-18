/// Where a tool is running FROM, printed under its version.
///
/// THE DEFECT THIS CLOSES (SCE8). `--version` prints a number and nothing
/// about which copy answered. During SCC70 a stale precompiled binary and the
/// working-tree source printed the same banner, and a whole regeneration batch
/// had to be discarded because nobody could attribute it. SCD3 made the NUMBER
/// trustworthy — a version stamp test in every package that prints a banner —
/// which does not help here: two runs can share a number and differ in origin.
/// The tree after an unpublished fix, a pub-cache copy, and a binary on PATH
/// from a DIFFERENT clone all report the same version, and on this developer's
/// machine `.zshrc` really does put another clone's `tom_binaries` on PATH.
///
/// WHY A PURE FUNCTION rather than a test that spawns both forms: spawning
/// needs a compiled binary in the test environment, which is what CI does not
/// have and what would make this the first test here to need one. The
/// discriminator is two strings the runtime hands over, so it can be decided
/// in memory and pinned exactly.
library;

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('SCE8: the version banner names the copy that answered', () {
    test('BB-ORIGIN-1: an AOT binary reports the executable that is running '
        '[2026-09-18] (PASS)', () {
      expect(
        toolOriginLine(
          resolvedExecutable: '/Users/dev/.tom/bin/darwin_arm64/d4rtgen',
          script: Uri.file('/Users/dev/.tom/bin/darwin_arm64/d4rtgen'),
        ),
        'binary: /Users/dev/.tom/bin/darwin_arm64/d4rtgen',
      );
    });

    test('BB-ORIGIN-2: a JIT run reports the SCRIPT, not the dart that ran it '
        '[2026-09-18] (PASS)', () {
      // The discriminating case. Both forms have a `resolvedExecutable`; only
      // one of them is the tool. Printing it unconditionally would name
      // `/usr/local/bin/dart` for every source run — the same string for every
      // tool in the workspace, which is the opposite of an origin.
      expect(
        toolOriginLine(
          resolvedExecutable:
              '/opt/homebrew/Cellar/dart/3.10.4/libexec/bin/dart',
          script: Uri.file('/work/tom_d4rt_generator/bin/d4rtgen.dart'),
        ),
        'source: /work/tom_d4rt_generator/bin/d4rtgen.dart',
      );
    });

    test('BB-ORIGIN-3: the three source origins that matter are '
        'distinguishable [2026-09-18] (PASS)', () {
      // Not three code paths — one path, and the three inputs a reader needs
      // to tell apart. A pub-cache copy and a working tree differ only in the
      // path, which is exactly why the path is what gets printed.
      const dart = '/usr/lib/dart/bin/dart';
      final tree = toolOriginLine(
        resolvedExecutable: dart,
        script: Uri.file('/work/tom_d4rt_generator/bin/d4rtgen.dart'),
      );
      final cache = toolOriginLine(
        resolvedExecutable: dart,
        script: Uri.file(
          '/home/d/.pub-cache/hosted/pub.dev/tom_d4rt_generator-1.26.2/bin/d4rtgen.dart',
        ),
      );
      final snapshot = toolOriginLine(
        resolvedExecutable: dart,
        script: Uri.file(
          '/work/consumer/.dart_tool/pub/bin/tom_d4rt_generator/d4rtgen.dart-3.10.4.snapshot',
        ),
      );
      expect({tree, cache, snapshot}, hasLength(3));
      expect(cache, contains('.pub-cache'));
      expect(snapshot, contains('.dart_tool/pub/bin'));
    });

    test('BB-ORIGIN-4: a Windows dart is recognised as an interpreter '
        '[2026-09-18] (PASS)', () {
      expect(
        toolOriginLine(
          resolvedExecutable: r'C:\tools\dart-sdk\bin\dart.exe',
          script: Uri.file(r'C:\work\gen\bin\d4rtgen.dart', windows: true),
        ),
        startsWith('source: '),
      );
      // …and a tool whose own name merely CONTAINS "dart" is not.
      expect(
        toolOriginLine(
          resolvedExecutable: '/home/d/.tom/bin/linux_x64/d4rtgen',
          script: Uri.file('/home/d/.tom/bin/linux_x64/d4rtgen'),
        ),
        startsWith('binary: '),
      );
    });
  });
}
