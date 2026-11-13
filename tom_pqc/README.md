# Tom PQC

Post-quantum cryptography for Dart: **ML-KEM-768** (FIPS 203), the
module-lattice key-encapsulation mechanism at security category 3.

The algorithm runs in vetted, portable C — the PQ Code Package's
[mlkem-native](https://github.com/pq-code-package/mlkem-native), vendored at a
pinned commit — compiled for the target by the package's build hook and
reached through `dart:ffi`. Nothing is downloaded at build time and the
package ships no binaries. `cryptography` and `pointycastle` have no ML-KEM;
this package fills that gap.

ML-DSA-65 (FIPS 204) and the hybrid helpers (X25519 + ML-KEM-768,
Ed25519 + ML-DSA-65) follow in a later release.

## Usage

```dart
import 'package:tom_pqc/tom_pqc.dart';

final receiver = MlKem768.generateKeyPair();
final sent = MlKem768.encapsulate(receiver.publicKey);
final received = MlKem768.decapsulate(sent.ciphertext, receiver.secretKey);
// sent.sharedSecret and received hold the same 32 bytes.

sent.sharedSecret.dispose();
received.dispose();
receiver.dispose();
```

See [`example/tom_pqc_example.dart`](example/tom_pqc_example.dart).

| API | What it does |
| --- | --- |
| `MlKem768.generateKeyPair()` | a key pair from the operating system's generator |
| `MlKem768.keyPairFromSeed(seed)` | the key pair a 64-byte seed (d ‖ z) determines — the compact form `age` stores a key in |
| `MlKem768.generateSeed()` | a fresh 64-byte seed |
| `MlKem768.encapsulate(publicKey)` | a ciphertext and the shared secret it carries; refuses a key that fails FIPS 203's modulus check |
| `MlKem768.decapsulate(ciphertext, secretKey)` | the shared secret; a ciphertext not made for the key yields an unrelated secret (implicit rejection), not an error |
| `MlKem768.isValidPublicKey` / `isValidSecretKey` | FIPS 203's encapsulation- and decapsulation-key checks |
| `SecretBytes` | native memory for secret keys and shared secrets |

Sizes: encapsulation key 1,184 bytes, decapsulation key 2,400, ciphertext
1,088, shared secret 32, seed 64 (`MlKem768.publicKeyLength` and so on).

## Secrets in memory

Secret keys, seeds and shared secrets are `SecretBytes`: native memory, never
the Dart heap unless `extractBytes()` copies them out. `dispose()` overwrites
the buffer and releases it; a `NativeFinalizer` does the same for an object
collected undisposed. Dispose as soon as a secret is no longer needed.

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
  interface (`native/tom_pqc.h`, and `PqcBackend` on the Dart side). The
  vendored mlkem-native is built as one compilation unit with all of its
  symbols `static`, so the library exports nothing but that interface, and
  another C implementation (liboqs, PQClean) can replace it without changing
  the Dart API — provided it passes the same known-answer tests.
- **Portable C only.** mlkem-native's assembly back ends are not vendored.

## Tests

```bash
dart test
```

runs NIST's ACVP known-answer vectors for ML-KEM-768 (key generation,
encapsulation, decapsulation with implicit rejection, and both key checks),
every ML-KEM-768 case of Project Wycheproof (key generation from seeds,
encapsulation including unreduced and wrong-length keys, decapsulation
including malformed, malleable and wrong-length ciphertexts and corrupted
keys), the API's behaviour, and the licence checks.

## Licence

BSD-3-Clause, see [`LICENSE`](LICENSE). The vendored mlkem-native is
Apache-2.0 OR ISC OR MIT, used under MIT; [`THIRD_PARTY.md`](THIRD_PARTY.md)
names the files, their origin and commit.
