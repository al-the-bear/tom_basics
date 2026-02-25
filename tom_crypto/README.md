# Tom Crypto

Cryptographic utilities for secure authentication and data protection.

## Features

- **JWT Tokens** - Token-based authentication with HMAC/RSA signing and encrypted payloads
- **Password Hashing** - Secure password storage using Argon2 algorithm
- **RSA Encryption** - Asymmetric encryption with OAEP padding and digital signatures
- **RSA Key Management** - Key generation, PEM parsing/encoding (PKCS#1 and PKCS#8)

## Getting Started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  tom_crypto: ^1.0.0
```

## Usage

### Password Hashing

```dart
import 'package:tom_crypto/tom_crypto.dart';

// Hash a password
final (hash, spec) = TomPasswordHasher.hashPassword('userPassword123');

// Store both hash and spec in your database
await db.saveUser(passwordHash: hash, hashSpec: spec);

// Verify the password later
if (TomPasswordHasher.verifyPassword('userPassword123', hash, spec)) {
  print('Login successful!');
}
```

### JWT Tokens

```dart
import 'package:tom_crypto/tom_crypto.dart';

// Server: Create a token
final token = TomServerJwtToken(
  {'userId': '123', 'role': 'admin'},
  encryptedData: {'permissions': ['read', 'write', 'delete']},
  expiresIn: Duration(hours: 24),
);
final jwtString = token.getJWT('my-auth-server');

// Client: Parse the token
final clientToken = TomClientJwtToken(jwtString);
print('User ID: ${clientToken.payload?['userId']}');
print('Permissions: ${clientToken.secretData?['permissions']}');
```

### RSA Encryption

```dart
import 'package:tom_crypto/tom_crypto.dart';
import 'dart:convert';
import 'dart:typed_data';

// Generate keys
final secureRandom = RsaKeyHelper.getSecureRandom();
final keyPair = await RsaKeyHelper.computeRSAKeyPair(secureRandom);
final publicKey = keyPair.publicKey as RSAPublicKey;
final privateKey = keyPair.privateKey as RSAPrivateKey;

// Encrypt
final plaintext = utf8.encode('Secret message');
final encrypted = rsaEncrypt(publicKey, Uint8List.fromList(plaintext));

// Decrypt
final decrypted = rsaDecrypt(privateKey, encrypted);
final message = utf8.decode(decrypted);
```

## Core Components

| Component | Purpose | Key Features |
|-----------|---------|--------------|
| `jwt_token.dart` | Token-based authentication | HMAC/RSA signing, encrypted payloads |
| `password_hashing.dart` | Secure password storage | Argon2 algorithm, configurable parameters |
| `rsa_encryption.dart` | Asymmetric encryption | OAEP padding, digital signatures |
| `rsa_tools.dart` | RSA key management | Key generation, PEM parsing/encoding |

## Additional Information

This package is part of the TOM Framework. It depends on:
- `tom_basics` - Basic utilities including exception handling

## License

BSD-3-Clause - See [LICENSE](LICENSE) for details.
