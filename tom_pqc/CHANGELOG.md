# Changelog

## 0.1.0

The first release.

- **ML-KEM-768** (FIPS 203): key generation (also from a 64-byte seed),
  encapsulation, decapsulation, and the encapsulation- and decapsulation-key
  checks.
- **ML-DSA-65** (FIPS 204): key generation from a 32-byte seed (also from an
  expanded secret key), hedged signing with a context string, verification.
- **SHA3-256 and SHAKE256** (FIPS 202).
- **MLKEM768-X25519** (X-Wing, draft-connolly-cfrg-xwing-kem; the KEM of
  `age` v1.3's `mlkem768x25519` recipients): key generation from a 32-byte
  seed, encapsulation, decapsulation; a low-order X25519 share is refused.
- **ML-DSA-65 + Ed25519** composite signatures (RFC 10073,
  `id-MLDSA65-Ed25519-SHA512`): key generation, signing with an application
  context, verification that needs both halves.
- Vendored C, portable only (no assembly, no architecture back ends):
  mlkem-native v2.0.0, commit `d1b2fe782888bdb761a50336012923180be7f502`,
  and mldsa-native v2.0.0, commit
  `834a90d5e846ffa1e1611bd24e160bb2e9b86d35`.
- A build hook (`hook/build.dart`) compiles the C code for the target:
  macOS, Linux and Windows.
- An internal backend interface between the Dart API and the C code.
- Secret keys and shared secrets in native memory (`SecretBytes`),
  overwritten when disposed or finalized.
- Randomness from the operating system's generator.
- Tested with NIST's ACVP vectors (ML-KEM-768; ML-DSA-65 key generation,
  signing and verification), every ML-KEM-768 and ML-DSA-65 case of
  Wycheproof (commit `65ca494727a52944c204441c860b039e6786b99b`), the X-Wing
  draft's vectors, RFC 10073's vector, the age testkit's hybrid files, and a
  cross-check with Go's `crypto/mlkem`, `crypto/mldsa` and `crypto/hpke`.
