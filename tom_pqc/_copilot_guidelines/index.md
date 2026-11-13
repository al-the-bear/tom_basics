# Tom PQC — development guidelines

How `tom_pqc` is built, tested and kept current. User documentation is the
package README.

## Layout

| Path | What it is |
| --- | --- |
| `native/mlkem-native/`, `native/mldsa-native/` | the vendored C, unchanged upstream files (see `THIRD_PARTY.md`) |
| `native/tom_pqc.h` | the backend interface: the only exported C symbols |
| `native/tom_pqc.c` | the mlkem-native backend (ML-KEM-768, SHA3-256, SHAKE256): includes `mlkem_native.c` as one compilation unit and maps its errors |
| `native/tom_pqc_mldsa.c` | the mldsa-native backend (ML-DSA-65): `mldsa_native.c` as a compilation unit of its own, so the two libraries' internal names never meet |
| `native/tom_pqc_mlkem_config.h`, `native/tom_pqc_mldsa_config.h` | the libraries' configurations: one parameter set each, every symbol `static`, randomness from `tom_pqc_randombytes` |
| `native/tom_pqc_random.c` | the OS random generator |
| `hook/build.dart` | compiles the three `.c` files per target with `native_toolchain_c` |
| `lib/src/native_backend.dart` | the `@Native` bindings |
| `lib/src/pqc_backend.dart` | `PqcBackend` (the Dart side of the interface) and `NativePqcBackend`; not exported |
| `lib/src/ml_kem_768_x25519.dart`, `lib/src/ml_dsa_65_ed25519.dart` | the hybrids, built on the Dart API (`MlKem768`, `MlDsa65`, `Sha3`) and `package:cryptography` (X25519, Ed25519), never on the C code directly |
| `test/vectors/` | ACVP (`tool/extract_acvp_vectors.py`), Wycheproof (`tool/extract_wycheproof_vectors.py`), the X-Wing draft, RFC 10073 and the age testkit (`tool/extract_hybrid_vectors.py`), each with its source and commit; the Go cross-check (`tool/go_crosscheck`) |
| `test/support/age_reader.dart` | a minimal age reader (header, stanzas, HPKE open, MAC, STREAM, armor) for the age testkit; test-only |

## Rules

- **The vendored files are never edited.** Configuration goes into
  `tom_pqc_mlkem_config.h` / `tom_pqc_mldsa_config.h`, glue into
  `tom_pqc.c` / `tom_pqc_mldsa.c`. A fix upstream reaches the package as a
  new pinned commit.
- **The hybrids follow their specifications byte for byte.** X-Wing is
  `MLKEM768-X25519` of draft-ietf-hpke-pq (what age uses), with the all-zero
  X25519 secret refused as filippo.io/hpke-pq does; the composite signature
  is RFC 10073 `id-MLDSA65-Ed25519-SHA512`. Their formats are fixed in phase
  A of the Tom Secrets Manager (keys, grants), so a change to either is a
  migration.
- **Only the backend interface is exported.** A new C entry point is declared
  in `tom_pqc.h` with `TOM_PQC_EXPORT`, bound in `native_backend.dart`, and
  reached from the public API through `PqcBackend` only.
- **Every output is zeroed on failure, every secret lives in `SecretBytes`.**
  A secret that has to touch the Dart heap (a seed from `randomBytes`) is
  overwritten right after it is copied into native memory.
- **The known-answer tests decide.** A change to the C code, a new upstream
  commit or another backend is accepted only when every ACVP vector passes on
  macOS, Linux and Windows.

## Updating mlkem-native or mldsa-native

1. Clone `https://github.com/pq-code-package/mlkem-native` (or
   `mldsa-native`) into the workspace `ztmp/` and check out the new release.
2. Replace `native/mlkem-native/` with its `mlkem/` directory (or
   `native/mldsa-native/` with its `mldsa/` directory), leaving out
   `src/native/`, `src/fips202/native/`, the `*_asm.S` file and `README.md`;
   copy the repository's `LICENSE` into it.
3. Change the commit in `THIRD_PARTY.md`, in the backend's name
   (`TOM_PQC_BACKEND_NAME` in `native/tom_pqc.c`, the name in
   `native/tom_pqc_mldsa.c`) and in the CHANGELOG (`test/licence_test.dart`
   holds them together).
4. `dart analyze`, `testkit :test`, and the same tests on a Linux and a
   Windows host.

## Refreshing the vectors

- **ACVP:** clone `https://github.com/usnistgov/ACVP-Server` into `ztmp/`,
  check out the commit wanted, run `tool/extract_acvp_vectors.py <clone>`, and
  update the commit in `THIRD_PARTY.md`.
- **Wycheproof:** clone `https://github.com/C2SP/wycheproof` into `ztmp/`,
  check out the commit wanted, run `tool/extract_wycheproof_vectors.py
  <clone>` (it rewrites `SOURCE.json` with the commit and the SHA-256s), and
  update the commit in `THIRD_PARTY.md` and the CHANGELOG. The case counts in
  `test/wycheproof_ml_kem_768_test.dart` and
  `test/wycheproof_ml_dsa_65_test.dart` change with the files.
- **X-Wing, RFC 10073, age:** clone the three repositories named in
  `THIRD_PARTY.md` into `ztmp/` and run `tool/extract_hybrid_vectors.py
  --xwing <clone> --composite <clone> --cctv <clone>`; update the commits in
  `THIRD_PARTY.md`.
- **Go cross-check:** with Go 1.27 or later (an official release unpacked
  into `ztmp/` will do; nothing is installed), `cd tool/go_crosscheck && go
  run . ../../test/vectors/go_crosscheck.json`. The inputs are derived from a
  counter, so a rerun with the same Go writes the same file.

## Testing on the other desktop platforms

The hook compiles on the host it runs on, so each platform is tested there.
Run by a person: copy the package with `tom_test_support` and `tom_github_api`
(its dev dependencies) into the host's workspace `ztmp/`, then
`dart pub get && dart test` (on legiondary01 MSVC is found through vswhere),
and remove the copy afterwards.

## Bundling: what each build carries (spike, 2026-11-13)

The design asks whether the service's executable, `tsm` and the Flutter
desktop app bundle the hook's library on every fleet platform, with a
library built by hand as the fallback where one does not. Measured with two
throwaway consumers, each a separate package with a path dependency on
`tom_pqc` that runs one ML-KEM-768 round trip and prints `PQC_SPIKE OK`: a
CLI built with `dart build cli` (as `tsm` and the service will be) and a
Flutter desktop app (`flutter create`, `flutter build <os> --release`).

| Platform (host) | `dart test` (all suites) | `dart build cli` | Flutter desktop release |
| --- | --- | --- | --- |
| macOS arm64 (mbp) | 1,330 passed, 45 skipped (HashML-DSA) | `bundle/lib/libtom_pqc.dylib`; runs, also after the bundle is moved | `Contents/Frameworks/tom_pqc.framework`; the app runs |
| Linux x64 (bigbeast) | 1,330 passed, 45 skipped (HashML-DSA) | `bundle/lib/libtom_pqc.so`; runs | `bundle/lib/libtom_pqc.so`, mapped in `data/flutter_assets/NativeAssetsManifest.json`; not launched: bigbeast has no display |
| Windows x64 (legiondary01, MSVC) | 1,330 passed, 45 skipped (HashML-DSA) | `bundle\lib\tom_pqc.dll`; runs | `tom_pqc.dll` beside the exe, mapped in the manifest; the app runs (started over SSH) |
| macOS x64 | — | not buildable: `dart build cli` on macOS arm64 targets only Linux | — |
| Linux arm64 | — | no cross C compiler on mbp or bigbeast | — |

**Result: every fleet platform's build bundles the library, so no hand-built
fallback is needed.** The library goes into each build's own place (`lib/`
of a CLI bundle, the app's `Frameworks/` on macOS, beside the executable on
Windows), and the native-assets manifest names it.

What the table does not cover, and where it is caught up:

- **The Linux desktop app has not been launched.** The bundle and manifest
  are right; the first launch on a Linux machine with a display is the
  desktop app's (tsm_a23) or the fleet rollout's (tsm_a28).
- **macOS x64 and Linux arm64 are not fleet platforms** (mbp is arm64,
  bomber and bigbeast x64, legiondary01 x64). The C code compiles and links
  for macOS x86_64 (`clang -arch x86_64`, the 11 exported symbols), and an
  x86_64 C harness run under Rosetta passed the first ACVP key-generation
  vector and a round trip; the Dart side there is untested. Linux arm64 needs
  an `aarch64-linux-gnu` toolchain or an arm64 host.

To repeat the spike, run by a person: create the two consumers in the
workspace `ztmp/` (a `bin/` script, and a `flutter create --platforms
macos,linux,windows` app whose `main()` calls the round trip and exits),
`dart build cli` and `flutter build <os> --release` (Flutter under the
workspace flutter lock), run them, and remove the folder afterwards. On a
host without the package checked out, copy `tom_pqc` next to them and point
the path dependency at the copy.
