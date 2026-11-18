# Tom PQC

Published on pub.dev as [`tom_pqc` 0.1.2](https://pub.dev/packages/tom_pqc).

> Tom PQC is part of the **Tom framework** by al-the-bear.
> Distributed under the terms in this package's license — see
> [LICENSE](LICENSE).

Post-quantum cryptography for Dart: ML-KEM-768, ML-DSA-65, X-Wing and
composite ML-DSA-65 + Ed25519 (RFC 10073), via FFI to vendored mlkem-native
and mldsa-native C code.

## Overview

`tom_pqc` offers the two NIST post-quantum standards at security category 3
and the hybrids built on them:

- **ML-KEM-768** (FIPS 203), the module-lattice key-encapsulation mechanism:
  a sender encapsulates a fresh shared secret to a receiver's public key, and
  only the receiver's secret key decapsulates it;
- **ML-DSA-65** (FIPS 204), the module-lattice signature scheme;
- **MLKEM768-X25519** (X-Wing), a hybrid KEM that stays secure while either
  ML-KEM-768 or X25519 holds; it is the KEM of `age` v1.3's post-quantum
  recipients;
- **ML-DSA-65 + Ed25519**, the composite signature of RFC 10073
  (`id-MLDSA65-Ed25519-SHA512`), valid only when both halves verify;
- **SHA3-256 and SHAKE256** (FIPS 202).

The post-quantum algorithms run in vetted, portable C — the PQ Code Package's
[mlkem-native](https://github.com/pq-code-package/mlkem-native) and
[mldsa-native](https://github.com/pq-code-package/mldsa-native), vendored
unchanged at pinned commits; the classical halves of the hybrids come from
[`cryptography`](https://pub.dev/packages/cryptography). The package's build
hook compiles that C for the target of the build, and the Dart API reaches it
through `dart:ffi`. Nothing is downloaded at build time and the package ships
no binaries. Secret keys, seeds and shared secrets
live in native memory (`SecretBytes`) and are overwritten when disposed.

## Installation

```bash
dart pub add tom_pqc
```

or in `pubspec.yaml`:

```yaml
dependencies:
  tom_pqc: ^0.1.0
```

Dart SDK `^3.10.0`.

**A C compiler.** The build hook (`hook/build.dart`) compiles the vendored C
with `native_toolchain_c`, which looks for the platform's compiler: clang
from the Xcode command-line tools on macOS, `clang` on the `PATH` on Linux
(a native Linux build does not use gcc), MSVC from Visual Studio or its Build
Tools (with the C++ build tools) on Windows. The hook runs on
the first `dart run`, `dart test` or build of a package that depends on
`tom_pqc` and is cached afterwards.

**Building an executable.** A package with a build hook is compiled with
`dart build cli`, not `dart compile exe`, which refuses it (`'dart compile'
does not support build hooks, use 'dart build' instead`):

```bash
dart build cli --target bin/my_app.dart
```

The bundle holds the executable in `bin/` and the native library
(`libtom_pqc.dylib`, `libtom_pqc.so` or `tom_pqc.dll`) in `lib/`; ship the
bundle as a whole. Flutter desktop builds bundle the library themselves.

## Features

### Algorithms

| Class | Standard | What it offers |
| --- | --- | --- |
| `MlKem768` | FIPS 203 | key pairs (fresh, or from a 64-byte seed d ‖ z), `encapsulate`, `decapsulate`, the encapsulation- and decapsulation-key checks |
| `MlDsa65` | FIPS 204 | key pairs from a 32-byte seed (the interoperable private key) or an expanded secret key, hedged `sign` with a context of up to 255 bytes, `verify` |
| `MlKem768X25519` | X-Wing (draft-connolly-cfrg-xwing-kem, `MLKEM768-X25519` of draft-ietf-hpke-pq) | a 32-byte secret key (a seed), `encapsulate`, `decapsulate`; a low-order X25519 share is refused |
| `MlDsa65Ed25519` | RFC 10073 `id-MLDSA65-Ed25519-SHA512` | a 64-byte secret key (two seeds), `sign` with an application context of up to 255 bytes, `verify` that needs both halves |
| `Sha3` | FIPS 202 | SHA3-256 and SHAKE256, also over `SecretBytes` |

### Secrets and errors

| Feature | What it does |
| --- | --- |
| `SecretBytes` | native memory for secret keys, seeds and shared secrets; `extractBytes()` copies them to the Dart heap, `dispose()` overwrites and frees them, a `NativeFinalizer` does the same for an object collected undisposed |
| Randomness | the operating system's generator: `SecRandomCopyBytes` on macOS, `getrandom` on Linux, `BCryptGenRandom` on Windows |
| `TomPqcException` | a key that fails a FIPS check, a low-order X25519 share, a failure of the C code; a value of the wrong length is an `ArgumentError` |

## Quick start

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:tom_pqc/tom_pqc.dart';

Future<void> main() async {
  final message = Uint8List.fromList(utf8.encode('demo message'));

  // ML-KEM-768: the receiver publishes its public key; the sender
  // encapsulates a fresh shared secret to it.
  final receiver = MlKem768.generateKeyPair();
  final sent = MlKem768.encapsulate(receiver.publicKey);
  final received = MlKem768.decapsulate(sent.ciphertext, receiver.secretKey);
  print(base64.encode(sent.sharedSecret.extractBytes()) ==
      base64.encode(received.extractBytes())); // true
  print(sent.ciphertext.length); // 1088

  // ML-DSA-65: sign and verify.
  final signer = MlDsa65.generateKeyPair();
  final signature = MlDsa65.sign(message, signer.secretKey);
  print(signature.length); // 3309
  print(MlDsa65.verify(message, signature, signer.publicKey)); // true

  // Overwrite the secrets as soon as they are no longer needed.
  sent.sharedSecret.dispose();
  received.dispose();
  receiver.dispose();
  signer.dispose();
}
```

## Example projects

| Sample | Demonstrates |
| --- | --- |
| [`example/tom_pqc_example.dart`](example/tom_pqc_example.dart) | The four schemes in a few lines each: an ML-KEM-768 key exchange, an ML-DSA-65 signature with a context, an X-Wing key exchange and a composite signature |

## Usage

The snippets below use `message`, a `Uint8List`.

### ML-KEM-768

```dart
// A key pair from a 64-byte seed: the same seed always gives the same pair,
// so the seed is the secret key's compact form (the one age stores).
final seed = MlKem768.generateSeed();
final pair = MlKem768.keyPairFromSeed(seed);

// FIPS 203's key checks, for keys from elsewhere.
print(MlKem768.isValidPublicKey(pair.publicKey)); // true
print(MlKem768.isValidSecretKey(pair.secretKey)); // true

final sent = MlKem768.encapsulate(pair.publicKey);
final received = MlKem768.decapsulate(sent.ciphertext, pair.secretKey);

sent.sharedSecret.dispose();
received.dispose();
pair.dispose();
seed.dispose();
```

`encapsulate` throws `TomPqcException` for a public key that fails FIPS 203's
modulus check. A ciphertext not made for the key does **not** fail to
decapsulate: FIPS 203's implicit rejection returns a secret no sender knows,
so the failure shows when the two sides use their secrets.

### ML-DSA-65

```dart
final context = Uint8List.fromList(utf8.encode('demo/context'));
final signer = MlDsa65.generateKeyPair();
final signature = MlDsa65.sign(message, signer.secretKey, context: context);

print(MlDsa65.verify(message, signature, signer.publicKey, context: context)); // true
print(MlDsa65.verify(message, signature, signer.publicKey)); // false: other context

// The 32-byte seed is the key to store; it gives the same key pair again.
final seed = SecretBytes.fromBytes(signer.seed!.extractBytes());
final again = MlDsa65.keyPairFromSeed(seed);

again.dispose(); // disposes the seed it keeps
signer.dispose();
```

Signing is hedged (fresh randomness mixed into each signature), so two
signatures of one message differ. `verify` answers `false` for malformed
input rather than throwing. `keyPairFromSecretKey` takes an expanded
4,032-byte secret key instead of a seed.

### MLKEM768-X25519 (X-Wing)

The hybrids are asynchronous, because their classical halves are:

```dart
final pair = await MlKem768X25519.generateKeyPair();
final capsule = await MlKem768X25519.encapsulate(pair.publicKey);
final opened = await MlKem768X25519.decapsulate(
  capsule.ciphertext,
  pair.secretKey,
);
// capsule.sharedSecret and opened hold the same 32 bytes.

// The public key follows from the 32-byte secret key.
final publicKey = await MlKem768X25519.publicKey(pair.secretKey);

capsule.sharedSecret.dispose();
opened.dispose();
pair.dispose();
```

The shared secret is SHA3-256 of the ML-KEM and X25519 shared secrets, the
X25519 ciphertext and public key, and the X-Wing label. A low-order X25519
share throws `TomPqcException`; a wrong ML-KEM half yields an unrelated secret,
as in ML-KEM.

### Composite ML-DSA-65 + Ed25519 (RFC 10073)

```dart
final context = Uint8List.fromList(utf8.encode('demo/context'));
final composite = await MlDsa65Ed25519.generateKeyPair();
final signature = await MlDsa65Ed25519.sign(
  message,
  composite.secretKey,
  context: context,
);
print(await MlDsa65Ed25519.verify(
  message,
  signature,
  composite.publicKey,
  context: context,
)); // true

composite.dispose();
```

Both halves sign the message representative
`Prefix ‖ Label ‖ len(ctx) ‖ ctx ‖ SHA-512(M)` (`MlDsa65Ed25519.representative`);
the signature is the ML-DSA-65 signature followed by the Ed25519 signature,
and `verify` answers `true` only when both verify.

### SHA3-256 and SHAKE256

```dart
final digest = Sha3.sha3256(message); // 32 bytes
final stream = Sha3.shake256(message, 64); // any length
```

`sha3256Secret` and `shake256Secret` take and answer `SecretBytes`, for
hashing a secret without copying it to the Dart heap.

### Secrets in memory

```dart
final secret = SecretBytes.fromBytes(Uint8List(32));
final copy = secret.extractBytes(); // a Dart heap copy, yours to overwrite
secret.dispose();
print(secret.isDisposed); // true
```

Dispose every key pair, seed and shared secret as soon as it is no longer
needed. A key pair's `dispose()` disposes its secret key (and an ML-DSA-65
pair its seed).

## Key sizes

The classes' `…Length` constants hold them; all sizes in bytes:

| Scheme | Public key | Secret key | Seed | Ciphertext / signature | Shared secret |
| --- | --- | --- | --- | --- | --- |
| ML-KEM-768 | 1,184 | 2,400 | 64 | ciphertext 1,088 | 32 |
| ML-DSA-65 | 1,952 | 4,032 (expanded) | 32 | signature 3,309 | — |
| MLKEM768-X25519 | 1,216 | 32 (the seed) | — | ciphertext 1,120 | 32 |
| ML-DSA-65 + Ed25519 | 1,984 | 64 (two seeds) | — | signature 3,373 | — |

## Architecture

```text
 hybrids       MlKem768X25519            MlDsa65Ed25519
                 |         \               /         |
                 |       package:cryptography        |
                 |       (X25519, Ed25519)           |
                 v                                   v
 Dart API      MlKem768          Sha3          MlDsa65         SecretBytes
                    \              |              /
                     PqcBackend (internal, not exported)
                                   |  dart:ffi
 native         libtom_pqc, built by hook/build.dart
                tom_pqc.h: the backend interface, the only exported symbols
                 /                 |                    \
         mlkem-native         mldsa-native         OS random generator
         (ML-KEM, SHA3)       (ML-DSA)
```

The Dart API calls the C code only through a small backend interface
(`native/tom_pqc.h`, `PqcBackend` on the Dart side); the hybrids are built on
the Dart API, never on a C library directly. Each vendored library is compiled
as one unit with all of its symbols `static`, so the native library exports
nothing but that interface, and another C implementation could replace them
without changing the Dart API, provided it passes the same known-answer tests.
Only the libraries' portable C is vendored; their assembly back ends are not.

| Type | Responsibility |
| --- | --- |
| `MlKem768`, `MlKem768KeyPair`, `MlKem768Encapsulation` | ML-KEM-768 |
| `MlDsa65`, `MlDsa65KeyPair` | ML-DSA-65 |
| `MlKem768X25519`, `MlKem768X25519KeyPair`, `MlKem768X25519Encapsulation` | X-Wing |
| `MlDsa65Ed25519`, `MlDsa65Ed25519KeyPair` | the RFC 10073 composite signature |
| `Sha3` | SHA3-256, SHAKE256 |
| `SecretBytes` | secrets in native memory |
| `TomPqcException` | the package's failures |

## Test vectors

The suite checks the package against:

- NIST's ACVP known-answer vectors for ML-KEM-768 (key generation,
  encapsulation, decapsulation, both key checks) and ML-DSA-65 (key
  generation; signing, deterministic and hedged, through the external,
  internal and external-mu interfaces; verification);
- every ML-KEM-768 and ML-DSA-65 case of Project Wycheproof;
- the X-Wing draft's test vectors and RFC 10073's composite vector;
- every hybrid file of the age testkit, decrypted through a minimal age reader
  with this package's MLKEM768-X25519;
- a cross-check with Go's standard library (`crypto/mlkem`, `crypto/mldsa`,
  `crypto/hpke`).

Each set is kept as its source wrote it, with its origin and commit;
[`THIRD_PARTY.md`](THIRD_PARTY.md) lists them.

## Platforms

| Platform | Status |
| --- | --- |
| macOS (arm64) | supported, verified |
| Linux (x64) | supported, verified |
| Windows (x64) | supported, verified |
| iOS (arm64, device and simulator) | supported, verified (Flutter; the ACVP vectors on a simulator) |
| Android (arm64-v8a, armeabi-v7a, x86_64) | supported, verified (Flutter; the ACVP vectors on an emulator, API 33) |
| Web | not supported (`dart:ffi`) |

The library is bundled by `dart run` and `dart test`, by `dart build cli` and
by Flutter builds, desktop and mobile.

## Limits

- **One parameter set each.** ML-KEM-768 and ML-DSA-65 only; HashML-DSA (the
  pre-hash variant of FIPS 204) is not offered.
- **Side channels.** The post-quantum code is the vendored libraries' portable
  C, compiled as their authors wrote it; `tom_pqc` makes no side-channel claim
  of its own beyond it.
- **The classical halves pass the Dart heap.** X25519 and Ed25519 run in
  `package:cryptography`, so the hybrids' classical key bytes are on the Dart
  heap briefly and are overwritten after use.
- **Copies are the caller's.** `extractBytes()` copies a secret to the Dart
  heap; that copy is not overwritten by `dispose()`.

## Licence

`tom_pqc`'s own code (the Dart library, the build hook, the tools and the C
glue under `native/`) is BSD-3-Clause, see [`LICENSE`](LICENSE). The vendored
mlkem-native (v2.0.0) and mldsa-native (v2.0.0) are available under
Apache-2.0 OR ISC OR MIT and are used under MIT; their licences are kept as
[`native/mlkem-native/LICENSE`](native/mlkem-native/LICENSE) and
[`native/mldsa-native/LICENSE`](native/mldsa-native/LICENSE).
[`THIRD_PARTY.md`](THIRD_PARTY.md) names the vendored files, their origin and
commit, the Dart dependencies' licences and the licences of the test vectors.

## Further documentation

| Document | Covers |
| --- | --- |
| [`doc/pqc.md`](doc/pqc.md) | the user guide: concepts, every scheme with examples, secrets in memory, errors, platforms and limits |
| [`example/`](example/) | the runnable example |
| [`THIRD_PARTY.md`](THIRD_PARTY.md) | the vendored C, its commits and licences; the test vectors and their sources |
| [`CHANGELOG.md`](CHANGELOG.md) | the releases |
| [API reference](https://pub.dev/documentation/tom_pqc/latest/) | every public type and member |
| [mlkem-native](https://github.com/pq-code-package/mlkem-native), [mldsa-native](https://github.com/pq-code-package/mldsa-native) | the C implementations and their verification |
| [FIPS 203](https://csrc.nist.gov/pubs/fips/203/final), [FIPS 204](https://csrc.nist.gov/pubs/fips/204/final), [RFC 10073](https://www.rfc-editor.org/rfc/rfc10073) | the standards |

## Status

Version **0.1.2**, published on [pub.dev](https://pub.dev/packages/tom_pqc).
`dart test` from the package root runs the known-answer and cross-check suites
listed under [Test vectors](#test-vectors), the API's behaviour and the licence
checks; the build hook compiles the C on the first run.

Repository: [github.com/al-the-bear/tom_basics — tom_pqc](https://github.com/al-the-bear/tom_basics/tree/main/tom_pqc)
