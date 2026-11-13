# Third-party software in tom_pqc

`tom_pqc` is licensed under the BSD 3-Clause License ([`LICENSE`](LICENSE)).
That covers its own code: the Dart library, the build hook, the tools and the
C files directly under `native/` (`tom_pqc.c`, `tom_pqc.h`, `tom_pqc_mldsa.c`,
`tom_pqc_mldsa_config.h`, `tom_pqc_mlkem_config.h`, `tom_pqc_random.c`,
`tom_pqc_random.h`).

## Vendored C code

| Directory | Upstream | Version and commit | Licence |
| --- | --- | --- | --- |
| `native/mlkem-native/` | [pq-code-package/mlkem-native](https://github.com/pq-code-package/mlkem-native), its `mlkem/` directory | v2.0.0, `d1b2fe782888bdb761a50336012923180be7f502` | Apache-2.0 OR ISC OR MIT, taken under **MIT**; the upstream `LICENSE` is kept as `native/mlkem-native/LICENSE` |
| `native/mldsa-native/` | [pq-code-package/mldsa-native](https://github.com/pq-code-package/mldsa-native), its `mldsa/` directory | v2.0.0, `834a90d5e846ffa1e1611bd24e160bb2e9b86d35` | Apache-2.0 OR ISC OR MIT, taken under **MIT**; the upstream `LICENSE` is kept as `native/mldsa-native/LICENSE` |

mlkem-native (ML-KEM, FIPS 203) and mldsa-native (ML-DSA, FIPS 204) are the
PQ Code Package's maintained forks of the public-domain Kyber and Dilithium
reference code; their copyright holders are named at the top of each file.
Only the portable C is vendored: each library's `src/native/` and
`src/fips202/native/` back ends, its assembly file (`mlkem_native_asm.S`,
`mldsa_native_asm.S`) and its directory `README.md` (documentation,
CC-BY-4.0, linking into upstream folders that are not vendored) are left out,
and no file is changed. The vendored `mlkem_native_config.h` and
`mldsa_native_config.h` are not used; `native/tom_pqc_mlkem_config.h` and
`native/tom_pqc_mldsa_config.h` configure the builds instead.

To update one: replace its directory with the upstream directory of the new
commit (the same files left out), copy its `LICENSE`, and change the commit
here, in its backend (`TOM_PQC_BACKEND_NAME` in `native/tom_pqc.c`, the name
in `native/tom_pqc_mldsa.c`) and in the CHANGELOG. `test/licence_test.dart`
holds the three together, and the known-answer tests decide whether the new
code may be used.

## Dart dependencies

The packages `tom_pqc` depends on are fetched by pub, not bundled:

- `cryptography` (Apache-2.0): X25519 and Ed25519, the classical halves of
  the hybrids;
- `crypto` (BSD-3-Clause): SHA-512, the composite signature's pre-hash;
- `code_assets`, `hooks`, `native_toolchain_c`, `logging`, `ffi`, `meta`
  (BSD-3-Clause): the build hook and the FFI calls.

`test/licence_test.dart` checks that every package in the closure carries a
permissive licence.

## Test vectors

Each set is kept as its source wrote it, with its origin and commit; where a
folder has a `SOURCE.json`, it also records each file's SHA-256, which the
tests check.

| Path | Source | Commit | Licence |
| --- | --- | --- | --- |
| `test/vectors/acvp_ml_kem_768.json`, `test/vectors/acvp_ml_dsa_65.json` | NIST [ACVP-Server](https://github.com/usnistgov/ACVP-Server), the ML-KEM-768 and ML-DSA-65 groups of the internal projections, extracted by `tool/extract_acvp_vectors.py` | `975de31eb83d87039ec88934fdc47d8c312b892d` | a work of the US government |
| `test/vectors/wycheproof/` | [C2SP/wycheproof](https://github.com/C2SP/wycheproof) `testvectors_v1/`: the four ML-KEM-768 and three ML-DSA-65 files, unchanged, with Wycheproof's `LICENSE` beside them; copied by `tool/extract_wycheproof_vectors.py` | `65ca494727a52944c204441c860b039e6786b99b` | **Apache-2.0** |
| `test/vectors/xwing/` | [draft-connolly-cfrg-xwing-kem](https://github.com/dconnolly/draft-connolly-cfrg-xwing-kem) `spec/test-vectors.json`, unchanged; copied by `tool/extract_hybrid_vectors.py` | `984c2f7a93b8f8d8f8073ebb53f9f4ce50b5babd` | IETF Trust; code components of Internet-Drafts under the BSD license of the TLP |
| `test/vectors/rfc10073/` | RFC 10073's test vectors ([lamps-wg/draft-composite-sigs](https://github.com/lamps-wg/draft-composite-sigs) `src/testvectors.json`), the `id-MLDSA65-Ed25519-SHA512` entry; extracted by `tool/extract_hybrid_vectors.py` | `b9e2674c0072df66ea09abeabc1c1be5ef9baf29` | IETF Trust; code components of RFCs under the Revised BSD License of the TLP |
| `test/vectors/age/` | the age testkit ([C2SP/CCTV](https://github.com/C2SP/CCTV) `age/testdata/`), every hybrid file, unchanged; copied by `tool/extract_hybrid_vectors.py` | `b88c4b206254ac543df240097e0f1fcc6a664821` | 0BSD OR CC0-1.0 OR Unlicense |
| `test/vectors/go_crosscheck.json` | written by `tool/go_crosscheck` with Go's standard library (its Go version is in the file) | — | tom_pqc's own (BSD-3-Clause) |
