// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// Post-quantum cryptography for Dart: ML-KEM-768 (FIPS 203), ML-DSA-65
/// (FIPS 204), and the hybrids built on them — the KEM MLKEM768-X25519
/// (X-Wing, `age`'s hybrid recipients) and the composite signature
/// ML-DSA-65 + Ed25519 of RFC 10073.
///
/// The post-quantum algorithms run in vendored, portable C (mlkem-native,
/// mldsa-native), compiled for the target by the package's build hook and
/// reached through FFI behind an internal backend interface; the classical
/// halves of the hybrids come from `package:cryptography`. Secret keys and
/// shared secrets stay in native memory ([SecretBytes]) and are overwritten
/// when disposed.
library;

export 'src/ml_dsa_65.dart';
export 'src/ml_dsa_65_ed25519.dart';
export 'src/ml_kem_768.dart';
export 'src/ml_kem_768_x25519.dart';
export 'src/pqc_exception.dart';
export 'src/secret_bytes.dart';
export 'src/sha3.dart';
