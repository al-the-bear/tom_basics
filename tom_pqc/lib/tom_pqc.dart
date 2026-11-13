// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// Post-quantum cryptography for Dart: ML-KEM-768 (FIPS 203).
///
/// The algorithms run in vendored, portable C (mlkem-native), compiled for
/// the target by the package's build hook and reached through FFI behind an
/// internal backend interface. Secret keys and shared secrets stay in native
/// memory ([SecretBytes]) and are overwritten when disposed.
library;

export 'src/ml_kem_768.dart';
export 'src/pqc_exception.dart';
export 'src/secret_bytes.dart';
