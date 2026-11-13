// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:typed_data';

import 'pqc_backend.dart';
import 'secret_bytes.dart';

/// SHA3-256 and SHAKE256 (FIPS 202) from the vendored C code, the hashes the
/// hybrid combiners use.
abstract final class Sha3 {
  /// SHA3-256 of [input]: 32 bytes.
  static Uint8List sha3256(Uint8List input) => pqcBackend.sha3256(input);

  /// SHA3-256 of the secret [input], kept in native memory.
  static SecretBytes sha3256Secret(SecretBytes input) =>
      pqcBackend.sha3256Secret(input);

  /// The first [length] bytes of SHAKE256 of [input].
  static Uint8List shake256(Uint8List input, int length) =>
      pqcBackend.shake256(input, length);

  /// The first [length] bytes of SHAKE256 of the secret [input], kept in
  /// native memory.
  static SecretBytes shake256Secret(SecretBytes input, int length) =>
      pqcBackend.shake256Secret(input, length);
}
