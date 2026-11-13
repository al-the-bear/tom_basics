// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The backend interface: the one boundary between tom_pqc's Dart API and a
/// C implementation of the algorithms (TD-2).
///
/// The public classes ([MlKem768]) call nothing but a [PqcBackend]. The
/// vendored mlkem-native is the one backend ([NativePqcBackend]); another C
/// implementation (liboqs, PQClean) replaces it by implementing the same C
/// functions (`native/tom_pqc.h`) or this interface, and passes the same
/// known-answer tests before it may. Not exported from the package.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_backend.dart';
import 'pqc_exception.dart';
import 'secret_bytes.dart';

/// ML-KEM-768 sizes in bytes (FIPS 203, Table 3).
abstract final class MlKem768Sizes {
  static const publicKey = 1184;
  static const secretKey = 2400;
  static const ciphertext = 1088;
  static const sharedSecret = 32;
  static const seed = 64;
  static const encapsulationCoins = 32;
}

/// One ML-KEM-768 encapsulation: the ciphertext for the holder of the secret
/// key, and the shared secret it carries.
final class MlKem768Encapsulation {
  MlKem768Encapsulation(this.ciphertext, this.sharedSecret);

  /// [MlKem768Sizes.ciphertext] bytes, sent to the key holder.
  final Uint8List ciphertext;

  /// [MlKem768Sizes.sharedSecret] bytes in native memory; dispose when used.
  final SecretBytes sharedSecret;
}

/// The operations a backend provides.
abstract interface class PqcBackend {
  /// What the backend is: the code and the version or commit it is pinned to.
  String get name;

  /// [length] bytes from the operating system's generator.
  Uint8List randomBytes(int length);

  /// ML-KEM.KeyGen_internal(d, z) from `seed` = d || z (64 bytes).
  (Uint8List publicKey, SecretBytes secretKey) mlKem768KeyPairFromSeed(
    SecretBytes seed,
  );

  /// ML-KEM.KeyGen, from the operating system's generator.
  (Uint8List publicKey, SecretBytes secretKey) mlKem768GenerateKeyPair();

  /// ML-KEM.Encaps; [coins] (32 bytes, the m of Encaps_internal) only for
  /// known-answer tests.
  MlKem768Encapsulation mlKem768Encapsulate(
    Uint8List publicKey, {
    Uint8List? coins,
  });

  /// ML-KEM.Decaps.
  SecretBytes mlKem768Decapsulate(Uint8List ciphertext, SecretBytes secretKey);

  /// The encapsulation-key check of FIPS 203 Section 7.2.
  bool mlKem768CheckPublicKey(Uint8List publicKey);

  /// The decapsulation-key check of FIPS 203 Section 7.3.
  bool mlKem768CheckSecretKey(SecretBytes secretKey);
}

/// The backend over the native library built from the vendored mlkem-native.
final class NativePqcBackend implements PqcBackend {
  const NativePqcBackend();

  @override
  String get name => tomPqcBackendName().toDartString();

  @override
  Uint8List randomBytes(int length) {
    if (length < 0) throw ArgumentError.value(length, 'length');
    if (length == 0) return Uint8List(0);
    return using((arena) {
      final out = arena<Uint8>(length);
      _check(tomPqcRandomBytes(out, length), 'random bytes');
      return Uint8List.fromList(out.asTypedList(length));
    });
  }

  @override
  (Uint8List, SecretBytes) mlKem768KeyPairFromSeed(SecretBytes seed) {
    _length(seed.length, MlKem768Sizes.seed, 'seed');
    return _keyPair(
      (pk, sk) => tomPqcMlKem768KeypairDerand(pk, sk, seed.pointer),
    );
  }

  @override
  (Uint8List, SecretBytes) mlKem768GenerateKeyPair() =>
      _keyPair(tomPqcMlKem768Keypair);

  (Uint8List, SecretBytes) _keyPair(
    int Function(Pointer<Uint8> pk, Pointer<Uint8> sk) generate,
  ) {
    final secretKey = SecretBytes.allocate(MlKem768Sizes.secretKey);
    try {
      return using((arena) {
        final pk = arena<Uint8>(MlKem768Sizes.publicKey);
        _check(generate(pk, secretKey.pointer), 'ML-KEM-768 key generation');
        return (
          Uint8List.fromList(pk.asTypedList(MlKem768Sizes.publicKey)),
          secretKey,
        );
      });
    } catch (_) {
      secretKey.dispose();
      rethrow;
    }
  }

  @override
  MlKem768Encapsulation mlKem768Encapsulate(
    Uint8List publicKey, {
    Uint8List? coins,
  }) {
    _length(publicKey.length, MlKem768Sizes.publicKey, 'public key');
    if (coins != null) {
      _length(coins.length, MlKem768Sizes.encapsulationCoins, 'coins');
    }
    final sharedSecret = SecretBytes.allocate(MlKem768Sizes.sharedSecret);
    try {
      return using((arena) {
        final ct = arena<Uint8>(MlKem768Sizes.ciphertext);
        final pk = _copy(arena, publicKey);
        final rc = coins == null
            ? tomPqcMlKem768Enc(ct, sharedSecret.pointer, pk)
            : tomPqcMlKem768EncDerand(
                ct,
                sharedSecret.pointer,
                pk,
                _copy(arena, coins),
              );
        _check(rc, 'ML-KEM-768 encapsulation');
        return MlKem768Encapsulation(
          Uint8List.fromList(ct.asTypedList(MlKem768Sizes.ciphertext)),
          sharedSecret,
        );
      });
    } catch (_) {
      sharedSecret.dispose();
      rethrow;
    }
  }

  @override
  SecretBytes mlKem768Decapsulate(Uint8List ciphertext, SecretBytes secretKey) {
    _length(ciphertext.length, MlKem768Sizes.ciphertext, 'ciphertext');
    _length(secretKey.length, MlKem768Sizes.secretKey, 'secret key');
    final sharedSecret = SecretBytes.allocate(MlKem768Sizes.sharedSecret);
    try {
      using((arena) {
        _check(
          tomPqcMlKem768Dec(
            sharedSecret.pointer,
            _copy(arena, ciphertext),
            secretKey.pointer,
          ),
          'ML-KEM-768 decapsulation',
        );
      });
      return sharedSecret;
    } catch (_) {
      sharedSecret.dispose();
      rethrow;
    }
  }

  @override
  bool mlKem768CheckPublicKey(Uint8List publicKey) {
    if (publicKey.length != MlKem768Sizes.publicKey) return false;
    return using(
      (arena) => tomPqcMlKem768CheckPk(_copy(arena, publicKey)) == 0,
    );
  }

  @override
  bool mlKem768CheckSecretKey(SecretBytes secretKey) {
    if (secretKey.length != MlKem768Sizes.secretKey) return false;
    return tomPqcMlKem768CheckSk(secretKey.pointer) == 0;
  }

  static Pointer<Uint8> _copy(Arena arena, Uint8List bytes) {
    final pointer = arena<Uint8>(bytes.length);
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  static void _length(int actual, int expected, String what) {
    if (actual != expected) {
      throw ArgumentError(
        'ML-KEM-768 $what must be $expected bytes, not $actual',
      );
    }
  }

  static void _check(int rc, String operation) {
    switch (rc) {
      case 0:
        return;
      case -2:
        throw TomPqcException(
          '$operation: the public key fails the FIPS 203 modulus check',
        );
      case -3:
        throw TomPqcException(
          '$operation: the secret key fails the FIPS 203 hash check',
        );
      case -4:
        throw TomPqcException(
          '$operation: the operating system random generator failed',
        );
      case -5:
        throw TomPqcException('$operation: out of memory');
      default:
        throw TomPqcException('$operation failed (code $rc)');
    }
  }
}

/// The backend the package uses.
const PqcBackend pqcBackend = NativePqcBackend();
