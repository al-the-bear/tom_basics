# Tom PQC — development guidelines

How `tom_pqc` is built, tested and kept current. User documentation is the
package README.

## Layout

| Path | What it is |
| --- | --- |
| `native/mlkem-native/` | the vendored C, unchanged upstream files (see `THIRD_PARTY.md`) |
| `native/tom_pqc.h` | the backend interface: the only exported C symbols |
| `native/tom_pqc.c` | the mlkem-native backend: includes `mlkem_native.c` as one compilation unit and maps its errors |
| `native/tom_pqc_mlkem_config.h` | the mlkem-native configuration: ML-KEM-768, every symbol `static`, randomness from `tom_pqc_randombytes` |
| `native/tom_pqc_random.c` | the OS random generator |
| `hook/build.dart` | compiles the two `.c` files per target with `native_toolchain_c` |
| `lib/src/native_backend.dart` | the `@Native` bindings |
| `lib/src/pqc_backend.dart` | `PqcBackend` (the Dart side of the interface) and `NativePqcBackend`; not exported |
| `test/vectors/` | NIST ACVP vectors, written by `tool/extract_acvp_vectors.py` |

## Rules

- **The vendored files are never edited.** Configuration goes into
  `tom_pqc_mlkem_config.h`, glue into `tom_pqc.c`. A fix upstream reaches the
  package as a new pinned commit.
- **Only the backend interface is exported.** A new C entry point is declared
  in `tom_pqc.h` with `TOM_PQC_EXPORT`, bound in `native_backend.dart`, and
  reached from the public API through `PqcBackend` only.
- **Every output is zeroed on failure, every secret lives in `SecretBytes`.**
  A secret that has to touch the Dart heap (a seed from `randomBytes`) is
  overwritten right after it is copied into native memory.
- **The known-answer tests decide.** A change to the C code, a new upstream
  commit or another backend is accepted only when every ACVP vector passes on
  macOS, Linux and Windows.

## Updating mlkem-native

1. Clone `https://github.com/pq-code-package/mlkem-native` into the
   workspace `ztmp/` and check out the new release.
2. Replace `native/mlkem-native/` with its `mlkem/` directory, leaving out
   `src/native/`, `src/fips202/native/` and `mlkem_native_asm.S`; copy the
   repository's `LICENSE` into it.
3. Change the commit in `THIRD_PARTY.md`, `TOM_PQC_BACKEND_NAME` in
   `native/tom_pqc.c` and the CHANGELOG (`test/licence_test.dart` holds them
   together).
4. `dart analyze`, `testkit :test`, and the same tests on a Linux and a
   Windows host.

## Refreshing the vectors

Clone `https://github.com/usnistgov/ACVP-Server` into `ztmp/`, check out the
commit wanted, run `tool/extract_acvp_vectors.py <clone>`, and update the
commit in `THIRD_PARTY.md`.

## Testing on the other desktop platforms

The hook compiles on the host it runs on, so each platform is tested there.
Run by a person: copy the package with `tom_test_support` and `tom_github_api`
(its dev dependencies) into the host's workspace `ztmp/`, then
`dart pub get && dart test` (on legiondary01 MSVC is found through vswhere),
and remove the copy afterwards.
