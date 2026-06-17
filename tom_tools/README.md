# Tom Tools

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause, see [LICENSE](LICENSE).

Small command-line tools for the Tom framework. Currently an RSA keypair
generator that prints PEM PKCS#1 public and private keys, built on
[`tom_crypto`](../tom_crypto).

---

## Overview

`tom_tools` is a thin home for one-off developer command-line utilities that
don't warrant a package of their own. Today it ships a single tool:

- **`key_generator`** — generate a fresh 2048-bit RSA keypair and print both keys
  in **PEM PKCS#1** form (the `-----BEGIN PUBLIC KEY----- / -----BEGIN PRIVATE
  KEY-----` envelope), ready to paste into a config file, a secret store, or a
  JWT-signing setup.

The heavy lifting is done by [`tom_crypto`](../tom_crypto)'s `RsaKeyHelper`; this
package is just the CLI front-end. If you need to generate keys *inside* your own
Dart code rather than from the command line, call `RsaKeyHelper` directly (see
[Generating keys in Dart code](#generating-keys-in-dart-code)) — you don't need
`tom_tools` for that.

> **The private key is a secret.** `key_generator` prints the **private** key to
> stdout. Redirect it straight into a protected file and never commit it or paste
> it into a shared channel — see [Handling the output](#handling-the-output).

---

## Installation

This is a **workspace-internal** package (`publish_to: none`); it is consumed by
path, not from pub.dev:

```yaml
dependencies:
  tom_tools:
    path: ../../basics/tom_tools
```

It depends (by path) on [`tom_crypto`](../tom_crypto) for `RsaKeyHelper`, plus
`pointycastle` / `asn1lib` / `cryptography` for the underlying RSA primitives.
Requires the Dart SDK `^3.9.2`.

In practice you rarely *depend* on `tom_tools` — you run its tool from a checkout
of the package (see [Running the key generator](#running-the-key-generator)).

---

## Features

| Capability | Entrypoint | Notes |
| ---------- | ---------- | ----- |
| Generate an RSA keypair | `lib/key_generator.dart` (`main`) | Prints PEM PKCS#1 public + private keys to stdout |
| Reuse the generator in code | `tom_crypto`'s `RsaKeyHelper` | The same helper the CLI wraps — call it directly |

---

## Quick start

Run the key generator from a checkout of the package:

```bash
cd tom_ai/basics/tom_tools
dart pub get
dart run lib/key_generator.dart
```

Output — a freshly generated keypair (the key bodies are random on every run, and
abbreviated here with `…`):

```text
Public Key
-----BEGIN PUBLIC KEY-----
MIIBCgKCAQEAhIX014nch7ZGsf0tV5UK/yBwxeIrytl1TC3DKuyTB+homRawwHq…
-----END PUBLIC KEY-----
Private Key
-----BEGIN PRIVATE KEY-----
MIIFowIBAAKCAQEAhIX014nch7ZGsf0tV5UK/yBwxeIrytl1TC3DKuyTB+homRa…
-----END PRIVATE KEY-----
```

Each run produces a brand-new keypair — there is no seed or fixed output.

---

## Usage

### Running the key generator

`key_generator` is a plain `main()` in `lib/key_generator.dart`, so you run it by
file path with `dart run`:

```bash
dart run lib/key_generator.dart
```

It prints two PEM blocks to stdout: the public key first (under the line
`Public Key`), then the private key (under `Private Key`). Both use the **PKCS#1**
envelope produced by `RsaKeyHelper.encodePublicKeyToPemPKCS1` /
`encodePrivateKeyToPemPKCS1`.

### Handling the output

Because the private key is printed to stdout, capture it directly into a
protected file rather than letting it scroll past in a shared terminal:

```bash
# Capture the whole keypair into one file, then restrict it.
dart run lib/key_generator.dart > keypair.pem
chmod 600 keypair.pem        # restrict before anyone else can read it
```

Then split the two PEM blocks into separate files as your tooling needs. **Never
commit the private key** or paste it into chat/issue trackers — treat
`keypair.pem` like any other credential.

### Generating keys in Dart code

If you want a keypair *inside* an application rather than from the command line,
skip `tom_tools` entirely and call `tom_crypto`'s `RsaKeyHelper` directly — it is
exactly what the CLI wraps:

```dart
import 'package:pointycastle/asymmetric/api.dart';
import 'package:tom_crypto/tom_crypto.dart';

Future<void> main() async {
  final keypair =
      await RsaKeyHelper.computeRSAKeyPair(RsaKeyHelper.getSecureRandom());

  final publicPem = RsaKeyHelper.encodePublicKeyToPemPKCS1(
      keypair.publicKey as RSAPublicKey);
  final privatePem = RsaKeyHelper.encodePrivateKeyToPemPKCS1(
      keypair.privateKey as RSAPrivateKey);

  // ... store publicPem / privatePem securely; never log the private key.
}
```

See the [`tom_crypto` README](../tom_crypto) for the full RSA surface —
encryption, signing, and PEM parsing back into key objects.

---

## Architecture

```text
tom_tools  (workspace-internal CLI package)
│
└── lib/key_generator.dart            main(): print PEM PKCS#1 public + private keys
        │
        └── delegates all crypto to
            package:tom_crypto
            └── RsaKeyHelper
                ├── getSecureRandom()              seeded CSPRNG
                ├── computeRSAKeyPair(random)      2048-bit RSA keypair
                ├── encodePublicKeyToPemPKCS1(k)   PEM (PKCS#1) public key
                └── encodePrivateKeyToPemPKCS1(k)  PEM (PKCS#1) private key
```

| File / member | Role |
| ------------- | ---- |
| `lib/key_generator.dart` | The CLI entrypoint — generates a keypair and prints both PEM blocks |
| `RsaKeyHelper` (from `tom_crypto`) | Does the actual key generation and PEM encoding |

`tom_tools` carries no logic of its own beyond wiring stdout to `RsaKeyHelper`; it
is intentionally minimal.

---

## Ecosystem

`tom_tools` is one of the foundational packages under [`tom_ai/basics/`](../). All
`tom_ai/basics/` packages share a single repository,
[`tom_basics`](https://github.com/al-the-bear/tom_basics). It builds directly on
[`tom_crypto`](../tom_crypto), the framework's cryptography library (JWT, password
hashing, RSA), and exists to give that library's RSA keygen a one-command
front-end.

---

## Further documentation

- [LICENSE](LICENSE) — BSD-3-Clause licence text.
- [`tom_crypto`](../tom_crypto) — the cryptography library `key_generator` wraps;
  full RSA / JWT / password-hashing surface.
- [CHANGELOG.md](CHANGELOG.md) — release history.

---

## Status

Stable (`1.0.1`). Workspace-internal (`publish_to: none`), consumed by path. A
deliberately small package: one CLI tool wrapping `tom_crypto`'s `RsaKeyHelper`.
`dart analyze` is clean. The generator runs against the live `tom_crypto` RSA
primitives — every invocation produces a fresh keypair.
