# tom_crypto — Authentication & Encryption Sample

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause.

A runnable, article-grade walkthrough of [`tom_crypto`](../../tom_crypto/), the
library that handles the three cryptographic chores almost every backend needs:
**storing passwords safely**, **issuing and verifying JWT credentials**, and
**RSA encryption / signing**. Each is a place where a hand-rolled shortcut turns
into a security incident, so `tom_crypto` wraps battle-tested primitives
(Argon2, HMAC/RSA-signed JWTs, OAEP) behind a small, hard-to-misuse surface.

Every example here is **deterministic and offline** — no key servers, no clock
dependence in the assertions, no network. Cryptographic output is random by
design (salts, OAEP padding, generated keys), so the examples assert the things
that *are* stable — does verification succeed, does the round trip recover the
input, is the modulus 2048 bits — and never print the random bytes. That is what
lets the whole set run in CI and be checked line by line.

> **Read the `tom_crypto` module manual first.** This README assumes you have
> skimmed [`tom_ai/basics/tom_crypto/README.md`](../../tom_crypto/README.md),
> which documents the full API. Here we re-derive only what the examples need
> and spend the words on *why* each primitive is shaped the way it is.

> **Pairs with** the other `tom_basics_samples` walkthroughs. The
> [samples index](../README.md) lists them; each follows the same shape — a
> handful of one-concept example files plus a single aggregator that runs them
> all.

---

## The problem: three chores you must not improvise

Three recurring tasks in any authenticated system are exactly the tasks where
naïve code is dangerous:

1. **Passwords.** Storing them in plaintext — or behind a fast hash like MD5/SHA
   — means a database leak is an instant account-takeover of every user. The fix
   is a *slow, salted, memory-hard* hash so that even with the database an
   attacker cannot feasibly reverse it.
2. **Tokens.** After login you need a credential the client can carry and any
   service can check without a database round trip. A JWT is that credential —
   *if* it is signed, so it cannot be forged, and *if* sensitive fields are
   encrypted, so a stolen token does not leak them.
3. **Asymmetric crypto.** Sometimes you must let anyone send you a secret (public
   key encrypts, private key decrypts) or prove a payload came from you (private
   key signs, public key verifies). Getting the padding and block handling right
   is fiddly and security-critical.

`tom_crypto` gives each chore one obvious entry point:

| Chore | API | Primitive |
|-------|-----|-----------|
| Hash & verify a password | `TomPasswordHasher.hashPassword` / `verifyPassword` | Argon2id-family (Argon2i default) |
| Issue & read a JWT | `TomServerJwtToken` / `TomClientJwtToken` | HMAC (HS256) or RSA signing |
| Verify a JWT signature | `JWT.verify` (`dart_jsonwebtoken`) | HS256 over a shared secret |
| Encrypt / decrypt | `rsaEncrypt` / `rsaDecrypt` | RSA-OAEP |
| Sign / verify | `rsaSign` / `rsaVerify` | RSA + SHA-256 |
| Generate & store keys | `RsaKeyHelper` | 2048-bit RSA, PEM (PKCS#1/#8) |

---

## What you will learn

| # | Example | Concept |
|---|---------|---------|
| 1 | [`01_hashing_a_password`](example/01_hashing_a_password_example.dart) | `hashPassword` / `verifyPassword`; salts make equal passwords hash differently |
| 2 | [`02_the_hash_specification`](example/02_the_hash_specification_example.dart) | The `salt$hash` + spec storage contract; the spec is part of the credential |
| 3 | [`03_issuing_and_reading_a_jwt`](example/03_issuing_and_reading_a_jwt_example.dart) | `TomServerJwtToken` issues, `TomClientJwtToken` reads public claims |
| 4 | [`04_verifying_a_jwt_signature`](example/04_verifying_a_jwt_signature_example.dart) | `JWT.verify` accepts the right key, rejects the wrong one; decode ≠ verify |
| 5 | [`05_encrypted_jwt_payload`](example/05_encrypted_jwt_payload_example.dart) | RSA-encrypted `encryptedData` section; `secretData` on decrypt |
| 6 | [`06_rsa_encrypt_decrypt`](example/06_rsa_encrypt_decrypt_example.dart) | `rsaEncrypt` / `rsaDecrypt`; OAEP is randomized but round-trips |
| 7 | [`07_rsa_signatures_and_keygen`](example/07_rsa_signatures_and_keygen_example.dart) | `rsaSign` / `rsaVerify`; key generation and PEM round trip |

---

## Quick start

```bash
cd tom_ai/basics/tom_basics_samples/tom_crypto_sample
dart pub get

# Run a single concept:
dart run example/01_hashing_a_password_example.dart

# Run all seven in order, with a pass/fail tally:
dart run example/run_all_examples.dart
```

The aggregator prints each example's output under a header and ends with a
tally; it exits non-zero if any example throws — the single command CI needs:

```text
----------------------------------------
7 passed, 0 failed
```

---

## Layout

| Path | What it is |
|------|------------|
| [`example/01..07_*.dart`](example/) | One concept per file, each ending in a verbatim `// expected output` block |
| [`example/run_all_examples.dart`](example/run_all_examples.dart) | Aggregator: runs all seven, tallies, throws on failure |
| [`pubspec.yaml`](pubspec.yaml) | `publish_to: none`; path dep on `../../tom_crypto`, plus `dart_jsonwebtoken` and `pointycastle` for the types `tom_crypto` takes but does not re-export |

---

## Walkthrough

### Example 1 — Hashing a password

Never store a password — store a one-way hash, and verify by re-hashing the
attempt. `tom_crypto` uses **Argon2**, the Password Hashing Competition winner:
deliberately slow and memory-hungry so brute-forcing is expensive.
[`hashPassword`](../../tom_crypto/lib/src/password_hashing.dart) returns a record
`(hash, spec)` — you store both.

```dart
final (hash, spec) = TomPasswordHasher.hashPassword(password);
print('verify correct: ${TomPasswordHasher.verifyPassword(password, hash, spec)}');
print('verify wrong:   ${TomPasswordHasher.verifyPassword('wrong password', hash, spec)}');
```

```text
hash has salt$hash shape: true
spec: Argon2;2i,13,4,65536,4,128
verify correct: true
verify wrong:   false
two hashes differ: true
both verify: true
```

The last two lines carry the key insight: each hash uses a **fresh random salt**,
so hashing the same password twice produces two different strings — both of which
still verify. This is why you can never compare password hashes for equality; you
must always run `verifyPassword`, which extracts the salt from the stored hash and
re-derives. The salt is what defeats precomputed "rainbow table" attacks.

### Example 2 — The hash specification

A stored credential is three things working together: a **salt**, a **hash**, and
a **spec**. The salt and hash live in one string as `salt$hash` (both hex); the
spec — `Argon2;variant,version,iterations,memory,lanes,keyLength` — is a separate
field recording *how* the hash was made.

```dart
final parts = hash.split(r'$');
print('salt hex length: ${parts[0].length}');   // 16 bytes -> 32 hex chars

const tamperedSpec = 'Argon2;2i,13,2,65536,4,128'; // 2 iterations, not 4
print('verify, correct spec:  ${TomPasswordHasher.verifyPassword(password, hash, spec)}');
print('verify, tampered spec: ${TomPasswordHasher.verifyPassword(password, hash, tamperedSpec)}');
```

```text
hash parts: 2
salt hex length: 32
spec: Argon2;2i,13,4,65536,4,128
verify, correct spec: true
verify, tampered spec: false
toHexString([0,10,255]): 000aff
round-trips: [0, 10, 255]
```

Verifying with the wrong spec fails because different parameters derive a
different key — the spec is genuinely *part of* the credential, not metadata. That
is also what makes upgrades safe: when you later raise the iteration count, old
hashes keep verifying against their stored (old) spec while new hashes use the new
one. The format rests on the `toHexString` / `toUint8List` helpers, shown here
round-tripping `[0, 10, 255]` ↔ `000aff`.

### Example 3 — Issuing and reading a JWT

A JWT is a signed, self-describing credential. `tom_crypto` separates the roles:
[`TomServerJwtToken`](../../tom_crypto/lib/src/jwt_token.dart) *issues* on the
server, [`TomClientJwtToken`](../../tom_crypto/lib/src/jwt_token.dart) *reads* on
the client.

```dart
final jwtString = TomServerJwtToken(
  {'userId': 'u-123', 'role': 'admin'},
  expiresIn: const Duration(hours: 1),
).getJWT('tom-auth');

final client = TomClientJwtToken(jwtString);
print('issuer: ${client.issuer}');
print('role:   ${client.payload?['role']}');
```

```text
token segments: 3
issuer: tom-auth
userId: u-123
role:   admin
has validUntil claim: true
secretData: null
```

A JWT is three base64url segments — `header.payload.signature` — which is why
`split('.').length` is 3. The library also stamps a `validUntil` / `validFrom`
window into the public payload. With no encrypted section added, `secretData` is
`null` (example 5 fills it). Note the token string itself is *not* printed: it
embeds `iat`/`exp` timestamps that change every run.

### Example 4 — Verifying a JWT signature

Decoding a token reads its claims; it does **not** prove authenticity — anyone can
write JSON. Trust comes from the **signature**, which only a holder of the signing
key can produce. `tom_crypto` signs with the key in
[`TomJwtConfiguration`](../../tom_crypto/lib/src/jwt_token.dart) (HS256 over a
shared secret); verification is `dart_jsonwebtoken`'s `JWT.verify`.

```dart
final verified = JWT.verify(token, TomJwtConfiguration.hmacKey);   // ok
try {
  JWT.verify(token, SecretKey('attacker-guess'));                  // throws
} on JWTException catch (e) {
  print('wrong key rejected: ${e.message}');
}
final decoded = JWT.decode(token);   // reads claims, skips the signature check
```

```text
verified issuer: tom-auth
wrong key rejected: invalid signature
decode ignores signature: tom-auth
```

The rule to internalise: **decode to read, verify to trust.** `JWT.decode` will
happily parse a token signed by anyone (it is how `TomClientJwtToken` reads
claims), so a service that makes authorization decisions must call `JWT.verify`
with the real secret. A wrong key yields `JWTInvalidException('invalid
signature')`.

### Example 5 — An encrypted JWT payload

JWT claims are only *encoded*, not encrypted — a stolen token leaks every claim.
For sensitive fields, `tom_crypto` adds an **encrypted section**: anything passed
as `encryptedData` is RSA-encrypted into a single opaque `encrypted` claim,
recoverable only with the private key.

```dart
final config = TomJwtConfiguration(
  TomJwtConfiguration.hmacKey, JWTAlgorithm.HS256,
  TomJwtConfiguration.rsaPrivKey, TomJwtConfiguration.rsaPubKey,
  false, // not a dummy configuration -> no warning
);

final token = TomServerJwtToken(
  {'userId': 'u-9', 'role': 'user'},
  encryptedData: {'sessionSecret': 's3cr3t', 'scopes': ['read', 'write']},
  signingConfiguration: config,
).getJWT('tom-auth');

final client = TomClientJwtToken(token, signingConfiguration: config);
print('sessionSecret: ${client.secretData?['sessionSecret']}');
```

```text
public has encrypted blob: true
public exposes sessionSecret: false
sessionSecret: s3cr3t
scopes: [read, write]
```

The public payload carries an opaque `encrypted` blob and **never** the plaintext
`sessionSecret`; only a client holding the private key recovers it as
`secretData`. Two practical notes: the example builds a **non-dummy**
`TomJwtConfiguration` from the development keys so the library does not print its
"dummy configuration" warning (the default config is flagged dummy on purpose);
and in production you would replace those development keys with your own.

### Example 6 — RSA encrypt / decrypt

RSA is asymmetric: the **public** key encrypts, only the **private** key
decrypts. That asymmetry is what lets you publish the public key — anyone can send
you a secret, but only you can open it. `tom_crypto` wraps PointyCastle with
**OAEP padding** ([`rsaEncrypt`](../../tom_crypto/lib/src/rsa_encryption.dart) /
`rsaDecrypt`).

```dart
final cipher = rsaEncrypt(pub, bytes);
final recovered = utf8.decode(rsaDecrypt(priv, cipher));

final cipher2 = rsaEncrypt(pub, bytes);          // same plaintext, again
print('ciphertexts differ: ${!_bytesEqual(cipher, cipher2)}');
```

```text
recovered: attack at dawn
round-trips: true
ciphertexts differ: true
second decrypts too: true
cipher length: 256
```

OAEP injects randomness, so encrypting the same plaintext twice gives different
ciphertext — both decrypt to the original. This is a feature: deterministic
encryption leaks whether two ciphertexts hold the same plaintext. A 2048-bit key
emits a fixed **256-byte** ciphertext block, which is why short messages are
padded up to that size (and why RSA is used to wrap symmetric keys, not bulk
data).

### Example 7 — RSA signatures and key management

The flip side of encryption is the **signature**: the private key signs, the
public key verifies, proving authorship and integrity. `tom_crypto` exposes
[`rsaSign`](../../tom_crypto/lib/src/rsa_encryption.dart) / `rsaVerify` (SHA-256
then RSA), and a full key-management surface in
[`RsaKeyHelper`](../../tom_crypto/lib/src/rsa_tools.dart).

```dart
final signature = rsaSign(priv, data);
print('valid signature: ${rsaVerify(pub, data, signature)}');
print('tampered data rejected: ${!rsaVerify(pub, tampered, signature)}');

final pair = await RsaKeyHelper.computeRSAKeyPair(RsaKeyHelper.getSecureRandom());
final genPub = pair.publicKey as RSAPublicKey;
final pem = RsaKeyHelper.encodePublicKeyToPemPKCS1(genPub);
final parsed = RsaKeyHelper.parsePublicKeyFromPem(pem);
print('parsed modulus matches: ${parsed.modulus == genPub.modulus}');
```

```text
valid signature: true
tampered data rejected: true
generated modulus bits: 2048
PEM header present: true
parsed modulus matches: true
generated pair round-trips: true
```

A signature over `release v1.0.0` verifies; the *same* signature against `release
v1.0.1` is rejected, because the SHA-256 hash differs — that is integrity
detection. The second half generates a fresh **2048-bit** pair, round-trips its
public key through PEM text (`encodePublicKeyToPemPKCS1` → `parsePublicKeyFromPem`
yields the same modulus), and proves the generated pair encrypts and decrypts end
to end. PEM is the on-disk/on-wire form you would store or distribute.

---

## How this sample stays deterministic and offline

Cryptographic primitives are *meant* to produce unpredictable output. That is at
odds with a sample whose output must be checked literally — so the examples are
written to assert only the stable facts:

- **Randomness is asserted indirectly.** Salts, OAEP ciphertext, and generated
  keys differ every run, so the examples print *booleans* (does it verify, does it
  round-trip, do two ciphertexts differ) and *sizes* (32 hex salt chars, 256-byte
  cipher block, 2048-bit modulus) — never the random bytes.
- **No clock leaks into assertions.** JWTs embed `iat`/`exp`/`validUntil`, so the
  token string and timestamps are never printed; only stable claims (`issuer`,
  `userId`, `role`) and structure (3 segments) are.
- **No network, no key servers.** Everything runs in-process: Argon2 hashing, JWT
  signing/verifying, RSA with the bundled development keys or a freshly generated
  pair.
- **The dummy-config warning is silenced deliberately.** Example 5 constructs a
  non-dummy `TomJwtConfiguration` so the encrypted round trip does not emit the
  library's development-key warning into the captured output.

The result: `dart run example/run_all_examples.dart` is hermetic and repeatable,
and every `// expected output` block matches byte for byte.

---

## Concept reference

| API | Role | Seen in |
|-----|------|---------|
| `TomPasswordHasher.hashPassword` | Argon2 hash → `(hash, spec)` | 1, 2 |
| `TomPasswordHasher.verifyPassword` | Re-derive and compare | 1, 2 |
| `TomPasswordHasher.toHexString` / `toUint8List` | Hex codec for the storage format | 2 |
| `TomServerJwtToken` | Issue (sign) a token | 3, 4, 5 |
| `TomClientJwtToken` | Read (decode + decrypt) a token | 3, 5 |
| `TomJwtConfiguration` | Signing keys + algorithm; dummy flag | 4, 5 |
| `JWT.verify` / `JWT.decode` (`dart_jsonwebtoken`) | Verify signature vs. read only | 4 |
| `rsaEncrypt` / `rsaDecrypt` | RSA-OAEP confidentiality | 6, 7 |
| `rsaSign` / `rsaVerify` | RSA + SHA-256 integrity | 7 |
| `RsaKeyHelper.computeRSAKeyPair` / `getSecureRandom` | Generate a 2048-bit pair | 7 |
| `RsaKeyHelper.encodePublicKeyToPemPKCS1` / `parsePublicKeyFromPem` | PEM round trip | 7 |

---

## Where to go next

- Read [`tom_ai/basics/tom_crypto/README.md`](../../tom_crypto/README.md) for the
  full API, including PKCS#1 vs PKCS#8 parsing, RSA-signed (RS256) JWTs, and the
  Argon2 variants.
- In production, replace the development keys in `TomJwtConfiguration` with your
  own and construct non-dummy configurations — the examples flag exactly where.
- Browse the [samples index](../README.md) for the other `tom_basics` libraries,
  each with a walkthrough in this same shape.
