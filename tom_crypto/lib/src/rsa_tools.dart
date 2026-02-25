/// RSA key generation, parsing, and encoding utilities for TomBase.
///
/// This library provides comprehensive RSA key management including:
/// - Key pair generation with secure random
/// - PEM format parsing (PKCS#1 and PKCS#8)
/// - PEM format encoding
/// - Key-based encryption and signing operations
///
/// ## Key Generation
///
/// ```dart
/// final secureRandom = RsaKeyHelper.getSecureRandom();
/// final keyPair = await RsaKeyHelper.computeRSAKeyPair(secureRandom);
/// final publicKey = keyPair.publicKey as RSAPublicKey;
/// final privateKey = keyPair.privateKey as RSAPrivateKey;
/// ```
///
/// ## PEM Parsing
///
/// Supports both PKCS#1 and PKCS#8 formats:
///
/// ```dart
/// final publicKey = RsaKeyHelper.parsePublicKeyFromPem(pemString);
/// final privateKey = RsaKeyHelper.parsePrivateKeyFromPem(pemString);
/// ```
///
/// ## PEM Encoding
///
/// ```dart
/// final pemPublic = RsaKeyHelper.encodePublicKeyToPemPKCS1(publicKey);
/// final pemPrivate = RsaKeyHelper.encodePrivateKeyToPemPKCS1(privateKey);
/// ```
library;

// =============================================================================
// Dart SDK Imports
// =============================================================================

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// =============================================================================
// Package Imports
// =============================================================================

import "package:asn1lib/asn1lib.dart";
import "package:pointycastle/export.dart";

// =============================================================================
// Relative Imports
// =============================================================================

import 'rsa_encryption.dart';

// =============================================================================
// RSA Key Helper
// =============================================================================

/// Helper class for RSA key generation, parsing, and encoding.
///
/// [RsaKeyHelper] provides static methods for working with RSA keys,
/// including generation, PEM format conversion, and cryptographic operations.
///
/// ## Key Formats
///
/// This class supports:
/// - **PKCS#1**: Traditional RSA key format
/// - **PKCS#8**: Newer format with algorithm identifier
///
/// Both formats are automatically detected during parsing.
///
/// ## Security Notes
///
/// - Generated keys use 2048-bit modulus (industry standard minimum)
/// - Uses FortunaRandom CSPRNG for key generation
/// - Public exponent is fixed at 65537 (0x10001)
///
/// Adapted from: https://github.com/Vanethos/flutter_rsa_generator_example/
class RsaKeyHelper {
  // ---------------------------------------------------------------------------
  // Key Generation
  // ---------------------------------------------------------------------------

  /// Generates an RSA key pair asynchronously.
  ///
  /// [secureRandom] is a cryptographically secure random number generator.
  ///
  /// Returns an [AsymmetricKeyPair] containing the public and private keys.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final random = RsaKeyHelper.getSecureRandom();
  /// final keyPair = await RsaKeyHelper.computeRSAKeyPair(random);
  /// final publicKey = keyPair.publicKey as RSAPublicKey;
  /// final privateKey = keyPair.privateKey as RSAPrivateKey;
  /// ```
  static Future<AsymmetricKeyPair<PublicKey, PrivateKey>> computeRSAKeyPair(
    SecureRandom secureRandom,
  ) async {
    return getRsaKeyPair(secureRandom);
  }

  /// Creates a cryptographically secure random number generator.
  ///
  /// Returns a [FortunaRandom] seeded with 32 bytes of secure random data.
  ///
  /// This should be used as input to [computeRSAKeyPair] for key generation.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final random = RsaKeyHelper.getSecureRandom();
  /// ```
  static SecureRandom getSecureRandom() {
    var secureRandom = FortunaRandom();
    var random = Random.secure();
    List<int> seeds = [];
    for (int i = 0; i < 32; i++) {
      seeds.add(random.nextInt(255));
    }
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  // ---------------------------------------------------------------------------
  // PEM Parsing
  // ---------------------------------------------------------------------------

  /// Parses an RSA public key from PEM format.
  ///
  /// [pemString] is the PEM-encoded public key with headers and footers.
  ///
  /// Supports both PKCS#1 and PKCS#8 formats:
  ///
  /// **PKCS#1:**
  /// ```
  /// RSAPublicKey ::= SEQUENCE {
  ///    modulus           INTEGER,  -- n
  ///    publicExponent    INTEGER   -- e
  /// }
  /// ```
  ///
  /// **PKCS#8:**
  /// ```
  /// PublicKeyInfo ::= SEQUENCE {
  ///   algorithm       AlgorithmIdentifier,
  ///   PublicKey       BIT STRING
  /// }
  /// ```
  ///
  /// ## Example
  ///
  /// ```dart
  /// final publicKey = RsaKeyHelper.parsePublicKeyFromPem('''
  /// -----BEGIN PUBLIC KEY-----
  /// MIIBIjANBgkq...
  /// -----END PUBLIC KEY-----
  /// ''');
  /// ```
  static RSAPublicKey parsePublicKeyFromPem(String pemString) {
    List<int> publicKeyDER = decodePEM(pemString);
    var asn1Parser = ASN1Parser(Uint8List.fromList(publicKeyDER));
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

    ASN1Integer modulus, exponent;
    // Depending on the first element type, we either have PKCS1 or 2
    if (topLevelSeq.elements[0].runtimeType == ASN1Integer) {
      modulus = topLevelSeq.elements[0] as ASN1Integer;
      exponent = topLevelSeq.elements[1] as ASN1Integer;
    } else {
      var publicKeyBitString = topLevelSeq.elements[1];

      var publicKeyAsn = ASN1Parser(publicKeyBitString.contentBytes());
      ASN1Sequence publicKeySeq = publicKeyAsn.nextObject() as ASN1Sequence;
      modulus = publicKeySeq.elements[0] as ASN1Integer;
      exponent = publicKeySeq.elements[1] as ASN1Integer;
    }

    RSAPublicKey rsaPublicKey = RSAPublicKey(
      modulus.valueAsBigInteger,
      exponent.valueAsBigInteger,
    );

    return rsaPublicKey;
  }

  // ---------------------------------------------------------------------------
  // Signing and Verification
  // ---------------------------------------------------------------------------

  /// Signs plain text using an RSA private key.
  ///
  /// [plainText] is the text to sign.
  /// [privateKey] is the RSA private key used for signing.
  ///
  /// Returns the base64-encoded signature.
  ///
  /// Uses SHA-256 for hashing before signing.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final signature = RsaKeyHelper.sign('Hello, World!', privateKey);
  /// ```
  static String sign(String plainText, RSAPrivateKey privateKey) {
    var signer = RSASigner(SHA256Digest(), tomRsaHashIdentifier);
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return base64Encode(
      signer.generateSignature(createUint8ListFromString(plainText)).bytes,
    );
  }

  // ---------------------------------------------------------------------------
  // Encryption and Decryption
  // ---------------------------------------------------------------------------

  /// Encrypts data using RSA with OAEP padding.
  ///
  /// [myPublic] is the RSA public key to encrypt with.
  /// [dataToEncrypt] is the plaintext data as bytes.
  ///
  /// Returns the encrypted ciphertext as a [Uint8List].
  static Uint8List rsaEncrypt(RSAPublicKey myPublic, Uint8List dataToEncrypt) {
    final encryptor = OAEPEncoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(myPublic)); // true=encrypt

    return _processInBlocks(encryptor, dataToEncrypt);
  }

  /// Decrypts RSA-encrypted data using OAEP padding.
  ///
  /// [myPrivate] is the RSA private key to decrypt with.
  /// [cipherText] is the encrypted data as bytes.
  ///
  /// Returns the decrypted plaintext as a [Uint8List].
  static Uint8List rsaDecrypt(RSAPrivateKey myPrivate, Uint8List cipherText) {
    final decryptor = OAEPEncoding(RSAEngine())
      ..init(
        false,
        PrivateKeyParameter<RSAPrivateKey>(myPrivate),
      ); // false=decrypt

    return _processInBlocks(decryptor, cipherText);
  }

  /// Processes data through an asymmetric block cipher in chunks.
  ///
  /// [engine] is the initialized cipher engine.
  /// [input] is the data to process.
  ///
  /// Returns the processed output, trimmed to actual size.
  static Uint8List _processInBlocks(
    AsymmetricBlockCipher engine,
    Uint8List input,
  ) {
    final numBlocks =
        input.length ~/ engine.inputBlockSize +
        ((input.length % engine.inputBlockSize != 0) ? 1 : 0);

    final output = Uint8List(numBlocks * engine.outputBlockSize);

    var inputOffset = 0;
    var outputOffset = 0;
    while (inputOffset < input.length) {
      final chunkSize = (inputOffset + engine.inputBlockSize <= input.length)
          ? engine.inputBlockSize
          : input.length - inputOffset;

      outputOffset += engine.processBlock(
        input,
        inputOffset,
        chunkSize,
        output,
        outputOffset,
      );

      inputOffset += chunkSize;
    }

    return (output.length == outputOffset)
        ? output
        : output.sublist(0, outputOffset);
  }

  // ---------------------------------------------------------------------------
  // Utility Methods
  // ---------------------------------------------------------------------------

  /// Converts a string to a [Uint8List] for signing.
  ///
  /// Uses UTF-8 encoding with malformed character tolerance.
  static Uint8List createUint8ListFromString(String s) {
    var codec = Utf8Codec(allowMalformed: true);
    return Uint8List.fromList(codec.encode(s));
  }

  /// Parses an RSA private key from PEM format.
  ///
  /// [pemString] is the PEM-encoded private key with headers and footers.
  ///
  /// Supports both PKCS#1 and PKCS#8 formats.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final privateKey = RsaKeyHelper.parsePrivateKeyFromPem('''
  /// -----BEGIN PRIVATE KEY-----
  /// MIIEvQIBADANBgkq...
  /// -----END PRIVATE KEY-----
  /// ''');
  /// ```
  static RSAPrivateKey parsePrivateKeyFromPem(String pemString) {
    List<int> privateKeyDER = decodePEM(pemString);
    var asn1Parser = ASN1Parser(Uint8List.fromList(privateKeyDER));
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

    ASN1Integer modulus, privateExponent, p, q;
    // Depending on the number of elements, we will either use PKCS1 or PKCS8
    if (topLevelSeq.elements.length == 3) {
      var privateKey = topLevelSeq.elements[2];

      asn1Parser = ASN1Parser(privateKey.contentBytes());
      var pkSeq = asn1Parser.nextObject() as ASN1Sequence;

      modulus = pkSeq.elements[1] as ASN1Integer;
      privateExponent = pkSeq.elements[3] as ASN1Integer;
      p = pkSeq.elements[4] as ASN1Integer;
      q = pkSeq.elements[5] as ASN1Integer;
    } else {
      modulus = topLevelSeq.elements[1] as ASN1Integer;
      privateExponent = topLevelSeq.elements[3] as ASN1Integer;
      p = topLevelSeq.elements[4] as ASN1Integer;
      q = topLevelSeq.elements[5] as ASN1Integer;
    }

    RSAPrivateKey rsaPrivateKey = RSAPrivateKey(
      modulus.valueAsBigInteger,
      privateExponent.valueAsBigInteger,
      p.valueAsBigInteger,
      q.valueAsBigInteger,
    );

    return rsaPrivateKey;
  }

  /// Decodes a PEM string to raw DER bytes.
  ///
  /// [pem] is the PEM-encoded data with headers and footers.
  ///
  /// Returns the base64-decoded content as raw bytes.
  static List<int> decodePEM(String pem) {
    return base64.decode(removePemHeaderAndFooter(pem));
  }

  /// Removes PEM headers and footers from a key string.
  ///
  /// [pem] is the PEM-encoded string.
  ///
  /// Returns the base64-encoded content without headers/footers.
  ///
  /// Supports standard RSA key formats and OpenPGP key blocks.
  static String removePemHeaderAndFooter(String pem) {
    var startsWith = [
      "-----BEGIN PUBLIC KEY-----",
      "-----BEGIN RSA PRIVATE KEY-----",
      "-----BEGIN RSA PUBLIC KEY-----",
      "-----BEGIN PRIVATE KEY-----",
      "-----BEGIN PGP PUBLIC KEY BLOCK-----\r\nVersion: React-Native-OpenPGP.js 0.1\r\nComment: http://openpgpjs.org\r\n\r\n",
      "-----BEGIN PGP PRIVATE KEY BLOCK-----\r\nVersion: React-Native-OpenPGP.js 0.1\r\nComment: http://openpgpjs.org\r\n\r\n",
    ];
    var endsWith = [
      "-----END PUBLIC KEY-----",
      "-----END PRIVATE KEY-----",
      "-----END RSA PRIVATE KEY-----",
      "-----END RSA PUBLIC KEY-----",
      "-----END PGP PUBLIC KEY BLOCK-----",
      "-----END PGP PRIVATE KEY BLOCK-----",
    ];
    bool isOpenPgp = pem.contains('BEGIN PGP');

    pem = pem.replaceAll(' ', '');
    pem = pem.replaceAll('\n', '');
    pem = pem.replaceAll('\r', '');

    for (var s in startsWith) {
      s = s.replaceAll(' ', '');
      if (pem.startsWith(s)) {
        pem = pem.substring(s.length);
      }
    }

    for (var s in endsWith) {
      s = s.replaceAll(' ', '');
      if (pem.endsWith(s)) {
        pem = pem.substring(0, pem.length - s.length);
      }
    }

    if (isOpenPgp) {
      var index = pem.indexOf('\r\n');
      pem = pem.substring(0, index);
    }

    return pem;
  }

  // ---------------------------------------------------------------------------
  // PEM Encoding
  // ---------------------------------------------------------------------------

  /// Encodes an RSA private key to PEM format.
  ///
  /// [privateKey] is the RSA private key to encode.
  ///
  /// Returns a PKCS#1 formatted PEM string with headers and footers.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final pem = RsaKeyHelper.encodePrivateKeyToPemPKCS1(privateKey);
  /// // Store or transmit the PEM string
  /// ```
  static String encodePrivateKeyToPemPKCS1(RSAPrivateKey privateKey) {
    var topLevel = ASN1Sequence();

    var version = ASN1Integer(BigInt.from(0));
    var modulus = ASN1Integer(privateKey.n!);
    var publicExponent = ASN1Integer(privateKey.exponent!);
    var privateExponent = ASN1Integer(privateKey.privateExponent!);
    var p = ASN1Integer(privateKey.p!);
    var q = ASN1Integer(privateKey.q!);
    var dP = privateKey.privateExponent! % (privateKey.p! - BigInt.from(1));
    var exp1 = ASN1Integer(dP);
    var dQ = privateKey.privateExponent! % (privateKey.q! - BigInt.from(1));
    var exp2 = ASN1Integer(dQ);
    var iQ = privateKey.q!.modInverse(privateKey.p!);
    var co = ASN1Integer(iQ);

    topLevel.add(version);
    topLevel.add(modulus);
    topLevel.add(publicExponent);
    topLevel.add(privateExponent);
    topLevel.add(p);
    topLevel.add(q);
    topLevel.add(exp1);
    topLevel.add(exp2);
    topLevel.add(co);

    var dataBase64 = base64.encode(topLevel.encodedBytes);

    return """-----BEGIN PRIVATE KEY-----\r\n$dataBase64\r\n-----END PRIVATE KEY-----""";
  }

  /// Encodes an RSA public key to PEM format.
  ///
  /// [publicKey] is the RSA public key to encode.
  ///
  /// Returns a PKCS#1 formatted PEM string with headers and footers.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final pem = RsaKeyHelper.encodePublicKeyToPemPKCS1(publicKey);
  /// // Share the public key
  /// ```
  static String encodePublicKeyToPemPKCS1(RSAPublicKey publicKey) {
    var topLevel = ASN1Sequence();

    topLevel.add(ASN1Integer(publicKey.modulus!));
    topLevel.add(ASN1Integer(publicKey.exponent!));

    var dataBase64 = base64.encode(topLevel.encodedBytes);
    return """-----BEGIN PUBLIC KEY-----\r\n$dataBase64\r\n-----END PUBLIC KEY-----""";
  }
}

// =============================================================================
// Top-Level Key Generation
// =============================================================================

/// Generates an RSA key pair synchronously.
///
/// [secureRandom] is a cryptographically secure random number generator.
///
/// Returns an [AsymmetricKeyPair] with a 2048-bit RSA key.
///
/// Key generation parameters:
/// - Public exponent: 65537 (0x10001)
/// - Key size: 2048 bits
/// - Certainty: 5 (Miller-Rabin primality test iterations)
///
/// ## Example
///
/// ```dart
/// final random = RsaKeyHelper.getSecureRandom();
/// final keyPair = getRsaKeyPair(random);
/// ```
AsymmetricKeyPair<PublicKey, PrivateKey> getRsaKeyPair(
  SecureRandom secureRandom,
) {
  var rsapars = RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 5);
  var params = ParametersWithRandom(rsapars, secureRandom);
  var keyGenerator = RSAKeyGenerator();
  keyGenerator.init(params);
  return keyGenerator.generateKeyPair();
}
