// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

import 'ml_kem_768.dart';
import 'pqc_backend.dart';
import 'pqc_exception.dart';
import 'secret_bytes.dart';

/// An MLKEM768-X25519 key pair: the 1,216-byte encapsulation key and the
/// 32-byte decapsulation key (a seed), the latter in native memory.
final class MlKem768X25519KeyPair {
  MlKem768X25519KeyPair(this.publicKey, this.secretKey);

  /// [MlKem768X25519.publicKeyLength] bytes: the ML-KEM-768 encapsulation
  /// key, then the X25519 public key.
  final Uint8List publicKey;

  /// [MlKem768X25519.secretKeyLength] bytes: the seed both halves are
  /// expanded from.
  final SecretBytes secretKey;

  /// Disposes the secret key.
  void dispose() => secretKey.dispose();
}

/// One MLKEM768-X25519 encapsulation.
final class MlKem768X25519Encapsulation {
  MlKem768X25519Encapsulation(this.ciphertext, this.sharedSecret);

  /// [MlKem768X25519.ciphertextLength] bytes: the ML-KEM-768 ciphertext,
  /// then the ephemeral X25519 public key.
  final Uint8List ciphertext;

  /// The 32-byte shared secret, in native memory.
  final SecretBytes sharedSecret;
}

/// The hybrid KEM MLKEM768-X25519, also called X-Wing
/// (draft-connolly-cfrg-xwing-kem; MLKEM768-X25519 of draft-ietf-hpke-pq),
/// the KEM of `age` v1.3's `mlkem768x25519` recipients.
///
/// The shared secret is SHA3-256 of both shared secrets, the X25519
/// ciphertext and public key, and the label, so it stays secret while either
/// ML-KEM-768 or X25519 holds. The 32-byte secret key is a seed: SHAKE256
/// expands it into the ML-KEM-768 seed and the X25519 private key.
///
/// The X25519 half runs in `package:cryptography`, whose API is
/// asynchronous; so are these functions. Its key bytes pass the Dart heap
/// briefly and are overwritten after use.
abstract final class MlKem768X25519 {
  /// Encapsulation-key length (1,216 bytes).
  static const publicKeyLength = 1216;

  /// Decapsulation-key (seed) length (32 bytes).
  static const secretKeyLength = 32;

  /// Ciphertext length (1,120 bytes).
  static const ciphertextLength = 1120;

  /// Shared-secret length (32 bytes).
  static const sharedSecretLength = 32;

  /// The combiner's label, `\.//^\`.
  static final Uint8List label = Uint8List.fromList(const [
    0x5c,
    0x2e,
    0x2f,
    0x2f,
    0x5e,
    0x5c,
  ]);

  static final _x25519 = X25519();

  /// A fresh key pair from the operating system's generator.
  static Future<MlKem768X25519KeyPair> generateKeyPair() {
    final seed = pqcBackend.randomBytes(secretKeyLength);
    final secret = SecretBytes.fromBytes(seed);
    seed.fillRange(0, seed.length, 0);
    return keyPairFromSeed(secret);
  }

  /// The key pair the 32-byte [seed] determines; the pair keeps [seed] as
  /// its secret key.
  static Future<MlKem768X25519KeyPair> keyPairFromSeed(SecretBytes seed) async {
    final expanded = await _expand(seed);
    try {
      return MlKem768X25519KeyPair(
        Uint8List.fromList([
          ...expanded.mlKemPublicKey,
          ...expanded.x25519Public,
        ]),
        seed,
      );
    } finally {
      expanded.dispose();
    }
  }

  /// The encapsulation key of the 32-byte [secretKey].
  static Future<Uint8List> publicKey(SecretBytes secretKey) async =>
      (await keyPairFromSeed(secretKey)).publicKey;

  /// A ciphertext and the shared secret it carries for the holder of the
  /// secret key of [publicKey]. Throws [TomPqcException] when the ML-KEM
  /// half fails FIPS 203's modulus check or the X25519 half is a low-order
  /// point.
  static Future<MlKem768X25519Encapsulation> encapsulate(Uint8List publicKey) {
    final eseed = pqcBackend.randomBytes(64);
    return encapsulateWithSeed(
      publicKey,
      eseed,
    ).whenComplete(() => eseed.fillRange(0, eseed.length, 0));
  }

  /// [encapsulate] with the 64-byte [eseed] in place of fresh randomness
  /// (the first 32 bytes the ML-KEM coins, the last 32 the ephemeral X25519
  /// key): for known-answer tests only.
  @visibleForTesting
  static Future<MlKem768X25519Encapsulation> encapsulateWithSeed(
    Uint8List publicKey,
    Uint8List eseed,
  ) async {
    if (publicKey.length != publicKeyLength) {
      throw ArgumentError(
        'MLKEM768-X25519 public key must be $publicKeyLength bytes, '
        'not ${publicKey.length}',
      );
    }
    if (eseed.length != 64) {
      throw ArgumentError('eseed must be 64 bytes, not ${eseed.length}');
    }
    final pkM = Uint8List.sublistView(publicKey, 0, MlKem768.publicKeyLength);
    final pkX = Uint8List.sublistView(publicKey, MlKem768.publicKeyLength);
    final mlkem = pqcBackend.mlKem768Encapsulate(
      Uint8List.fromList(pkM),
      coins: Uint8List.sublistView(eseed, 0, 32),
    );
    try {
      final ekX = Uint8List.fromList(Uint8List.sublistView(eseed, 32));
      final ephemeral = await _x25519.newKeyPairFromSeed(ekX);
      final ctX = Uint8List.fromList(
        (await ephemeral.extractPublicKey()).bytes,
      );
      final ssX = await _sharedSecret(ephemeral, pkX);
      ekX.fillRange(0, ekX.length, 0);
      final shared = _combine(mlkem.sharedSecret, ssX, ctX, pkX);
      return MlKem768X25519Encapsulation(
        Uint8List.fromList([...mlkem.ciphertext, ...ctX]),
        shared,
      );
    } finally {
      mlkem.sharedSecret.dispose();
    }
  }

  /// The shared secret [ciphertext] carries for [secretKey]. A ciphertext
  /// not made for the key yields an unrelated secret (ML-KEM's implicit
  /// rejection), not an error; an X25519 share that is a low-order point
  /// throws [TomPqcException].
  static Future<SecretBytes> decapsulate(
    Uint8List ciphertext,
    SecretBytes secretKey,
  ) async {
    if (ciphertext.length != ciphertextLength) {
      throw ArgumentError(
        'MLKEM768-X25519 ciphertext must be $ciphertextLength bytes, '
        'not ${ciphertext.length}',
      );
    }
    final expanded = await _expand(secretKey);
    try {
      final ctM = Uint8List.fromList(
        Uint8List.sublistView(ciphertext, 0, MlKem768.ciphertextLength),
      );
      final ctX = Uint8List.fromList(
        Uint8List.sublistView(ciphertext, MlKem768.ciphertextLength),
      );
      final ssM = MlKem768.decapsulate(ctM, expanded.mlKemSecretKey);
      try {
        final ssX = await _sharedSecret(expanded.x25519, ctX);
        return _combine(ssM, ssX, ctX, expanded.x25519Public);
      } finally {
        ssM.dispose();
      }
    } finally {
      expanded.dispose();
    }
  }

  /// SHA3-256(ss_M || ss_X || ct_X || pk_X || label), the bytes assembled in
  /// native memory.
  static SecretBytes _combine(
    SecretBytes ssM,
    Uint8List ssX,
    Uint8List ctX,
    Uint8List pkX,
  ) {
    final x = SecretBytes.fromBytes(ssX);
    ssX.fillRange(0, ssX.length, 0);
    final rest = SecretBytes.fromBytes(
      Uint8List.fromList([...ctX, ...pkX, ...label]),
    );
    final input = SecretBytes.concat([ssM, x, rest]);
    x.dispose();
    rest.dispose();
    try {
      return pqcBackend.sha3256Secret(input);
    } finally {
      input.dispose();
    }
  }

  static Future<Uint8List> _sharedSecret(
    SimpleKeyPair keyPair,
    Uint8List remotePublic,
  ) async {
    final secret = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(remotePublic, type: KeyPairType.x25519),
    );
    final bytes = Uint8List.fromList(await secret.extractBytes());
    // A low-order point (the identity among them) gives the all-zero secret,
    // which carries no contribution of the key; it is refused, as RFC 7748
    // section 6.1 allows and filippo.io/hpke-pq (age's MLKEM768-X25519) does.
    var any = 0;
    for (final b in bytes) {
      any |= b;
    }
    if (any == 0) {
      throw const TomPqcException(
        'MLKEM768-X25519: the X25519 share is a low-order point '
        '(all-zero shared secret)',
      );
    }
    return bytes;
  }

  /// SHAKE256(seed, 96): the ML-KEM-768 seed (64 bytes) and the X25519
  /// private key (32 bytes).
  static Future<_Expanded> _expand(SecretBytes seed) async {
    if (seed.length != secretKeyLength) {
      throw ArgumentError(
        'MLKEM768-X25519 secret key must be $secretKeyLength bytes, '
        'not ${seed.length}',
      );
    }
    final expanded = pqcBackend.shake256Secret(seed, 96);
    final mlkemSeed = expanded.sublist(0, 64);
    final pair = MlKem768.keyPairFromSeed(mlkemSeed);
    mlkemSeed.dispose();
    final skXSecret = expanded.sublist(64);
    expanded.dispose();
    final skX = skXSecret.extractBytes();
    skXSecret.dispose();
    try {
      final x = await _x25519.newKeyPairFromSeed(skX);
      final pkX = Uint8List.fromList((await x.extractPublicKey()).bytes);
      return _Expanded(pair.publicKey, pair.secretKey, x, pkX);
    } catch (_) {
      pair.dispose();
      throw const TomPqcException('MLKEM768-X25519 key expansion failed');
    } finally {
      skX.fillRange(0, skX.length, 0);
    }
  }
}

final class _Expanded {
  _Expanded(
    this.mlKemPublicKey,
    this.mlKemSecretKey,
    this.x25519,
    this.x25519Public,
  );

  final Uint8List mlKemPublicKey;
  final SecretBytes mlKemSecretKey;
  final SimpleKeyPair x25519;
  final Uint8List x25519Public;

  void dispose() {
    mlKemSecretKey.dispose();
    x25519.destroy();
  }
}
