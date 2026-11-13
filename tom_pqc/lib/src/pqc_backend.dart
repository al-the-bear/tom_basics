// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The backend interface: the one boundary between tom_pqc's Dart API and a
/// C implementation of the algorithms (TD-2).
///
/// The public classes ([MlKem768], [MlDsa65], [Sha3] and the hybrids on top
/// of them) call nothing but a [PqcBackend]. The vendored mlkem-native and
/// mldsa-native are the one backend ([NativePqcBackend]); another C
/// implementation (liboqs, PQClean) replaces them by implementing the same C
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

/// ML-DSA-65 sizes in bytes (FIPS 204, Table 2).
abstract final class MlDsa65Sizes {
  static const publicKey = 1952;
  static const secretKey = 4032;
  static const signature = 3309;
  static const seed = 32;
  static const rnd = 32;
  static const mu = 64;
  static const maxContext = 255;
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

  /// The ML-DSA backend's name, likewise.
  String get mlDsaName;

  /// SHA3-256 of [input] (FIPS 202).
  Uint8List sha3256(Uint8List input);

  /// SHA3-256 of the secret [input], kept in native memory.
  SecretBytes sha3256Secret(SecretBytes input);

  /// [length] bytes of SHAKE256 of [input] (FIPS 202).
  Uint8List shake256(Uint8List input, int length);

  /// [length] bytes of SHAKE256 of the secret [input], kept in native memory.
  SecretBytes shake256Secret(SecretBytes input, int length);

  /// ML-DSA.KeyGen_internal from the 32-byte [seed]: the public key and the
  /// expanded secret key.
  (Uint8List publicKey, SecretBytes secretKey) mlDsa65KeyPairFromSeed(
    SecretBytes seed,
  );

  /// The public key the expanded [secretKey] holds; throws for a malformed
  /// key.
  Uint8List mlDsa65PublicKey(SecretBytes secretKey);

  /// ML-DSA.Sign, hedged, with [context] (at most 255 bytes).
  Uint8List mlDsa65Sign(
    Uint8List message,
    SecretBytes secretKey, {
    Uint8List? context,
  });

  /// ML-DSA.Sign_internal over [prefix] || [message] with [rnd] (32 bytes;
  /// all zero is the deterministic variant); with [externalMu], [message] is
  /// the 64-byte mu and [prefix] must be empty.
  Uint8List mlDsa65SignInternal(
    Uint8List message,
    SecretBytes secretKey, {
    required Uint8List prefix,
    required Uint8List rnd,
    bool externalMu = false,
  });

  /// ML-DSA.Verify with [context].
  bool mlDsa65Verify(
    Uint8List message,
    Uint8List signature,
    Uint8List publicKey, {
    Uint8List? context,
  });

  /// ML-DSA.Verify_internal over [prefix] || [message], or over mu.
  bool mlDsa65VerifyInternal(
    Uint8List message,
    Uint8List signature,
    Uint8List publicKey, {
    required Uint8List prefix,
    bool externalMu = false,
  });

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
  String get mlDsaName => tomPqcMlDsaBackendName().toDartString();

  @override
  Uint8List sha3256(Uint8List input) => using((arena) {
    final out = arena<Uint8>(32);
    _check(tomPqcSha3256(out, _copy(arena, input), input.length), 'SHA3-256');
    return Uint8List.fromList(out.asTypedList(32));
  });

  @override
  SecretBytes sha3256Secret(SecretBytes input) {
    final out = SecretBytes.allocate(32);
    final rc = tomPqcSha3256(out.pointer, input.pointer, input.length);
    if (rc != 0) {
      out.dispose();
      _check(rc, 'SHA3-256');
    }
    return out;
  }

  @override
  Uint8List shake256(Uint8List input, int length) {
    if (length <= 0) throw ArgumentError.value(length, 'length');
    return using((arena) {
      final out = arena<Uint8>(length);
      _check(
        tomPqcShake256(out, length, _copy(arena, input), input.length),
        'SHAKE256',
      );
      return Uint8List.fromList(out.asTypedList(length));
    });
  }

  @override
  SecretBytes shake256Secret(SecretBytes input, int length) {
    final out = SecretBytes.allocate(length);
    final rc = tomPqcShake256(out.pointer, length, input.pointer, input.length);
    if (rc != 0) {
      out.dispose();
      _check(rc, 'SHAKE256');
    }
    return out;
  }

  @override
  (Uint8List, SecretBytes) mlDsa65KeyPairFromSeed(SecretBytes seed) {
    _sized(seed.length, MlDsa65Sizes.seed, 'ML-DSA-65 seed');
    final secretKey = SecretBytes.allocate(MlDsa65Sizes.secretKey);
    try {
      return using((arena) {
        final pk = arena<Uint8>(MlDsa65Sizes.publicKey);
        _check(
          tomPqcMlDsa65KeypairDerand(pk, secretKey.pointer, seed.pointer),
          'ML-DSA-65 key generation',
        );
        return (
          Uint8List.fromList(pk.asTypedList(MlDsa65Sizes.publicKey)),
          secretKey,
        );
      });
    } catch (_) {
      secretKey.dispose();
      rethrow;
    }
  }

  @override
  Uint8List mlDsa65PublicKey(SecretBytes secretKey) {
    _sized(secretKey.length, MlDsa65Sizes.secretKey, 'ML-DSA-65 secret key');
    return using((arena) {
      final pk = arena<Uint8>(MlDsa65Sizes.publicKey);
      _check(
        tomPqcMlDsa65PkFromSk(pk, secretKey.pointer),
        'ML-DSA-65 public key from secret key',
      );
      return Uint8List.fromList(pk.asTypedList(MlDsa65Sizes.publicKey));
    });
  }

  @override
  Uint8List mlDsa65Sign(
    Uint8List message,
    SecretBytes secretKey, {
    Uint8List? context,
  }) {
    final ctx = context ?? Uint8List(0);
    _context(ctx);
    _sized(secretKey.length, MlDsa65Sizes.secretKey, 'ML-DSA-65 secret key');
    return using((arena) {
      final sig = arena<Uint8>(MlDsa65Sizes.signature);
      _check(
        tomPqcMlDsa65Sign(
          sig,
          _copy(arena, message),
          message.length,
          _copy(arena, ctx),
          ctx.length,
          secretKey.pointer,
        ),
        'ML-DSA-65 signing',
      );
      return Uint8List.fromList(sig.asTypedList(MlDsa65Sizes.signature));
    });
  }

  @override
  Uint8List mlDsa65SignInternal(
    Uint8List message,
    SecretBytes secretKey, {
    required Uint8List prefix,
    required Uint8List rnd,
    bool externalMu = false,
  }) {
    _sized(rnd.length, MlDsa65Sizes.rnd, 'ML-DSA-65 rnd');
    _sized(secretKey.length, MlDsa65Sizes.secretKey, 'ML-DSA-65 secret key');
    if (externalMu) {
      _sized(message.length, MlDsa65Sizes.mu, 'ML-DSA-65 mu');
      if (prefix.isNotEmpty) {
        throw ArgumentError('an external mu takes no prefix');
      }
    }
    return using((arena) {
      final sig = arena<Uint8>(MlDsa65Sizes.signature);
      _check(
        tomPqcMlDsa65SignInternal(
          sig,
          _copy(arena, message),
          message.length,
          _copy(arena, prefix),
          prefix.length,
          _copy(arena, rnd),
          secretKey.pointer,
          externalMu ? 1 : 0,
        ),
        'ML-DSA-65 signing',
      );
      return Uint8List.fromList(sig.asTypedList(MlDsa65Sizes.signature));
    });
  }

  @override
  bool mlDsa65Verify(
    Uint8List message,
    Uint8List signature,
    Uint8List publicKey, {
    Uint8List? context,
  }) {
    final ctx = context ?? Uint8List(0);
    if (ctx.length > MlDsa65Sizes.maxContext ||
        signature.length != MlDsa65Sizes.signature ||
        publicKey.length != MlDsa65Sizes.publicKey) {
      return false;
    }
    return using(
      (arena) =>
          tomPqcMlDsa65Verify(
            _copy(arena, signature),
            _copy(arena, message),
            message.length,
            _copy(arena, ctx),
            ctx.length,
            _copy(arena, publicKey),
          ) ==
          0,
    );
  }

  @override
  bool mlDsa65VerifyInternal(
    Uint8List message,
    Uint8List signature,
    Uint8List publicKey, {
    required Uint8List prefix,
    bool externalMu = false,
  }) {
    if (signature.length != MlDsa65Sizes.signature ||
        publicKey.length != MlDsa65Sizes.publicKey ||
        (externalMu &&
            (message.length != MlDsa65Sizes.mu || prefix.isNotEmpty))) {
      return false;
    }
    return using(
      (arena) =>
          tomPqcMlDsa65VerifyInternal(
            _copy(arena, signature),
            _copy(arena, message),
            message.length,
            _copy(arena, prefix),
            prefix.length,
            _copy(arena, publicKey),
            externalMu ? 1 : 0,
          ) ==
          0,
    );
  }

  static void _sized(int actual, int expected, String what) {
    if (actual != expected) {
      throw ArgumentError('$what must be $expected bytes, not $actual');
    }
  }

  static void _context(Uint8List context) {
    if (context.length > MlDsa65Sizes.maxContext) {
      throw ArgumentError(
        'an ML-DSA context is at most ${MlDsa65Sizes.maxContext} bytes, '
        'not ${context.length}',
      );
    }
  }

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
      case -6:
        throw TomPqcException('$operation: invalid signature');
      case -7:
        throw TomPqcException('$operation: invalid argument');
      default:
        throw TomPqcException('$operation failed (code $rc)');
    }
  }
}

/// The backend the package uses.
const PqcBackend pqcBackend = NativePqcBackend();
