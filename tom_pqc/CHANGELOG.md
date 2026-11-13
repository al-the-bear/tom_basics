# Changelog

## 0.1.0

- ML-KEM-768 (FIPS 203): key generation (also from a 64-byte seed),
  encapsulation, decapsulation, and the encapsulation- and decapsulation-key
  checks, through FFI to the vendored C code.
- Vendored C: mlkem-native v2.0.0, commit
  `d1b2fe782888bdb761a50336012923180be7f502`, portable C only (no assembly,
  no architecture back ends).
- A build hook (`hook/build.dart`) compiles the C code for the target:
  macOS, Linux and Windows.
- An internal backend interface between the Dart API and the C code.
- Secret keys and shared secrets in native memory (`SecretBytes`),
  overwritten when disposed or finalized.
- Randomness from the operating system's generator.
- Tested with NIST's ACVP vectors for ML-KEM-768 (keyGen, encapsulation,
  decapsulation, both key checks).
