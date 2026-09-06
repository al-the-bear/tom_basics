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
export 'src/secure_bytes.dart';

// The types below belong to this package's dependencies but appear in *this*
// package's public API, so a consumer that cannot name them cannot use the API
// that mentions them. Every one of the four positional parameters of
// `TomJwtConfiguration`'s constructor had this problem, which made the class
// impossible to construct from outside — including in the way its own dartdoc
// documents.
//
// The lists are deliberately narrow: exactly the names this package's own
// surface mentions, and no more. Both packages declare an `RSAPrivateKey` and
// an `RSAPublicKey`, so exporting either one wholesale would hand every
// consumer an ambiguous name. The pointycastle pair wins because it is what
// `TomJwtConfiguration.rsaPrivateKey`/`rsaPublicKey` are and what
// `RsaKeyHelper.parsePrivateKeyFromPem` returns. A consumer who needs
// dart_jsonwebtoken's own RSA/EC/EdDSA *signing* keys — which this package's
// surface never names — imports that package directly.
export 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart'
    show Audience, JWT, JWTAlgorithm, JWTKey, SecretKey;
export 'package:pointycastle/asymmetric/api.dart'
    show RSAPrivateKey, RSAPublicKey;
