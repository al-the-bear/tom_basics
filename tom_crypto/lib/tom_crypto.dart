/// Cryptographic utilities for secure authentication and data protection.
///
/// This library provides a complete set of cryptographic primitives:
///
/// - **JWT Tokens**: Token-based authentication with HMAC/RSA signing
/// - **Password Hashing**: Secure password storage with Argon2
/// - **RSA Encryption**: Asymmetric encryption with OAEP padding
/// - **RSA Key Management**: Key generation, PEM parsing/encoding
///
/// ## Quick Start
///
/// ```dart
/// import 'package:tom_crypto/tom_crypto.dart';
///
/// // Hash a password
/// final (hash, spec) = TomPasswordHasher.hashPassword('userPassword123');
///
/// // Create a JWT token
/// final token = TomServerJwtToken(
///   {'userId': '123', 'role': 'admin'},
///   encryptedData: {'permissions': ['read', 'write', 'delete']},
///   expiresIn: Duration(hours: 24),
/// );
///
/// // Generate RSA keys
/// final secureRandom = RsaKeyHelper.getSecureRandom();
/// final keyPair = await RsaKeyHelper.computeRSAKeyPair(secureRandom);
/// ```
library;

export 'src/jwt_token.dart';
export 'src/password_hashing.dart';
export 'src/rsa_encryption.dart';
export 'src/rsa_tools.dart';
