# Third-party software in tom_pqc

`tom_pqc` is licensed under the BSD 3-Clause License ([`LICENSE`](LICENSE)).
That covers its own code: the Dart library, the build hook and the C files
directly under `native/` (`tom_pqc.c`, `tom_pqc.h`, `tom_pqc_random.c`,
`tom_pqc_random.h`, `tom_pqc_mlkem_config.h`).

## Vendored C code

| Directory | Upstream | Version and commit | Licence |
| --- | --- | --- | --- |
| `native/mlkem-native/` | [pq-code-package/mlkem-native](https://github.com/pq-code-package/mlkem-native), its `mlkem/` directory | v2.0.0, `d1b2fe782888bdb761a50336012923180be7f502` | Apache-2.0 OR ISC OR MIT, taken under **MIT**; the upstream `LICENSE` is kept as `native/mlkem-native/LICENSE` |

mlkem-native is the PQ Code Package's ML-KEM implementation (FIPS 203), a
maintained fork of the public-domain Kyber reference code; its copyright
holders are named at the top of each file. Only the portable C is vendored:
the `src/native/` and `src/fips202/native/` back ends, `mlkem_native_asm.S`
and the directory's `README.md` (documentation, CC-BY-4.0, linking into
upstream folders that are not vendored) are left out, and no file is changed. The vendored `mlkem_native_config.h` is
not used; `native/tom_pqc_mlkem_config.h` configures the build instead.

To update: replace `native/mlkem-native/` with the `mlkem/` directory of the
new upstream commit (the same files left out), copy its `LICENSE`, and change
the commit here, in `native/tom_pqc.c` (`TOM_PQC_BACKEND_NAME`) and in the
CHANGELOG. `test/licence_test.dart` holds the three together, and the
known-answer tests decide whether the new code may be used.

## Dart dependencies

The packages `tom_pqc` depends on (`code_assets`, `hooks`,
`native_toolchain_c`, `logging`, `ffi`, `meta` and theirs) are BSD-3-Clause;
`test/licence_test.dart` checks that every package in the closure carries a
permissive licence. They are not bundled: pub fetches them.

## Test vectors

`test/vectors/acvp_ml_kem_768.json` holds the ML-KEM-768 groups of NIST's
ACVP vectors ([usnistgov/ACVP-Server](https://github.com/usnistgov/ACVP-Server),
commit `975de31eb83d87039ec88934fdc47d8c312b892d`), a work of the US
government, extracted by `tool/extract_acvp_vectors.py`.

`test/vectors/wycheproof/` holds Wycheproof's four ML-KEM-768 files
(`mlkem_768_keygen_seed_test.json`, `mlkem_768_encaps_test.json`,
`mlkem_768_test.json`, `mlkem_768_semi_expanded_decaps_test.json`) from
[C2SP/wycheproof](https://github.com/C2SP/wycheproof) `testvectors_v1/`,
commit `65ca494727a52944c204441c860b039e6786b99b`, unchanged, under
**Apache-2.0** with Wycheproof's `LICENSE` beside them. `SOURCE.json` records
the commit and each file's SHA-256; `tool/extract_wycheproof_vectors.py`
copies them.
