// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:typed_data';

import 'pqc_backend.dart';
import 'secret_bytes.dart';

export 'pqc_backend.dart' show MlKem768Encapsulation;

/// An ML-KEM-768 key pair: the encapsulation (public) key and the
/// decapsulation (secret) key, the latter in native memory.
final class MlKem768KeyPair {
  MlKem768KeyPair(this.publicKey, this.secretKey);

  /// [MlKem768.publicKeyLength] bytes.
  final Uint8List publicKey;

  /// [MlKem768.secretKeyLength] bytes in native memory; dispose when done.
  final SecretBytes secretKey;

  /// Disposes the secret key.
  void dispose() => secretKey.dispose();
}

/// ML-KEM-768, the module-lattice key-encapsulation mechanism of FIPS 203 at
/// security category 3.
///
/// ```dart
/// final pair = MlKem768.generateKeyPair();
/// final sent = MlKem768.encapsulate(pair.publicKey);
/// final received = MlKem768.decapsulate(sent.ciphertext, pair.secretKey);
/// // sent.sharedSecret and received hold the same 32 bytes.
/// ```
///
/// Secret keys and shared secrets are [SecretBytes]: native memory that is
/// overwritten when disposed. Decapsulating a ciphertext that was not made for
/// the key does not fail: FIPS 203's implicit rejection returns a secret no
/// sender knows, so the failure shows when the secrets are used.
abstract final class MlKem768 {
  /// Encapsulation-key length (1,184 bytes).
  static const publicKeyLength = MlKem768Sizes.publicKey;

  /// Decapsulation-key length (2,400 bytes).
  static const secretKeyLength = MlKem768Sizes.secretKey;

  /// Ciphertext length (1,088 bytes).
  static const ciphertextLength = MlKem768Sizes.ciphertext;

  /// Shared-secret length (32 bytes).
  static const sharedSecretLength = MlKem768Sizes.sharedSecret;

  /// Seed length (64 bytes, d || z), the form `age` stores a key in.
  static const seedLength = MlKem768Sizes.seed;

  /// A fresh key pair from the operating system's generator.
  static MlKem768KeyPair generateKeyPair() {
    final (pk, sk) = pqcBackend.mlKem768GenerateKeyPair();
    return MlKem768KeyPair(pk, sk);
  }

  /// The key pair a 64-byte [seed] (d || z) determines (FIPS 203,
  /// ML-KEM.KeyGen_internal). The same seed always gives the same pair, so the
  /// seed is the secret key's compact form.
  static MlKem768KeyPair keyPairFromSeed(SecretBytes seed) {
    final (pk, sk) = pqcBackend.mlKem768KeyPairFromSeed(seed);
    return MlKem768KeyPair(pk, sk);
  }

  /// A fresh 64-byte seed from the operating system's generator, for
  /// [keyPairFromSeed].
  static SecretBytes generateSeed() {
    final bytes = pqcBackend.randomBytes(seedLength);
    try {
      return SecretBytes.fromBytes(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// A ciphertext and the shared secret it carries, for the holder of the
  /// secret key of [publicKey]. Throws [TomPqcException] when [publicKey]
  /// fails FIPS 203's modulus check.
  static MlKem768Encapsulation encapsulate(Uint8List publicKey) =>
      pqcBackend.mlKem768Encapsulate(publicKey);

  /// The shared secret [ciphertext] carries for [secretKey]. Throws
  /// [TomPqcException] when [secretKey] fails FIPS 203's hash check.
  static SecretBytes decapsulate(Uint8List ciphertext, SecretBytes secretKey) =>
      pqcBackend.mlKem768Decapsulate(ciphertext, secretKey);

  /// Whether [publicKey] passes FIPS 203's encapsulation-key check (length
  /// and modulus check, Section 7.2).
  static bool isValidPublicKey(Uint8List publicKey) =>
      pqcBackend.mlKem768CheckPublicKey(publicKey);

  /// Whether [secretKey] passes FIPS 203's decapsulation-key check (length
  /// and hash check, Section 7.3).
  static bool isValidSecretKey(SecretBytes secretKey) =>
      pqcBackend.mlKem768CheckSecretKey(secretKey);
}
