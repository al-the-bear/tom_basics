# Tom PQC

Post-quantum cryptography for Dart:

- **ML-KEM-768** (FIPS 203), the module-lattice key-encapsulation mechanism;
- **ML-DSA-65** (FIPS 204), the module-lattice signature scheme;
- the hybrids built on them: the KEM **MLKEM768-X25519** (X-Wing, the KEM of
  `age` v1.3's post-quantum recipients) and the composite signature
  **ML-DSA-65 + Ed25519** of RFC 10073.

The post-quantum algorithms run in vetted, portable C — the PQ Code
Package's [mlkem-native](https://github.com/pq-code-package/mlkem-native) and
[mldsa-native](https://github.com/pq-code-package/mldsa-native), vendored at
pinned commits — compiled for the target by the package's build hook and
reached through `dart:ffi`. Nothing is downloaded at build time and the
package ships no binaries. The classical halves of the hybrids (X25519,
Ed25519) come from [`cryptography`](https://pub.dev/packages/cryptography).

## Usage

```dart
import 'package:tom_pqc/tom_pqc.dart';

// ML-KEM-768
final receiver = MlKem768.generateKeyPair();
final sent = MlKem768.encapsulate(receiver.publicKey);
final received = MlKem768.decapsulate(sent.ciphertext, receiver.secretKey);
// sent.sharedSecret and received hold the same 32 bytes.

// ML-DSA-65
final signer = MlDsa65.generateKeyPair();
final signature = MlDsa65.sign(message, signer.secretKey);
final valid = MlDsa65.verify(message, signature, signer.publicKey);

// The hybrids (asynchronous: their classical halves are)
final hybrid = await MlKem768X25519.generateKeyPair();
final capsule = await MlKem768X25519.encapsulate(hybrid.publicKey);
final secret = await MlKem768X25519.decapsulate(capsule.ciphertext, hybrid.secretKey);

final composite = await MlDsa65Ed25519.generateKeyPair();
final both = await MlDsa65Ed25519.sign(message, composite.secretKey);
final ok = await MlDsa65Ed25519.verify(message, both, composite.publicKey);

// Overwrite every secret as soon as it is no longer needed.
for (final s in [sent.sharedSecret, received, capsule.sharedSecret, secret]) {
  s.dispose();
}
receiver.dispose();
signer.dispose();
hybrid.dispose();
composite.dispose();
```

See [`example/tom_pqc_example.dart`](example/tom_pqc_example.dart).

| API | What it does |
| --- | --- |
| `MlKem768` | key pairs (also from a 64-byte seed d ‖ z), `encapsulate`, `decapsulate`, FIPS 203's key checks; a ciphertext not made for the key yields an unrelated secret (implicit rejection), not an error |
| `MlDsa65` | key pairs from a 32-byte seed (the interoperable private key) or an expanded key, hedged `sign` with a context of up to 255 bytes, `verify`; HashML-DSA is not offered |
| `MlKem768X25519` | X-Wing: a 32-byte secret key (a seed), 1,216-byte public key, 1,120-byte ciphertext; the shared secret is SHA3-256 of both shared secrets, the X25519 ciphertext and public key, and the label; a low-order X25519 share is refused |
| `MlDsa65Ed25519` | RFC 10073 `id-MLDSA65-Ed25519-SHA512`: a 64-byte secret key (two seeds), 1,984-byte public key, 3,373-byte signature over `Prefix ‖ Label ‖ len(ctx) ‖ ctx ‖ SHA-512(M)`, valid only when both halves verify |
| `Sha3` | SHA3-256 and SHAKE256 (FIPS 202) |
| `SecretBytes` | native memory for secret keys, seeds and shared secrets |

Sizes: ML-KEM-768 encapsulation key 1,184 bytes, decapsulation key 2,400,
ciphertext 1,088, shared secret 32; ML-DSA-65 public key 1,952, expanded
secret key 4,032, signature 3,309, seed 32 (the classes' `…Length`
constants).

## Secrets in memory

Secret keys, seeds and shared secrets are `SecretBytes`: native memory, never
the Dart heap unless `extractBytes()` copies them out. `dispose()` overwrites
the buffer and releases it; a `NativeFinalizer` does the same for an object
collected undisposed. Dispose as soon as a secret is no longer needed. The
classical halves of the hybrids run in `package:cryptography`, so their key
bytes pass the Dart heap briefly and are overwritten after use.

## Platforms

The build hook compiles the C code with the platform's C compiler (clang,
gcc or MSVC, found by `native_toolchain_c`) for the target of the build. The
library is bundled by `dart test` / `dart run`, by `dart build cli` (in the
bundle's `lib/`) and by Flutter desktop release builds, verified on macOS
arm64, Linux x64 and Windows x64. The random bytes come from the operating
system: `SecRandomCopyBytes` on macOS, `getrandom` on Linux,
`BCryptGenRandom` on Windows. iOS and Android are not built yet.

## Design

- **A backend interface.** The Dart API calls the C code only through a small
  interface (`native/tom_pqc.h`, and `PqcBackend` on the Dart side); the
  hybrids are built on the Dart API, never on a C library directly. Each
  vendored library is built as one compilation unit with all of its symbols
  `static`, so the native library exports nothing but that interface, and
  another C implementation (liboqs, PQClean) can replace them without
  changing the Dart API — provided it passes the same known-answer tests.
- **Portable C only.** The vendored libraries' assembly back ends are not
  vendored.

## Tests

```bash
dart test
```

runs:

- NIST's ACVP known-answer vectors for ML-KEM-768 (key generation,
  encapsulation, decapsulation, both key checks) and ML-DSA-65 (key
  generation; signing, deterministic and hedged, through the external,
  internal and external-mu interfaces; verification);
- every ML-KEM-768 and ML-DSA-65 case of Project Wycheproof;
- the X-Wing draft's vectors and RFC 10073's composite vector;
- every hybrid file of the age testkit, decrypted through a minimal age
  reader with this package's MLKEM768-X25519;
- a cross-check with Go's `crypto/mlkem`, `crypto/mldsa` and `crypto/hpke`;
- the API's behaviour and the licence checks.

## Licence

BSD-3-Clause, see [`LICENSE`](LICENSE). The vendored mlkem-native and
mldsa-native are Apache-2.0 OR ISC OR MIT, used under MIT;
[`THIRD_PARTY.md`](THIRD_PARTY.md) names the files, their origin and commit,
and the sources of the test vectors.
