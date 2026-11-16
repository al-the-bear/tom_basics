# Tom PQC User Guide

Tom PQC gives Dart code the NIST post-quantum algorithms ML-KEM-768 (key
encapsulation, FIPS 203) and ML-DSA-65 (signatures, FIPS 204), the hybrids
built on them — the X-Wing KEM MLKEM768-X25519 and the RFC 10073 composite
signature ML-DSA-65 + Ed25519 — and the SHA-3 hashes they use. The
post-quantum code is vendored C (mlkem-native and mldsa-native), compiled by
the package's build hook and called through `dart:ffi`.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Core Components](#core-components)
- [Key Encapsulation: ML-KEM-768](#key-encapsulation-ml-kem-768)
- [Signatures: ML-DSA-65](#signatures-ml-dsa-65)
- [Hybrid KEM: MLKEM768-X25519 (X-Wing)](#hybrid-kem-mlkem768-x25519-x-wing)
- [Composite Signature: ML-DSA-65 + Ed25519](#composite-signature-ml-dsa-65--ed25519)
- [Hashes: SHA3-256 and SHAKE256](#hashes-sha3-256-and-shake256)
- [Secrets in Memory](#secrets-in-memory)
- [Sizes](#sizes)
- [Building and Platforms](#building-and-platforms)
- [Error Handling](#error-handling)
- [Limits](#limits)
- [Best Practices](#best-practices)

## Overview

Two kinds of operation are offered:

- A **key-encapsulation mechanism (KEM)** agrees a 32-byte shared secret. The
  receiver publishes a public key; a sender *encapsulates* to it, which yields
  a ciphertext and a shared secret; the receiver *decapsulates* the
  ciphertext with its secret key and gets the same shared secret. The secret
  then keys a symmetric cipher of your choice — this package does no
  symmetric encryption itself.
- A **signature scheme** signs a message with a secret key; anybody with the
  public key verifies it.

Each comes in a pure post-quantum form (`MlKem768`, `MlDsa65`) and a hybrid
form that pairs it with a classical algorithm (`MlKem768X25519`,
`MlDsa65Ed25519`), which stays secure as long as either half holds. The
post-quantum operations are synchronous; the hybrids are asynchronous,
because their classical halves run in `package:cryptography`, whose API is.

Secret keys, seeds and shared secrets are `SecretBytes`: buffers in native
memory that are overwritten when disposed. Public keys, ciphertexts and
signatures are plain `Uint8List`s.

## Quick Start

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:tom_pqc/tom_pqc.dart';

void main() {
  final receiver = MlKem768.generateKeyPair();
  final sent = MlKem768.encapsulate(receiver.publicKey);
  final received = MlKem768.decapsulate(sent.ciphertext, receiver.secretKey);
  print(base64.encode(sent.sharedSecret.extractBytes()) ==
      base64.encode(received.extractBytes())); // true

  final message = Uint8List.fromList(utf8.encode('hello'));
  final signer = MlDsa65.generateKeyPair();
  final signature = MlDsa65.sign(message, signer.secretKey);
  print(MlDsa65.verify(message, signature, signer.publicKey)); // true

  sent.sharedSecret.dispose();
  received.dispose();
  receiver.dispose();
  signer.dispose();
}
```

The first `dart run` or `dart test` compiles the C code (see
[Building and Platforms](#building-and-platforms)).

## Core Components

| Type | Role |
| --- | --- |
| `MlKem768` | ML-KEM-768: key pairs, `encapsulate`, `decapsulate`, the FIPS 203 key checks. |
| `MlKem768KeyPair`, `MlKem768Encapsulation` | A key pair (`publicKey`, `secretKey`); an encapsulation (`ciphertext`, `sharedSecret`). |
| `MlDsa65` | ML-DSA-65: key pairs from a seed or an expanded secret key, `sign`, `verify`. |
| `MlDsa65KeyPair` | `publicKey`, the expanded `secretKey`, and the 32-byte `seed` when known. |
| `MlKem768X25519` | The X-Wing hybrid KEM. |
| `MlKem768X25519KeyPair`, `MlKem768X25519Encapsulation` | Its key pair and encapsulation. |
| `MlDsa65Ed25519` | The RFC 10073 composite signature. |
| `MlDsa65Ed25519KeyPair` | Its key pair. |
| `Sha3` | SHA3-256 and SHAKE256, over bytes or over `SecretBytes`. |
| `SecretBytes` | A secret in native memory. |
| `TomPqcException` | A failure of an operation. |

Every key pair class has `dispose()`, which disposes its secret parts.

## Key Encapsulation: ML-KEM-768

```dart
final pair = MlKem768.generateKeyPair();
final sent = MlKem768.encapsulate(pair.publicKey); // the sender's side
final secret = MlKem768.decapsulate(sent.ciphertext, pair.secretKey);
```

- `generateKeyPair()` draws a fresh pair from the operating system's random
  generator.
- `keyPairFromSeed(seed)` derives the pair from a 64-byte seed (d ‖ z, FIPS
  203's `ML-KEM.KeyGen_internal`). The same seed always gives the same pair,
  so the seed is the compact form of the secret key — the form `age` stores.
  `generateSeed()` makes a fresh one. The pair does not keep the seed;
  dispose it yourself.
- `encapsulate(publicKey)` throws `TomPqcException` when the public key fails
  FIPS 203's modulus check.
- `decapsulate(ciphertext, secretKey)` throws `TomPqcException` when the
  secret key fails FIPS 203's hash check. A ciphertext that was **not** made
  for the key does not fail: FIPS 203's implicit rejection returns a secret
  that no sender knows, so the mismatch shows only when the two sides use
  their secrets.
- `isValidPublicKey(publicKey)` and `isValidSecretKey(secretKey)` run the
  FIPS 203 key checks (sections 7.2 and 7.3) on keys received from elsewhere.

## Signatures: ML-DSA-65

```dart
final context = Uint8List.fromList(utf8.encode('invoices/v1'));
final signer = MlDsa65.generateKeyPair();
final signature = MlDsa65.sign(message, signer.secretKey, context: context);
print(MlDsa65.verify(message, signature, signer.publicKey,
    context: context)); // true
print(MlDsa65.verify(message, signature, signer.publicKey)); // false
```

- `generateKeyPair()` makes a fresh 32-byte seed and derives the pair from
  it; the pair keeps the seed (`pair.seed`). The seed is the interoperable
  form of the private key — store it, not the 4,032-byte expanded key.
- `keyPairFromSeed(seed)` derives the pair again from a stored seed and keeps
  the seed: disposing the pair disposes it.
- `keyPairFromSecretKey(secretKey)` takes an expanded secret key instead; such
  a pair has no seed. A malformed key throws `TomPqcException`.
- `sign` is **hedged**, FIPS 204's default: fresh randomness is mixed in, so
  two signatures of one message differ, and both verify.
- The optional `context` (at most 255 bytes) separates uses of one key: a
  signature verifies only under the context it was made with.
- `verify` answers `false` for malformed input — a signature or key of the
  wrong length included — rather than throwing.

HashML-DSA, FIPS 204's pre-hash variant, is not offered.

## Hybrid KEM: MLKEM768-X25519 (X-Wing)

MLKEM768-X25519, also called X-Wing (draft-connolly-cfrg-xwing-kem;
`MLKEM768-X25519` of draft-ietf-hpke-pq), combines ML-KEM-768 with X25519. It
is the KEM of `age` v1.3's `mlkem768x25519` recipients.

```dart
final pair = await MlKem768X25519.generateKeyPair();
final capsule = await MlKem768X25519.encapsulate(pair.publicKey);
final opened = await MlKem768X25519.decapsulate(
  capsule.ciphertext,
  pair.secretKey,
);
// capsule.sharedSecret and opened hold the same 32 bytes.
```

- The secret key is a 32-byte seed; SHAKE256 expands it into the ML-KEM-768
  seed and the X25519 private key. `keyPairFromSeed(seed)` rebuilds the pair
  and keeps the seed as its secret key; `publicKey(secretKey)` derives only
  the 1,216-byte public key (the ML-KEM key followed by the X25519 key).
- The 1,120-byte ciphertext is the ML-KEM ciphertext followed by the
  ephemeral X25519 public key.
- The shared secret is SHA3-256 of the ML-KEM shared secret, the X25519
  shared secret, the X25519 ciphertext and public key, and the label
  `\.//^\` (`MlKem768X25519.label`), so it stays secret while either half
  holds.
- An X25519 share that is a low-order point (it would give the all-zero
  shared secret) throws `TomPqcException`. A wrong ML-KEM half yields an
  unrelated secret, as in ML-KEM.

## Composite Signature: ML-DSA-65 + Ed25519

`MlDsa65Ed25519` is RFC 10073's `id-MLDSA65-Ed25519-SHA512` (OID
1.3.6.1.5.5.7.6.48). Keys, signatures and the application context follow the
RFC byte for byte, so other implementations of it interoperate.

```dart
final composite = await MlDsa65Ed25519.generateKeyPair();
final signature = await MlDsa65Ed25519.sign(message, composite.secretKey);
print(await MlDsa65Ed25519.verify(
  message,
  signature,
  composite.publicKey,
)); // true
composite.dispose();
```

- The 64-byte secret key is the ML-DSA-65 seed followed by the Ed25519 seed;
  `keyPairFromSecretKey` and `publicKey` derive the 1,984-byte public key
  (the ML-DSA-65 key followed by the Ed25519 key) from it.
- Both halves sign the message representative
  `M' = Prefix ‖ Label ‖ len(ctx) ‖ ctx ‖ SHA-512(M)`, ML-DSA-65 with the
  Label as its context; `representative(message, context:)` computes `M'`.
  The 3,373-byte signature is the ML-DSA-65 signature followed by the Ed25519
  signature.
- `verify` answers `true` only when both halves verify, and `false` for
  malformed input.
- The optional application `context` is at most 255 bytes; `sign` throws
  `ArgumentError` for a longer one.

## Hashes: SHA3-256 and SHAKE256

`Sha3` exposes the FIPS 202 hashes from the vendored C code — the ones the
hybrid combiner uses:

```dart
final digest = Sha3.sha3256(message); // 32 bytes
final stream = Sha3.shake256(message, 64); // any positive length
```

`sha3256Secret` and `shake256Secret` take and return `SecretBytes`, so a
secret can be hashed or expanded without passing the Dart heap.

## Secrets in Memory

`SecretBytes` keeps a secret in native memory, outside the Dart heap.

| Member | Behaviour |
| --- | --- |
| `SecretBytes.fromBytes(bytes)` | Copies `bytes` into native memory. The caller still owns `bytes` and should overwrite it (`bytes.fillRange(0, bytes.length, 0)`). |
| `SecretBytes.allocate(length)` | A zeroed native buffer. |
| `extractBytes()` | A copy on the Dart heap; the copy is the caller's to overwrite. |
| `sublist(start, [end])`, `SecretBytes.concat(parts)` | New secrets, copied native to native. |
| `dispose()` | Overwrites and frees the buffer; safe to call twice. Using the secret afterwards throws `StateError`. |
| `isDisposed`, `length` | State and size. |

A `NativeFinalizer` overwrites and frees a secret that is garbage-collected
undisposed, but the collector decides when that happens: dispose every key
pair, seed and shared secret as soon as it is no longer needed.

The hybrids' classical halves run in `package:cryptography`, so their X25519
and Ed25519 key bytes pass the Dart heap briefly; the package overwrites them
after use.

## Sizes

All sizes in bytes; each class exposes them as `…Length` constants.

| Scheme | Public key | Secret key | Seed | Ciphertext / signature | Shared secret |
| --- | --- | --- | --- | --- | --- |
| ML-KEM-768 | 1,184 | 2,400 | 64 | ciphertext 1,088 | 32 |
| ML-DSA-65 | 1,952 | 4,032 (expanded) | 32 | signature 3,309 | — |
| MLKEM768-X25519 | 1,216 | 32 (the seed) | — | ciphertext 1,120 | 32 |
| ML-DSA-65 + Ed25519 | 1,984 | 64 (two seeds) | — | signature 3,373 | — |

## Building and Platforms

The build hook (`hook/build.dart`) compiles the vendored C with
`native_toolchain_c` for the target of the build, the first time a package
depending on Tom PQC runs, tests or builds; the result is cached. It needs the
platform's C compiler: clang from the Xcode command-line tools on macOS,
`clang` on the `PATH` on Linux, MSVC (Visual Studio or its Build Tools) on
Windows. Nothing is downloaded and no binaries ship with the package.

An executable that uses Tom PQC is built with `dart build cli`; `dart compile
exe` refuses packages with build hooks. The bundle holds the native library
(`libtom_pqc.dylib`, `libtom_pqc.so` or `tom_pqc.dll`) in `lib/` beside the
executable in `bin/` — ship the bundle as a whole. Flutter desktop builds
bundle the library themselves.

| Platform | Status | Random generator |
| --- | --- | --- |
| macOS (arm64) | supported, verified | `SecRandomCopyBytes` |
| Linux (x64) | supported, verified | `getrandom` |
| Windows (x64) | supported, verified | `BCryptGenRandom` |
| iOS, Android | not built yet | — |
| Web | not supported (`dart:ffi`) | — |

## Error Handling

| Error | When |
| --- | --- |
| `TomPqcException` | A public key that fails FIPS 203's modulus check, a secret key that fails its hash check, a malformed ML-DSA-65 expanded key, a low-order X25519 share, a failure of the operating system's random generator, out of memory. Its `message` names the operation. |
| `ArgumentError` | A value of the wrong length (a key, seed or ciphertext), a context longer than 255 bytes, a non-positive length. |
| `StateError` | A `SecretBytes` used after `dispose()`. |

Signature verification never throws for bad input; it answers `false`. KEM
decapsulation of a ciphertext made for another key does not throw either; it
answers an unrelated secret.

## Limits

- **One parameter set each:** ML-KEM-768 and ML-DSA-65 only; no HashML-DSA.
- **No symmetric encryption:** the KEMs produce a shared secret, which the
  caller feeds to a cipher.
- **Side channels:** the post-quantum code is the vendored libraries'
  portable C, compiled as their authors wrote it (no assembly back ends);
  Tom PQC makes no side-channel claim of its own beyond it.
- **Copies are the caller's:** `extractBytes()` copies a secret to the Dart
  heap, and `dispose()` does not overwrite that copy.

## Best Practices

- Store an ML-DSA-65 key as its 32-byte seed and an ML-KEM-768 key as its
  64-byte seed; derive the pair when needed.
- Dispose secrets in a `finally` block, and keep `extractBytes()` copies to a
  minimum.
- Give each use of a signing key its own `context`.
- Check keys received from elsewhere with `MlKem768.isValidPublicKey` before
  encapsulating to them, and confirm a KEM exchange by using the secret (for
  example, a MAC both sides check), since a wrong ciphertext does not fail.
- Prefer the hybrids where interoperability with X-Wing, `age` or RFC 10073
  is needed, or where a fallback to classical security is wanted.
