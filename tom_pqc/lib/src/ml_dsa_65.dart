// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:typed_data';

import 'pqc_backend.dart';
import 'secret_bytes.dart';

/// An ML-DSA-65 key pair: the public key, the expanded secret key, and the
/// 32-byte seed it was generated from when it is known.
final class MlDsa65KeyPair {
  MlDsa65KeyPair(this.publicKey, this.secretKey, {this.seed});

  /// [MlDsa65.publicKeyLength] bytes.
  final Uint8List publicKey;

  /// The expanded secret key, [MlDsa65.secretKeyLength] bytes in native
  /// memory.
  final SecretBytes secretKey;

  /// The 32-byte seed (FIPS 204's xi), the interoperable form of the secret
  /// key; null for a pair made from an expanded secret key.
  final SecretBytes? seed;

  /// Disposes the secret key and the seed.
  void dispose() {
    secretKey.dispose();
    seed?.dispose();
  }
}

/// ML-DSA-65, the module-lattice signature scheme of FIPS 204 at security
/// category 3.
///
/// ```dart
/// final pair = MlDsa65.generateKeyPair();
/// final signature = MlDsa65.sign(message, pair.secretKey);
/// final ok = MlDsa65.verify(message, signature, pair.publicKey);
/// ```
///
/// Signing is hedged (FIPS 204's default): fresh randomness from the
/// operating system is mixed in, so two signatures of one message differ. A
/// context string of at most 255 bytes separates uses of one key. HashML-DSA
/// is not offered.
abstract final class MlDsa65 {
  /// Public-key length (1,952 bytes).
  static const publicKeyLength = MlDsa65Sizes.publicKey;

  /// Expanded secret-key length (4,032 bytes).
  static const secretKeyLength = MlDsa65Sizes.secretKey;

  /// Signature length (3,309 bytes).
  static const signatureLength = MlDsa65Sizes.signature;

  /// Seed length (32 bytes).
  static const seedLength = MlDsa65Sizes.seed;

  /// The longest context string (255 bytes).
  static const maxContextLength = MlDsa65Sizes.maxContext;

  /// A fresh key pair, with its seed, from the operating system's generator.
  static MlDsa65KeyPair generateKeyPair() => keyPairFromSeed(generateSeed());

  /// The key pair the 32-byte [seed] determines (FIPS 204,
  /// ML-DSA.KeyGen_internal). The pair keeps [seed]; disposing the pair
  /// disposes it.
  static MlDsa65KeyPair keyPairFromSeed(SecretBytes seed) {
    final (pk, sk) = pqcBackend.mlDsa65KeyPairFromSeed(seed);
    return MlDsa65KeyPair(pk, sk, seed: seed);
  }

  /// A key pair from an expanded [secretKey], which it keeps; throws
  /// [TomPqcException] for a malformed key.
  static MlDsa65KeyPair keyPairFromSecretKey(SecretBytes secretKey) =>
      MlDsa65KeyPair(pqcBackend.mlDsa65PublicKey(secretKey), secretKey);

  /// A fresh 32-byte seed from the operating system's generator.
  static SecretBytes generateSeed() {
    final bytes = pqcBackend.randomBytes(seedLength);
    try {
      return SecretBytes.fromBytes(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// A hedged signature of [message] with [context] (default empty).
  static Uint8List sign(
    Uint8List message,
    SecretBytes secretKey, {
    Uint8List? context,
  }) => pqcBackend.mlDsa65Sign(message, secretKey, context: context);

  /// Whether [signature] is a valid signature of [message] under [publicKey]
  /// and [context]. Malformed input is an invalid signature, not an error.
  static bool verify(
    Uint8List message,
    Uint8List signature,
    Uint8List publicKey, {
    Uint8List? context,
  }) =>
      pqcBackend.mlDsa65Verify(message, signature, publicKey, context: context);
}
