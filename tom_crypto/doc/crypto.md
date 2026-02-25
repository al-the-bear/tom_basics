# TomBase Crypto Module

Comprehensive cryptographic utilities for secure authentication and data protection.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Core Components](#core-components)
  - [JWT Tokens](#jwt-tokens)
  - [Password Hashing](#password-hashing)
  - [RSA Encryption](#rsa-encryption)
  - [RSA Key Management](#rsa-key-management)
- [Usage Examples](#usage-examples)
- [Best Practices](#best-practices)
- [Error Handling](#error-handling)

---

## Overview

The crypto module provides a complete set of cryptographic primitives for building secure applications:

| Component | Purpose | Key Features |
|-----------|---------|--------------|
| `jwt_token.dart` | Token-based authentication | HMAC/RSA signing, encrypted payloads |
| `password_hashing.dart` | Secure password storage | Argon2 algorithm, configurable parameters |
| `rsa_encryption.dart` | Asymmetric encryption | OAEP padding, digital signatures |
| `rsa_tools.dart` | RSA key management | Key generation, PEM parsing/encoding |

---

## Quick Start

### Hash a Password

```dart
import 'package:tom_core/tom_core.dart';

// Hash a new password
final (hash, spec) = TomPasswordHasher.hashPassword('userPassword123');

// Store both hash and spec in your database
await db.saveUser(passwordHash: hash, hashSpec: spec);

// Later, verify the password
if (TomPasswordHasher.verifyPassword('userPassword123', hash, spec)) {
  print('Login successful!');
}
```

### Create a JWT Token

```dart
import 'package:tom_core/tom_core.dart';

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

### Encrypt Data with RSA

```dart
import 'package:tom_core/tom_core.dart';
import 'dart:convert';

// Encrypt
final plaintext = utf8.encode('Secret message');
final encrypted = rsaEncrypt(publicKey, Uint8List.fromList(plaintext));

// Decrypt
final decrypted = rsaDecrypt(privateKey, encrypted);
final message = utf8.decode(decrypted);
```

---

## Core Components

### JWT Tokens

JWT (JSON Web Token) support for stateless authentication.

#### TomJwtConfiguration

Holds cryptographic keys and algorithms for JWT operations.

```dart
// Default configuration (development only!)
TomJwtConfiguration.defaultSignConfiguration;

// Custom configuration
final config = TomJwtConfiguration(
  SecretKey('my-production-secret'),
  JWTAlgorithm.HS256,
  productionPrivateKey,
  productionPublicKey,
  false, // Not a dummy configuration
);
```

**Supported Algorithms:**
- HMAC: HS256, HS384, HS512
- RSA: RS256, RS384, RS512, PS256, PS384, PS512

#### TomServerJwtToken

Creates signed JWT tokens on the server.

```dart
final token = TomServerJwtToken(
  {'userId': '123'},              // Public claims
  encryptedData: {'secret': 'x'}, // RSA-encrypted claims
  expiresIn: Duration(hours: 2),  // Token lifetime
  notBefore: Duration(seconds: 0), // Validity delay
);

final jwt = token.getJWT('issuer-name');
```

#### TomClientJwtToken

Parses and decrypts JWT tokens on the client.

```dart
final token = TomClientJwtToken(jwtString);

// Access token properties
print(token.issuer);      // iss claim
print(token.subject);     // sub claim
print(token.payload);     // All public claims
print(token.secretData);  // Decrypted private claims
```

---

### Password Hashing

Secure password hashing using the Argon2 algorithm.

#### Why Argon2?

- **Winner** of the Password Hashing Competition (2015)
- **Memory-hard**: Resists GPU/ASIC attacks
- **Configurable**: Tune for your security/performance needs

#### Hash Format

Passwords are stored in a dual-value format:

```
hash = "salt$hash"      // e.g., "a1b2c3$d4e5f6..."
spec = "Argon2;2i,13,4,65536,4,128"
```

The specification allows future algorithm changes without breaking existing hashes.

#### Configuration

Default parameters (adjustable via static fields):

```dart
TomPasswordHasher.globalSettingDefaultSaltLength = 16;  // 128-bit salt
TomPasswordHasher.globalSettingDefaultHashSpec = "Argon2;2i,13,4,65536,4,128";
```

Specification format: `Argon2;variant,version,iterations,memoryKB,lanes,keyLength`

| Parameter | Default | Description |
|-----------|---------|-------------|
| variant | 2i | Argon2i (side-channel resistant) |
| version | 13 | Version 1.3 |
| iterations | 4 | Time cost |
| memory | 65536 | 64 MB memory |
| lanes | 4 | Parallelism |
| keyLength | 128 | Output size in bytes |

---

### RSA Encryption

Asymmetric encryption for data confidentiality and digital signatures.

#### Encryption/Decryption

Uses OAEP (Optimal Asymmetric Encryption Padding) for security:

```dart
// Encrypt with public key
final encrypted = rsaEncrypt(publicKey, plaintextBytes);

// Decrypt with private key
final decrypted = rsaDecrypt(privateKey, encrypted);
```

#### Digital Signatures

Uses SHA-256 for hashing before signing:

```dart
// Sign with private key
final signature = rsaSign(privateKey, dataBytes);

// Verify with public key
final isValid = rsaVerify(publicKey, dataBytes, signature);
```

---

### RSA Key Management

Comprehensive RSA key handling via `RsaKeyHelper`.

#### Key Generation

```dart
// Generate a secure random source
final random = RsaKeyHelper.getSecureRandom();

// Generate 2048-bit key pair
final keyPair = await RsaKeyHelper.computeRSAKeyPair(random);
final publicKey = keyPair.publicKey as RSAPublicKey;
final privateKey = keyPair.privateKey as RSAPrivateKey;
```

#### PEM Parsing

Supports PKCS#1 and PKCS#8 formats:

```dart
final publicKey = RsaKeyHelper.parsePublicKeyFromPem('''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...
-----END PUBLIC KEY-----
''');

final privateKey = RsaKeyHelper.parsePrivateKeyFromPem('''
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASC...
-----END PRIVATE KEY-----
''');
```

#### PEM Encoding

```dart
final pemPublic = RsaKeyHelper.encodePublicKeyToPemPKCS1(publicKey);
final pemPrivate = RsaKeyHelper.encodePrivateKeyToPemPKCS1(privateKey);
```

---

## Usage Examples

### Complete Authentication Flow

```dart
// 1. User Registration
Future<void> registerUser(String email, String password) async {
  final (hash, spec) = TomPasswordHasher.hashPassword(password);
  await db.createUser(
    email: email,
    passwordHash: hash,
    hashSpec: spec,
  );
}

// 2. User Login
Future<String?> login(String email, String password) async {
  final user = await db.findUserByEmail(email);
  if (user == null) return null;
  
  if (!TomPasswordHasher.verifyPassword(
    password,
    user.passwordHash,
    user.hashSpec,
  )) {
    return null;
  }
  
  // Create JWT token
  final token = TomServerJwtToken(
    {'userId': user.id, 'email': user.email},
    encryptedData: {'roles': user.roles},
    expiresIn: Duration(hours: 24),
  );
  
  return token.getJWT('my-app');
}

// 3. Token Verification (Middleware)
Future<User?> authenticateRequest(String? authHeader) async {
  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    return null;
  }
  
  final token = TomClientJwtToken(authHeader.substring(7));
  final userId = token.payload?['userId'] as String?;
  
  if (userId == null) return null;
  
  return db.findUserById(userId);
}
```

### Secure Data Exchange

```dart
// Sender: Encrypt and sign
Future<Map<String, String>> sendSecureMessage(
  String message,
  RSAPublicKey recipientPublicKey,
  RSAPrivateKey senderPrivateKey,
) async {
  final messageBytes = utf8.encode(message);
  
  // Encrypt with recipient's public key
  final encrypted = rsaEncrypt(recipientPublicKey, Uint8List.fromList(messageBytes));
  
  // Sign with sender's private key
  final signature = rsaSign(senderPrivateKey, Uint8List.fromList(messageBytes));
  
  return {
    'encrypted': base64Encode(encrypted),
    'signature': base64Encode(signature),
  };
}

// Recipient: Verify and decrypt
Future<String?> receiveSecureMessage(
  Map<String, String> data,
  RSAPrivateKey recipientPrivateKey,
  RSAPublicKey senderPublicKey,
) async {
  final encrypted = base64Decode(data['encrypted']!);
  final signature = base64Decode(data['signature']!);
  
  // Decrypt with recipient's private key
  final decrypted = rsaDecrypt(recipientPrivateKey, Uint8List.fromList(encrypted));
  
  // Verify sender's signature
  if (!rsaVerify(senderPublicKey, decrypted, Uint8List.fromList(signature))) {
    return null; // Signature invalid!
  }
  
  return utf8.decode(decrypted);
}
```

---

## Best Practices

### Key Management

1. **Never hardcode production keys** - Use environment variables or secure vaults
2. **Rotate keys regularly** - Implement key rotation policies
3. **Use separate keys** for different purposes (signing vs encryption)
4. **Protect private keys** - Store with restricted permissions

```dart
// ❌ Bad: Hardcoded key
final secretKey = SecretKey('my-secret');

// ✅ Good: Environment variable
final secretKey = SecretKey(Platform.environment['JWT_SECRET']!);
```

### Password Hashing

1. **Always store the spec** alongside the hash for future algorithm changes
2. **Tune parameters** for your hardware (target 0.5-1 second hash time)
3. **Never use** MD5, SHA-1, or plain SHA-256 for passwords

```dart
// ❌ Bad: Hash without spec
db.saveUser(passwordHash: hash);

// ✅ Good: Hash with spec
db.saveUser(passwordHash: hash, hashSpec: spec);
```

### JWT Tokens

1. **Set appropriate expiration** - Shorter for sensitive operations
2. **Use encrypted payloads** for sensitive data
3. **Validate all tokens** server-side
4. **Don't store sensitive data** in unencrypted claims

```dart
// ❌ Bad: Long-lived token with sensitive data in public claims
TomServerJwtToken(
  {'userId': '123', 'creditCard': '4111...'},
  expiresIn: Duration(days: 365),
);

// ✅ Good: Short-lived token with encrypted sensitive data
TomServerJwtToken(
  {'userId': '123'},
  encryptedData: {'creditCard': '4111...'},
  expiresIn: Duration(hours: 1),
);
```

---

## Error Handling

### TomJwtTokenException

Thrown for JWT-related errors:

```dart
try {
  final token = TomClientJwtToken(invalidJwtString);
} on TomJwtTokenException catch (e) {
  print('JWT Error: ${e.defaultUserMessage}');
  print('Error Key: ${e.key}');
}
```

Common error keys:
- `jwt_token.error.decryption_failed` - Failed to decrypt encrypted payload

### Password Hashing Errors

```dart
try {
  TomPasswordHasher.buildKeyDerivator('InvalidSpec');
} catch (e) {
  print('Invalid specification: $e');
}
```

### RSA Signature Verification

Returns `false` instead of throwing for invalid signatures:

```dart
if (!rsaVerify(publicKey, data, signature)) {
  // Handle invalid signature
  throw SecurityException('Signature verification failed');
}
```

---

## Module Structure

```
crypto/
├── crypto.md              # This documentation
├── jwt_token.dart         # JWT token handling
├── password_hashing.dart  # Argon2 password hashing
├── rsa_encryption.dart    # RSA encrypt/decrypt/sign/verify
└── rsa_tools.dart         # RSA key generation and PEM handling
```

---

## Dependencies

This module depends on:

- **Little Things Module**: `TomException` for error handling
- **External**: `pointycastle` package for cryptographic operations
