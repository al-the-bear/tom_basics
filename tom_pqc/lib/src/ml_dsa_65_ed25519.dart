// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'ml_dsa_65.dart';
import 'pqc_backend.dart';
import 'secret_bytes.dart';

/// A composite ML-DSA-65 + Ed25519 key pair.
final class MlDsa65Ed25519KeyPair {
  MlDsa65Ed25519KeyPair(this.publicKey, this.secretKey);

  /// [MlDsa65Ed25519.publicKeyLength] bytes: the ML-DSA-65 public key, then
  /// the Ed25519 public key.
  final Uint8List publicKey;

  /// [MlDsa65Ed25519.secretKeyLength] bytes in native memory: the ML-DSA-65
  /// seed, then the Ed25519 seed.
  final SecretBytes secretKey;

  /// Disposes the secret key.
  void dispose() => secretKey.dispose();
}

/// The composite signature ML-DSA-65 with Ed25519 of RFC 10073
/// (`id-MLDSA65-Ed25519-SHA512`, OID 1.3.6.1.5.5.7.6.48): one signature that
/// is valid only when both its ML-DSA-65 and its Ed25519 half verify, over
/// the same domain-separated message
///
///     M' = Prefix || Label || len(ctx) || ctx || SHA-512(M)
///
/// with ML-DSA signing M' under the context Label. Keys, signatures and the
/// application context follow the RFC byte for byte, so other
/// implementations of it interoperate.
///
/// The Ed25519 half runs in `package:cryptography`, whose API is
/// asynchronous; so are these functions.
abstract final class MlDsa65Ed25519 {
  /// Composite public-key length (1,984 bytes).
  static const publicKeyLength = MlDsa65Sizes.publicKey + 32;

  /// Composite secret-key length (64 bytes: two seeds).
  static const secretKeyLength = MlDsa65Sizes.seed + 32;

  /// Composite signature length (3,373 bytes).
  static const signatureLength = MlDsa65Sizes.signature + 64;

  /// The longest application context (255 bytes).
  static const maxContextLength = 255;

  /// The RFC's Prefix, ASCII `CompositeAlgorithmSignatures2025`.
  static final Uint8List prefix = Uint8List.fromList(
    ascii.encode('CompositeAlgorithmSignatures2025'),
  );

  /// The RFC's Label for this composite, also ML-DSA's context.
  static final Uint8List label = Uint8List.fromList(
    ascii.encode('COMPSIG-MLDSA65-Ed25519-SHA512'),
  );

  static final _ed25519 = Ed25519();

  /// A fresh key pair (both component keys freshly generated, as the RFC
  /// requires).
  static Future<MlDsa65Ed25519KeyPair> generateKeyPair() {
    final bytes = pqcBackend.randomBytes(secretKeyLength);
    final secret = SecretBytes.fromBytes(bytes);
    bytes.fillRange(0, bytes.length, 0);
    return keyPairFromSecretKey(secret);
  }

  /// The key pair of the 64-byte composite [secretKey], which it keeps.
  static Future<MlDsa65Ed25519KeyPair> keyPairFromSecretKey(
    SecretBytes secretKey,
  ) async => MlDsa65Ed25519KeyPair(await publicKey(secretKey), secretKey);

  /// The composite public key of [secretKey].
  static Future<Uint8List> publicKey(SecretBytes secretKey) async {
    _sized(secretKey.length, secretKeyLength, 'secret key');
    final mlDsa = _mlDsaPair(secretKey);
    try {
      final ed = await _edPair(secretKey);
      final edPublic = (await ed.extractPublicKey()).bytes;
      ed.destroy();
      return Uint8List.fromList([...mlDsa.publicKey, ...edPublic]);
    } finally {
      mlDsa.dispose();
    }
  }

  /// The composite signature of [message] with the application [context]
  /// (default empty, at most 255 bytes).
  static Future<Uint8List> sign(
    Uint8List message,
    SecretBytes secretKey, {
    Uint8List? context,
  }) async {
    _sized(secretKey.length, secretKeyLength, 'secret key');
    final mPrime = representative(message, context: context);
    final mlDsa = _mlDsaPair(secretKey);
    try {
      final mlDsaSig = MlDsa65.sign(mPrime, mlDsa.secretKey, context: label);
      final ed = await _edPair(secretKey);
      final edSig = await _ed25519.sign(mPrime, keyPair: ed);
      ed.destroy();
      return Uint8List.fromList([...mlDsaSig, ...edSig.bytes]);
    } finally {
      mlDsa.dispose();
    }
  }

  /// Whether [signature] is a valid composite signature of [message] under
  /// [publicKey] and [context]: both halves must verify. Malformed input is
  /// an invalid signature, not an error.
  static Future<bool> verify(
    Uint8List message,
    Uint8List signature,
    Uint8List publicKey, {
    Uint8List? context,
  }) async {
    if (signature.length != signatureLength ||
        publicKey.length != publicKeyLength ||
        (context?.length ?? 0) > maxContextLength) {
      return false;
    }
    final mPrime = representative(message, context: context);
    final mlDsaPk = Uint8List.sublistView(publicKey, 0, MlDsa65Sizes.publicKey);
    final edPk = Uint8List.sublistView(publicKey, MlDsa65Sizes.publicKey);
    final mlDsaSig = Uint8List.sublistView(
      signature,
      0,
      MlDsa65Sizes.signature,
    );
    final edSig = Uint8List.sublistView(signature, MlDsa65Sizes.signature);
    if (!MlDsa65.verify(
      mPrime,
      Uint8List.fromList(mlDsaSig),
      Uint8List.fromList(mlDsaPk),
      context: label,
    )) {
      return false;
    }
    return _ed25519.verify(
      mPrime,
      signature: Signature(
        Uint8List.fromList(edSig),
        publicKey: SimplePublicKey(
          Uint8List.fromList(edPk),
          type: KeyPairType.ed25519,
        ),
      ),
    );
  }

  /// The message representative M' the RFC signs.
  static Uint8List representative(Uint8List message, {Uint8List? context}) {
    final ctx = context ?? Uint8List(0);
    if (ctx.length > maxContextLength) {
      throw ArgumentError(
        'a composite context is at most $maxContextLength bytes, '
        'not ${ctx.length}',
      );
    }
    return Uint8List.fromList([
      ...prefix,
      ...label,
      ctx.length,
      ...ctx,
      ...crypto.sha512.convert(message).bytes,
    ]);
  }

  static MlDsa65KeyPair _mlDsaPair(SecretBytes secretKey) =>
      MlDsa65.keyPairFromSeed(secretKey.sublist(0, MlDsa65Sizes.seed));

  static Future<SimpleKeyPair> _edPair(SecretBytes secretKey) async {
    final part = secretKey.sublist(MlDsa65Sizes.seed);
    final seed = part.extractBytes();
    part.dispose();
    try {
      return await _ed25519.newKeyPairFromSeed(seed);
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  }

  static void _sized(int actual, int expected, String what) {
    if (actual != expected) {
      throw ArgumentError(
        'ML-DSA-65+Ed25519 $what must be $expected bytes, not $actual',
      );
    }
  }
}
