/// JWT token generation and verification for TomBase.
///
/// This library provides secure JWT token handling with support for:
/// - HMAC-based token signing (HS256, HS384, HS512)
/// - RSA-based token signing (RS256, RS384, RS512)
/// - Encrypted payload sections for sensitive data
/// - Configurable expiration and validity windows
///
/// ## Usage
///
/// ```dart
/// // Create a server-side token
/// final token = TomServerJwtToken(
///   {'userId': '123', 'role': 'admin'},
///   encryptedData: {'permissions': ['read', 'write']},
///   expiresIn: Duration(hours: 24),
/// );
/// final jwtString = token.getJWT('my-issuer');
///
/// // Parse a client-side token
/// final clientToken = TomClientJwtToken(jwtString);
/// print(clientToken.payload); // Access public claims
/// print(clientToken.secretData); // Access decrypted data
/// ```
library;

// =============================================================================
// Dart SDK Imports
// =============================================================================

import 'dart:convert';

// =============================================================================
// Package Imports
// =============================================================================

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart' as jwt;
import 'package:pointycastle/asymmetric/api.dart';
import 'package:tom_basics/tom_basics.dart';

import 'rsa_encryption.dart';
import 'rsa_tools.dart';

// =============================================================================
// Exceptions
// =============================================================================

/// Exception thrown when JWT token operations fail.
///
/// This includes errors during token creation, signing, decryption,
/// or validation.
///
/// ## Example
///
/// ```dart
/// throw TomJwtTokenException(
///   'jwt_token.error.expired',
///   'The token has expired',
/// );
/// ```
class TomJwtTokenException extends TomBaseException {
  /// Creates a new JWT token exception.
  ///
  /// [key] is the unique error identifier for localization.
  /// [defaultUserMessage] is the human-readable error message.
  TomJwtTokenException(
    super.key,
    super.defaultUserMessage, {
    super.parameters,
    super.stack,
    super.rootException,
    super.uuid,
  });
}

// =============================================================================
// JWT Configuration
// =============================================================================

/// Configuration for JWT token signing and encryption.
///
/// [TomJwtConfiguration] holds the cryptographic keys and algorithms used
/// for signing JWT tokens and encrypting sensitive payload data.
///
/// ## Default Configuration
///
/// The class provides a static [defaultSignConfiguration] using development
/// keys. **These should be replaced in production environments.**
///
/// ## Encryption
///
/// The configuration supports RSA encryption for sensitive data within tokens.
/// Data marked as "encrypted" in the token payload is encrypted with the
/// RSA public key and can only be decrypted with the corresponding private key.
///
/// ## Usage
///
/// ```dart
/// // Create custom configuration
/// final config = TomJwtConfiguration(
///   SecretKey('my-secret'),
///   JWTAlgorithm.HS256,
///   myPrivateKey,
///   myPublicKey,
///   false, // not dummy configuration
/// );
///
/// // Set as default
/// TomJwtConfiguration.defaultSignConfiguration = config;
/// ```
class TomJwtConfiguration {
  // ---------------------------------------------------------------------------
  // Static Keys (Development Only - Replace in Production)
  // ---------------------------------------------------------------------------

  /// HMAC secret key for HS256/HS384/HS512 algorithms.
  ///
  /// **Warning:** This is a development-only key. Replace with a secure,
  /// randomly generated key in production.
  static final hmacKey = jwt.SecretKey('development-passphrase');

  /// RSA private key for RS256/RS384/RS512/PS256/PS384/PS512 algorithms.
  ///
  /// **Warning:** This is a development-only key. Replace with a secure
  /// key pair in production.
  static final rsaPrivKey = RsaKeyHelper.parsePrivateKeyFromPem('''
-----BEGIN PRIVATE KEY-----
MIIFowIBAAKCAQEApobMwJj9SxpZbk0fcG8Awv9PCiO4/GsPimeH398D+Qt1kUrrMqvm5+AYLh1PcIgE/V+QiFTgBv9Fpuu5YtrnF+oi/dg23MUKPA0yXzHjTyshm3P2uhIRN4c6fVru5HF3HXGh5POR1A6kGW9IGbeKhLCG1yyoNDGzHdrdwNEREw3N6KEKAN4swXOMau7rhaRXTkOWTSyPwhAEI+ZrwTnHBIDsVouqPQ0yAX7vTGK1UFNPGmh7itLECj8WgbxgElyrPgtDknmXmfCzrn3DMJeGbuq9dzl0z5DZysrR3nEqIQB8xnDLkkejjnmn1YOflaZMql3mKSJeJ9KxPUZ+u+6DcwKCAQAvUp9dHBze+t3vOnt0uBa/U05i00P+d24zJri2Jeo7G8aNQ30TKUa1HjnA4RNyJzVDy6SHGZeQZXqltNc6AHsrkJ3hBVCR7Gy8JAPsiYDPPrKOOqYiun+qCAPXG8BHqvbupxwatBz85iw8DiOvKzlx+7hV7ZrfOkBse4YJBWCUySF/T+ZVdM3kqoMtfegnGa2AWmGa09qDoCBt1TAHVtNDAu/1UnbvjlHTJ6NFfboibortCRBicmhAu1jcbW6dn9/J9naXlkYxRK22uItXKunv/dqmDQ+lRE9KuKArexYweenHd3yuExuXGOR9XM8vJtgZqTR8WYRDbeWgNQMwXSoBAoIBAC9Sn10cHN763e86e3S4Fr9TTmLTQ/53bjMmuLYl6jsbxo1DfRMpRrUeOcDhE3InNUPLpIcZl5BleqW01zoAeyuQneEFUJHsbLwkA+yJgM8+so46piK6f6oIA9cbwEeq9u6nHBq0HPzmLDwOI68rOXH7uFXtmt86QGx7hgkFYJTJIX9P5lV0zeSqgy196CcZrYBaYZrT2oOgIG3VMAdW00MC7/VSdu+OUdMno0V9uiJuiu0JEGJyaEC7WNxtbp2f38n2dpeWRjFErba4i1cq6e/92qYND6VET0q4oCt7FjB56cd3fK4TG5cY5H1czy8m2BmpNHxZhENt5aA1AzBdKgECgYEA5QjshbsxGUmtMLSFXPn3Y2KW9e2K0r2itb5A2PRB+28aDiFArPmWVhvRujS8KG78NUBwWq/c2c8bET/6j1y0qIsy/2ZBWmoKTSyIbrxybzalMpOWQ5Y37CKypG73EQtigHmuZ6TN0Tr9vkY/q+o+wilVF+EIzcj39WAherAKHwcCgYEAuiHin+jukcxVNKy4bz8dRkHHbmCoCv12fNSihhemfrE/daCWCY1J+VkCrB1a5iuOx6huDAYHXMWl3jjfkvoTX1/YQjhb5f2bMqrHjkyw86k1j6yMdgfO+AG3sqhIz3fszMaVd6UfE7mwwaqE4QfppAJWBvKS9SQaY7KNN2+8cTUCgYB3qPHp7KL6U0Po7me+69oUUq4MTs74y5r22S+IKhVPB/zU5QqlVMD2vBIW9vZXKaUbLU+GEduQ8GNz37lIrWa1qAQ862+5jS1UpK+jK1GeSS6F/hXDuff9pyMuRctPXGNaPDiibbgaWHe5sXoSl4+yYWXT0/6FhToHOPJE5zRigQKBgQCpx2zTFgI+xVZXNNEK0FQgmLGT0eCWHbpthPs2Ou5ok77hyXfyAImgQvu4CRK37rVPEyhGGV2v1q1EdTYh96+iCGfXh1b0A48D+VkLSJMDvq2XfvmkU90KxW5NLUk0zRwXcXA28UvWj0NWc/a+2JvaOTNFJRC9QJA9rkk3btlBnQKBgQCTT4oMD16jRtyxwK+cczzxPX3P4FtZHuppBetUmuq+2xFTvdB/ivUARXcYhibG09+AC1heYtImy+pRXxMPnKXimFFvimJMT4edBq0w2XA33VDoG+xeYM6G0c3bHbk53DTNk+lr4GirKMSe6kYFV3Fo9kmnvW0N9ttLfFQqds+LUg==
-----END PRIVATE KEY-----
''');

  /// RSA public key for token encryption.
  ///
  /// You can also extract the public key from a certificate with
  /// `RSAPublicKey.cert(...)`.
  ///
  /// **Warning:** This is a development-only key. Replace with a secure
  /// key pair in production.
  static final rsaPubKey = RsaKeyHelper.parsePublicKeyFromPem('''
-----BEGIN PUBLIC KEY-----
MIIBCgKCAQEApobMwJj9SxpZbk0fcG8Awv9PCiO4/GsPimeH398D+Qt1kUrrMqvm5+AYLh1PcIgE/V+QiFTgBv9Fpuu5YtrnF+oi/dg23MUKPA0yXzHjTyshm3P2uhIRN4c6fVru5HF3HXGh5POR1A6kGW9IGbeKhLCG1yyoNDGzHdrdwNEREw3N6KEKAN4swXOMau7rhaRXTkOWTSyPwhAEI+ZrwTnHBIDsVouqPQ0yAX7vTGK1UFNPGmh7itLECj8WgbxgElyrPgtDknmXmfCzrn3DMJeGbuq9dzl0z5DZysrR3nEqIQB8xnDLkkejjnmn1YOflaZMql3mKSJeJ9KxPUZ+u+6DcwIDAQAB
-----END PUBLIC KEY-----
''');

  // TODO: check these keys. Maybe remove them.

  /*

// ES256, ES256K, ES384, ES512
  static final ecPrivKey = JWT.ECPrivateKey('''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgevZzL1gdAFr88hb2
...
-----END PRIVATE KEY-----
''');

// You can also extract the public key from a certificate with ECPublicKey.cert(...)
  static final ecPubKey = JWT.ECPublicKey('''
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEEVs/o5+uQbTjL3chynL4wXgUg2R9
...
-----END PUBLIC KEY-----
''');


// EdDSA
  static final edPrivKey = JWT.EdDSAPrivateKey.fromPEM('''-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEICXCjBHvjArjXquUI5jo3x5SHI4ofZA2azwJ39IC/Qct
-----END PRIVATE KEY-----
''');

  static final edPubKey = JWT.EdDSAPublicKey.fromPEM('''-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAEi7MNW0Q9T83UA3Rw+8DbspMgqeuxCqa2wXaWS+tHqY=
-----END PUBLIC KEY-----
''');

   */

  // ---------------------------------------------------------------------------
  // Static Configuration
  // ---------------------------------------------------------------------------

  /// Default signing configuration used by JWT tokens.
  ///
  /// This configuration is used when no explicit configuration is provided
  /// to [TomServerJwtToken] or [TomClientJwtToken].
  ///
  /// **Important:** Replace this with production keys before deployment.
  static TomJwtConfiguration defaultSignConfiguration = TomJwtConfiguration(
    hmacKey,
    jwt.JWTAlgorithm.HS256,
    rsaPrivKey,
    rsaPubKey,
  );

  // ---------------------------------------------------------------------------
  // Instance Fields
  // ---------------------------------------------------------------------------

  /// RSA private key for decrypting encrypted payload sections.
  RSAPrivateKey rsaPrivateKey;

  /// RSA public key for encrypting payload sections.
  RSAPublicKey rsaPublicKey;

  /// Whether this is a dummy/development configuration.
  ///
  /// When true, a warning is logged when encryption/decryption is performed.
  bool isDummy = true;

  /// The secret key used for HMAC-based signing.
  jwt.JWTKey key;

  /// The algorithm used for token signing.
  jwt.JWTAlgorithm algorithm;

  // ---------------------------------------------------------------------------
  // Constructors
  // ---------------------------------------------------------------------------

  /// Creates a new JWT configuration.
  ///
  /// [key] is the secret key for HMAC signing.
  /// [algorithm] is the signing algorithm to use.
  /// [rsaPrivateKey] is the RSA private key for decryption.
  /// [rsaPublicKey] is the RSA public key for encryption.
  /// [isDummy] indicates if this is a development configuration (default: true).
  TomJwtConfiguration(
    this.key,
    this.algorithm,
    this.rsaPrivateKey,
    this.rsaPublicKey, [
    this.isDummy = true,
  ]);

  // ---------------------------------------------------------------------------
  // Encryption Methods
  // ---------------------------------------------------------------------------

  /// Encrypts a string using RSA encryption.
  ///
  /// The input [s] is encrypted using the [rsaPublicKey] and returned as
  /// a base64-encoded string.
  ///
  /// If [isDummy] is true, a warning is logged indicating that development
  /// keys are being used.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final encrypted = config.encrypt(jsonEncode({'secret': 'data'}));
  /// ```
  String encrypt(String s) {
    if (isDummy) {
      // ignore: avoid_print
      print(
        "WARNING: The system is using a dummy encryption configuration. Set proper default configurations in TomJwtConfiguration or use explicitly provided TomJwtConfigurations.",
      );
    }
    return base64Encode(rsaEncrypt(rsaPublicKey, utf8.encode(s)).toList());
  }

  /// Decrypts a base64-encoded RSA-encrypted string.
  ///
  /// The input [s] must be a base64-encoded string that was encrypted
  /// with the corresponding [rsaPublicKey].
  ///
  /// If [isDummy] is true, a warning is logged indicating that development
  /// keys are being used.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final decrypted = config.decrypt(encryptedBase64String);
  /// final data = jsonDecode(decrypted);
  /// ```
  String decrypt(String s) {
    if (isDummy) {
      // ignore: avoid_print
      print(
        "WARNING: The system is using a dummy encryption configuration. Set proper default configurations in TomJwtConfiguration or use explicitly provided TomJwtConfigurations.",
      );
    }
    return utf8.decode(rsaDecrypt(rsaPrivateKey, base64Decode(s)));
  }
}

// =============================================================================
// Server-Side JWT Token
// =============================================================================

/// Server-side JWT token generator.
///
/// [TomServerJwtToken] creates signed JWT tokens with both public and
/// encrypted payload sections. Use this class on the server to generate
/// tokens for client authentication.
///
/// ## Token Structure
///
/// The generated token contains:
/// - **Public claims**: Visible to anyone who can decode the token
/// - **Encrypted claims**: RSA-encrypted, only readable with the private key
/// - **validUntil**: Expiration timestamp
/// - **validFrom**: Start of validity window
///
/// ## Usage
///
/// ```dart
/// final token = TomServerJwtToken(
///   {'userId': '123', 'role': 'user'},
///   encryptedData: {'sessionSecret': 'abc123'},
///   expiresIn: Duration(hours: 24),
/// );
///
/// final jwtString = token.getJWT('my-issuer');
/// // Send jwtString to the client
/// ```
class TomServerJwtToken {
  // ---------------------------------------------------------------------------
  // Instance Fields
  // ---------------------------------------------------------------------------

  /// The signing configuration to use for this token.
  TomJwtConfiguration signingConfiguration =
      TomJwtConfiguration.defaultSignConfiguration;

  /// Public claims visible in the token payload.
  Map<String, Object?> publicData;

  /// Sensitive data that will be RSA-encrypted in the token.
  Map<String, Object?> encryptedData;

  /// How long until the token expires.
  Duration expiresIn;

  /// Delay before the token becomes valid.
  Duration notBefore;

  /// Whether to omit the "issued at" claim.
  bool noIssueAt;

  // ---------------------------------------------------------------------------
  // Constructors
  // ---------------------------------------------------------------------------

  /// Creates a new server-side JWT token.
  ///
  /// [publicData] contains claims visible in the token payload.
  /// [encryptedData] contains sensitive claims that will be RSA-encrypted.
  /// [expiresIn] is how long until the token expires (default: 2 hours).
  /// [notBefore] is the delay before the token becomes valid (default: 0).
  /// [noIssueAt] whether to omit the "iat" claim (default: false).
  /// [signingConfiguration] optional custom configuration for signing.
  TomServerJwtToken(
    this.publicData, {
    this.encryptedData = const {},
    this.expiresIn = const Duration(hours: 2),
    this.notBefore = const Duration(seconds: 0),
    this.noIssueAt = false,
    TomJwtConfiguration? signingConfiguration,
  }) {
    this.signingConfiguration =
        signingConfiguration ?? this.signingConfiguration;
  }

  // ---------------------------------------------------------------------------
  // Token Generation
  // ---------------------------------------------------------------------------

  /// Generates the token payload with public and encrypted data.
  ///
  /// Returns a map containing all public claims plus:
  /// - `encrypted`: RSA-encrypted JSON string of [encryptedData] (if not empty)
  /// - `validUntil`: ISO 8601 expiration timestamp
  /// - `validFrom`: ISO 8601 validity start timestamp
  Map<String, Object?> _generateLoad() {
    Map<String, Object?> load = {};
    load.addAll(publicData);
    if (encryptedData.isNotEmpty) {
      load["encrypted"] = signingConfiguration.encrypt(
        jsonEncode(encryptedData),
      );
    }
    load["validUntil"] = DateTime.now().add(expiresIn).toIso8601String();
    load["validFrom"] = DateTime.now().add(notBefore).toIso8601String();
    return load;
  }

  /// Generates and signs the JWT token string.
  ///
  /// [issuer] is the "iss" claim identifying the token issuer.
  ///
  /// Returns the signed JWT token as a string.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final token = TomServerJwtToken({'userId': '123'});
  /// final jwt = token.getJWT('my-auth-server');
  /// ```
  String getJWT(String issuer) {
    final jwtToken = jwt.JWT(_generateLoad(), issuer: issuer);
    final token = jwtToken.sign(
      signingConfiguration.key,
      algorithm: signingConfiguration.algorithm,
      expiresIn: expiresIn,
      notBefore: notBefore,
      noIssueAt: noIssueAt,
    );
    return token;
  }
}

// =============================================================================
// Client-Side JWT Token
// =============================================================================

/// Client-side JWT token parser and validator.
///
/// [TomClientJwtToken] decodes and optionally decrypts JWT tokens received
/// from a server. Use this class to access token claims and encrypted data.
///
/// ## Token Decryption
///
/// If the token contains an "encrypted" claim, it is automatically decrypted
/// using the configured RSA private key and made available via [secretData].
///
/// ## Usage
///
/// ```dart
/// final token = TomClientJwtToken(jwtString);
/// print(token.issuer);     // Token issuer
/// print(token.payload);    // Public claims
/// print(token.secretData); // Decrypted claims (if any)
/// ```
///
/// ## Disable Decryption
///
/// If you don't need to access encrypted data:
/// ```dart
/// final token = TomClientJwtToken(jwtString, decrypt: false);
/// ```
class TomClientJwtToken {
  // ---------------------------------------------------------------------------
  // Instance Fields
  // ---------------------------------------------------------------------------

  /// Whether to decrypt the "encrypted" payload section.
  final bool decrypt;

  /// The signing configuration used for decryption.
  TomJwtConfiguration signingConfiguration = TomJwtConfiguration.defaultSignConfiguration;

  /// The decoded JWT token.
  late jwt.JWT token;

  /// The original JWT string.
  late String tokenString;

  // ---------------------------------------------------------------------------
  // Computed Properties
  // ---------------------------------------------------------------------------

  /// Decrypted secret data from the "encrypted" payload section.
  Map<String, dynamic>? secretData;

  /// The "iss" (issuer) claim.
  String? get issuer => token.issuer;

  /// The "sub" (subject) claim.
  String? get subject => token.subject;

  /// The "jti" (JWT ID) claim.
  String? get jwtId => token.jwtId;

  /// The "aud" (audience) claim.
  jwt.Audience? get audience => token.audience;

  /// The full token payload as a map.
  Map<String, dynamic>? get payload => token.payload as Map<String, dynamic>;

  // ---------------------------------------------------------------------------
  // Constructors
  // ---------------------------------------------------------------------------

  /// Creates a new client-side JWT token from a token string.
  ///
  /// [token] is the JWT token string to decode.
  /// [signingConfiguration] optional custom configuration for decryption.
  /// [decrypt] whether to decrypt the "encrypted" section (default: true).
  ///
  /// Throws [TomJwtTokenException] if decryption fails.
  TomClientJwtToken(
    String token, {
        TomJwtConfiguration? signingConfiguration,
        this.decrypt = true,
      }) {
    this.signingConfiguration = signingConfiguration ?? this.signingConfiguration;
    tokenString = token;
    this.token = jwt.JWT.decode(token);
    if(decrypt) _unwrapToken();
  }

  // ---------------------------------------------------------------------------
  // Private Methods
  // ---------------------------------------------------------------------------

  /// Decrypts the "encrypted" section of the token payload.
  ///
  /// If the payload contains an "encrypted" key, its value is decrypted
  /// using RSA and parsed as JSON into [secretData].
  void _unwrapToken() {
    if (token.payload is Map && token.payload["encrypted"] != null) {
      String? decrypted;
      if (token.payload["encrypted"] is! String) {
        tomLog.warn("Token encrypted data was not of type String. Ignoring.");
        return;
      }
      try {
        decrypted = signingConfiguration.decrypt(token.payload["encrypted"] as String);
        secretData = jsonDecode(decrypted);
      } catch (e, s) {
        throw TomJwtTokenException(
          "jwt_token.error.decryption_failed",
          "Failed to decrypt token encrypted data $e",
          rootException: e,
          stack: s,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Static Settings
  // ---------------------------------------------------------------------------

  /// When true, [toString] includes the full payload and secret data.
  ///
  /// Set to false in production to avoid logging sensitive information.
  static bool globalSettingShowContentInToString = true;

  // ---------------------------------------------------------------------------
  // Object Overrides
  // ---------------------------------------------------------------------------

  @override
  String toString() =>
      "TomClientJwtToken I: ${token.issuer} ID: ${token.jwtId} A: ${token.audience} H: ${token.header} S: ${token.subject} P: ${globalSettingShowContentInToString ? token.payload : ''} S: ${globalSettingShowContentInToString ? secretData : ''}";
}
