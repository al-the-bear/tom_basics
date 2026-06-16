# Tom Crypto

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause, see [LICENSE](LICENSE).
> Portions of the RSA key handling are adapted from public examples (see
> [Attribution](#attribution)); those parts retain their original licences.

Cryptographic utilities for secure authentication and data protection including
JWT tokens, password hashing, and RSA encryption.

---

## Overview

`tom_crypto` collects the small set of cryptographic primitives the Tom
framework needs for **authentication** and **confidentiality**, wrapped in a
task-oriented API so callers do not have to assemble PointyCastle engines by
hand. It covers four jobs:

- **Store passwords safely** with Argon2 — the winner of the Password Hashing
  Competition — including salt generation and a self-describing parameter
  string so you can rotate cost factors without invalidating old hashes.
- **Issue and verify JWTs** with HMAC or RSA signing, plus an optional
  RSA-encrypted payload section for claims that must stay secret from the
  bearer.
- **Encrypt and sign arbitrary bytes** with RSA-OAEP and RSA-SHA-256,
  block-chunked so payloads larger than one RSA block just work.
- **Generate and (de)serialise RSA keys** to and from PEM (PKCS#1 and PKCS#8),
  with 2048-bit key generation backed by a Fortuna CSPRNG.

Everything is plain Dart (no Flutter dependency), runs on the server and in
command-line tools, and builds on [`pointycastle`](https://pub.dev/packages/pointycastle),
[`asn1lib`](https://pub.dev/packages/asn1lib), and
[`dart_jsonwebtoken`](https://pub.dev/packages/dart_jsonwebtoken).

> **Read the [Security notes](#security-notes) before shipping.** This package
> gives you correct primitives, but using them safely (key storage, dummy-key
> replacement, cost tuning) is the caller's responsibility, and the defaults
> are tuned for development, not production secrets.

---

## Installation

```yaml
dependencies:
  tom_crypto: ^1.0.1
```

or from the command line:

```bash
dart pub add tom_crypto
```

Requires the Dart SDK `^3.10.0` (records and patterns are used in the password
API). Pure Dart — works in server apps, CLI tools, and Flutter alike.

When you work directly with RSA key objects (`RSAPublicKey`, `RSAPrivateKey`,
`AsymmetricKeyPair`) you also import the types from PointyCastle, which
`tom_crypto` does not re-export:

```dart
import 'package:tom_crypto/tom_crypto.dart';
import 'package:pointycastle/export.dart';
```

---

## Features

### Password hashing — `TomPasswordHasher`

| Capability | API | Notes |
| ---------- | --- | ----- |
| Hash a password | `hashPassword(password)` → `(hash, spec)` | Random per-password salt; returns a record |
| Verify a password | `verifyPassword(password, hash, spec)` | Re-derives with the stored spec/salt |
| Generate a salt | `generateSalt(length)` | Hex string from `Random.secure()` |
| Build a derivator | `buildKeyDerivator([spec, salt])` | Lower-level Argon2 access |
| Tune defaults | `globalSettingDefaultHashSpec`, `globalSettingDefaultSaltLength` | Process-wide cost factors |

### JWT tokens — `TomServerJwtToken` / `TomClientJwtToken`

| Capability | API | Notes |
| ---------- | --- | ----- |
| Issue a signed token | `TomServerJwtToken(public, …).getJWT(issuer)` | HMAC (default) or RSA signing |
| Encrypt sensitive claims | `encryptedData:` constructor argument | RSA-OAEP encrypted `encrypted` claim |
| Parse a token | `TomClientJwtToken(jwt)` | Decodes claims, auto-decrypts secrets |
| Read public claims | `.payload`, `.issuer`, `.subject`, `.audience`, `.jwtId` | Standard JWT accessors |
| Read decrypted claims | `.secretData` | Populated when `decrypt: true` |
| Configure keys/algorithm | `TomJwtConfiguration(...)`, `defaultSignConfiguration` | Swap dummy keys for production keys |

### RSA encryption & signatures — top-level functions

| Capability | API | Notes |
| ---------- | --- | ----- |
| Encrypt bytes | `rsaEncrypt(publicKey, bytes)` | OAEP padding, block-chunked |
| Decrypt bytes | `rsaDecrypt(privateKey, cipher)` | OAEP padding, block-chunked |
| Sign bytes | `rsaSign(privateKey, bytes)` | SHA-256 digest |
| Verify a signature | `rsaVerify(publicKey, data, sig)` | Returns `false` on tampered input |

### RSA key management — `RsaKeyHelper`

| Capability | API | Notes |
| ---------- | --- | ----- |
| Seed a CSPRNG | `getSecureRandom()` | Fortuna, seeded from `Random.secure()` |
| Generate a key pair | `computeRSAKeyPair(random)` | 2048-bit, exponent 65537 |
| Parse a public key | `parsePublicKeyFromPem(pem)` | PKCS#1 and PKCS#8 auto-detected |
| Parse a private key | `parsePrivateKeyFromPem(pem)` | PKCS#1 and PKCS#8 auto-detected |
| Encode a public key | `encodePublicKeyToPemPKCS1(key)` | PEM output |
| Encode a private key | `encodePrivateKeyToPemPKCS1(key)` | PEM output |
| Sign a string | `sign(plainText, privateKey)` | Base64 SHA-256 signature |

---

## Quick start

Hash a password, then verify it — the single most common use of this package:

```dart
import 'package:tom_crypto/tom_crypto.dart';

void main() {
  // Hash a new password. You get back the hash and the spec that produced it.
  final (hash, spec) = TomPasswordHasher.hashPassword('correct horse battery');

  print('spec : $spec');
  print('hash : ${hash.substring(0, 24)}…'); // salt$hash, hex-encoded

  // Store BOTH `hash` and `spec` in your database, then later:
  final good = TomPasswordHasher.verifyPassword('correct horse battery', hash, spec);
  final bad = TomPasswordHasher.verifyPassword('wrong password', hash, spec);

  print('correct password valid? $good');
  print('wrong   password valid? $bad');
}
```

Output (the hash differs every run because the salt is random):

```text
spec : Argon2;2i,13,4,65536,4,128
hash : 7f3c…$a91b…
correct password valid? true
wrong   password valid? false
```

The `spec` string is self-describing
(`Argon2;variant,version,iterations,memory,lanes,keyLength`), so verification
needs nothing but the values you already stored.

---

## Example projects

| Example | What it shows |
| ------- | ------------- |
| [Quick start](#quick-start) | Hash and verify a password |
| [Password hashing](#password-hashing) | Storage format and cost tuning |
| [JWT tokens](#jwt-tokens) | Issue, encrypt, parse, and read claims |
| [RSA encryption](#rsa-encryption) | Generate keys, encrypt, decrypt |
| [Digital signatures](#digital-signatures) | Sign data and verify integrity |
| [Working with PEM keys](#working-with-pem-keys) | Parse and encode PEM |

> A runnable `example/` program is tracked as a follow-up in the cli_tools
> quest; for now the snippets below are each self-contained and copy-paste
> runnable.

---

## Usage

### Password hashing

`hashPassword` returns a `(hash, spec)` record. **Persist both.** The `hash` is
`salt$hash` (both hex), and the `spec` carries every parameter `verifyPassword`
needs to re-derive the key — so you can change the global defaults later without
breaking existing accounts.

```dart
final (hash, spec) = TomPasswordHasher.hashPassword('userPassword123');
// user.passwordHash = hash;
// user.hashSpec     = spec;

final ok = TomPasswordHasher.verifyPassword('userPassword123', hash, spec);
```

The default spec is `Argon2;2i,13,4,65536,4,128` — Argon2i, version 1.3, 4
iterations, 64 MB of memory, 4 lanes, 128-byte output. To raise the cost for new
hashes (existing hashes keep verifying against their own stored spec):

```dart
// 6 iterations, 128 MB memory — slower, stronger.
TomPasswordHasher.globalSettingDefaultHashSpec = 'Argon2;2i,13,6,131072,4,128';
```

Tune these on the hardware that will run the verification so a login stays
comfortably under your latency budget.

### JWT tokens

The **server** issues a token; the **client** parses it. Public claims live in
the payload visible to anyone holding the token. Anything you pass via
`encryptedData` is RSA-encrypted into a single `encrypted` claim and only
recovers on a holder that owns the matching private key.

```dart
// --- Server side ---
final token = TomServerJwtToken(
  {'userId': '123', 'role': 'admin'},        // public claims
  encryptedData: {'sessionSecret': 'abc123'}, // RSA-encrypted claim
  expiresIn: const Duration(hours: 24),
);
final jwtString = token.getJWT('my-auth-server');

// --- Client side ---
final parsed = TomClientJwtToken(jwtString);
print(parsed.issuer);                       // my-auth-server
print(parsed.payload?['userId']);           // 123
print(parsed.secretData?['sessionSecret']); // abc123  (decrypted)
```

Skip decryption when you only need the public claims (and have no private key):

```dart
final parsed = TomClientJwtToken(jwtString, decrypt: false);
```

Signing and encryption keys come from a `TomJwtConfiguration`. The bundled
`TomJwtConfiguration.defaultSignConfiguration` uses **development keys** and
logs a warning every time it encrypts or decrypts. Replace it once, at startup,
with your real keys:

```dart
TomJwtConfiguration.defaultSignConfiguration = TomJwtConfiguration(
  SecretKey(myHmacSecret),     // from package:dart_jsonwebtoken
  JWTAlgorithm.HS256,
  myRsaPrivateKey,
  myRsaPublicKey,
  false,                       // isDummy = false → no warning
);
```

### RSA encryption

Generate a 2048-bit key pair, then encrypt and decrypt bytes with OAEP padding.
Inputs larger than one RSA block are chunked automatically.

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:tom_crypto/tom_crypto.dart';
import 'package:pointycastle/export.dart';

Future<void> main() async {
  final random = RsaKeyHelper.getSecureRandom();
  final pair = await RsaKeyHelper.computeRSAKeyPair(random);
  final publicKey = pair.publicKey as RSAPublicKey;
  final privateKey = pair.privateKey as RSAPrivateKey;

  final plaintext = Uint8List.fromList(utf8.encode('Secret message'));
  final cipher = rsaEncrypt(publicKey, plaintext);
  final recovered = rsaDecrypt(privateKey, cipher);

  print(utf8.decode(recovered)); // Secret message
}
```

> RSA is for small payloads (keys, tokens, short secrets). For bulk data,
> encrypt the data with a symmetric cipher and use RSA only to wrap the
> symmetric key.

### Digital signatures

Sign bytes with the private key; verify with the public key. `rsaVerify`
returns `false` for tampered data rather than throwing.

```dart
final data = Uint8List.fromList(utf8.encode('Important message'));
final signature = rsaSign(privateKey, data);

final ok = rsaVerify(publicKey, data, signature);          // true
final tampered = rsaVerify(publicKey, otherData, signature); // false
```

For a string convenience that returns a base64 signature, use
`RsaKeyHelper.sign(plainText, privateKey)`.

### Working with PEM keys

Parse keys from PEM (PKCS#1 or PKCS#8 — the format is auto-detected) and encode
them back out:

```dart
final publicKey = RsaKeyHelper.parsePublicKeyFromPem(pemPublicString);
final privateKey = RsaKeyHelper.parsePrivateKeyFromPem(pemPrivateString);

final pemPublic = RsaKeyHelper.encodePublicKeyToPemPKCS1(publicKey);
final pemPrivate = RsaKeyHelper.encodePrivateKeyToPemPKCS1(privateKey);
```

---

## Architecture

```text
package:tom_crypto/tom_crypto.dart   (single export surface)
│
├── password_hashing.dart   TomPasswordHasher          → Argon2 (pointycastle)
│
├── jwt_token.dart          TomServerJwtToken          → dart_jsonwebtoken
│                           TomClientJwtToken            + rsa_encryption
│                           TomJwtConfiguration
│                           TomJwtTokenException        → tom_basics
│
├── rsa_encryption.dart     rsaEncrypt / rsaDecrypt     → pointycastle
│                           rsaSign   / rsaVerify          (OAEP, RSA-SHA256)
│
└── rsa_tools.dart          RsaKeyHelper                → pointycastle + asn1lib
                            getRsaKeyPair (top-level)      (key gen, PEM I/O)
```

| Type / function | Role |
| --------------- | ---- |
| `TomPasswordHasher` | Argon2 password hashing and verification |
| `TomServerJwtToken` | Issues signed (and optionally encrypted) JWTs |
| `TomClientJwtToken` | Decodes and decrypts JWTs, exposes claims |
| `TomJwtConfiguration` | Holds signing/encryption keys and algorithm |
| `TomJwtTokenException` | `TomBaseException` raised on JWT failures |
| `rsaEncrypt` / `rsaDecrypt` | RSA-OAEP byte encryption |
| `rsaSign` / `rsaVerify` | RSA-SHA-256 signatures |
| `RsaKeyHelper` | Key generation and PEM parse/encode |

The JWT layer is the only part that reaches into `tom_basics` (for
`TomBaseException` and `tomLog`); the password and RSA layers depend only on
`pointycastle` and `asn1lib`.

---

## Security notes

This package provides correct primitives. Using them safely is on you — these
are the caveats that matter most:

- **Replace the development keys.** `TomJwtConfiguration.defaultSignConfiguration`
  ships with hard-coded HMAC and RSA keys (flagged in `false_secrets:`) purely
  so examples run. They are public — anyone can forge tokens against them. Set
  your own configuration with `isDummy: false` before issuing real tokens.
- **Store the hash *and* the spec together.** `verifyPassword` cannot work
  without the spec that produced the hash. Tune cost factors
  (`globalSettingDefaultHashSpec`) on production hardware; the defaults target
  development convenience, not a hostile attacker.
- **Don't log token contents in production.** `TomClientJwtToken.toString()`
  includes the full payload and decrypted secrets by default. Set
  `TomClientJwtToken.globalSettingShowContentInToString = false` in production.
- **Public claims are not secret.** Anything in `publicData` is base64 — readable
  by anyone holding the token. Only `encryptedData` is confidential, and only
  while the RSA private key stays private.
- **Use RSA for small payloads.** Encrypt bulk data with a symmetric cipher and
  wrap only the symmetric key with RSA. Keys are generated at 2048 bits with
  public exponent 65537 — the industry-standard minimum.
- **Verify, then trust.** `rsaVerify` returns `false` (it does not throw) on a
  modified signature; always check the boolean before acting on signed data.

---

## Ecosystem

`tom_crypto` is one of the foundational packages under
[`tom_ai/basics/`](../). It pairs naturally with:

- **[tom_basics](../tom_basics/)** — exceptions (`TomBaseException`) and logging
  (`tomLog`) used by the JWT layer (direct dependency).
- **[tom_basics_network](../tom_basics_network/)** — HTTP/transport helpers that
  carry the JWTs this package issues.

All `tom_ai/basics/` packages share a single repository,
[`tom_basics`](https://github.com/al-the-bear/tom_basics).

---

## Attribution

The RSA key generation and PEM parsing in `rsa_tools.dart` are adapted from the
public example at
[flutter_rsa_generator_example](https://github.com/Vanethos/flutter_rsa_generator_example/);
those portions retain their original licensing. The remainder of the package is
BSD-3-Clause as in [LICENSE](LICENSE).

---

## Further documentation

- [LICENSE](LICENSE) — BSD-3-Clause licence text.
- Source library docs — every public type and function in `lib/src/` carries
  dartdoc comments with usage examples.
- [`pointycastle`](https://pub.dev/packages/pointycastle),
  [`asn1lib`](https://pub.dev/packages/asn1lib),
  [`dart_jsonwebtoken`](https://pub.dev/packages/dart_jsonwebtoken) — the
  underlying cryptographic libraries.

---

## Status

Stable (`1.0.1`). Public API covers password hashing, JWT issuance/parsing, RSA
encryption/signatures, and RSA key management. `dart analyze` is clean. A
runnable `example/` program is tracked as a follow-up in the cli_tools quest.
