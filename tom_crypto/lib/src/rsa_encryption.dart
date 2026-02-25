/// RSA encryption, decryption, and digital signatures for TomBase.
///
/// This library provides core RSA cryptographic operations using the
/// PointyCastle library. It supports:
/// - OAEP encryption/decryption for data confidentiality
/// - SHA-256 based signatures for data integrity and authentication
///
/// ## Encryption
///
/// RSA encryption uses OAEP (Optimal Asymmetric Encryption Padding) for
/// security against chosen ciphertext attacks.
///
/// ```dart
/// final encrypted = rsaEncrypt(publicKey, plaintextBytes);
/// final decrypted = rsaDecrypt(privateKey, encrypted);
/// ```
///
/// ## Digital Signatures
///
/// Signatures use SHA-256 for hashing before RSA signing.
///
/// ```dart
/// final signature = rsaSign(privateKey, dataBytes);
/// final isValid = rsaVerify(publicKey, dataBytes, signature);
/// ```
///
/// ## Block Processing
///
/// Large data is automatically processed in blocks to handle RSA's
/// input size limitations.
library;

// =============================================================================
// Dart SDK Imports
// =============================================================================

import 'dart:typed_data';

// =============================================================================
// Package Imports
// =============================================================================

import "package:pointycastle/export.dart";

// =============================================================================
// RSA Encryption Functions
// =============================================================================

/// Encrypts data using RSA with OAEP padding.
///
/// [myPublic] is the RSA public key to encrypt with.
/// [dataToEncrypt] is the plaintext data as bytes.
///
/// Returns the encrypted ciphertext as a [Uint8List].
///
/// The data is processed in blocks if it exceeds the RSA input block size.
/// OAEP padding provides security against chosen ciphertext attacks.
///
/// ## Example
///
/// ```dart
/// final publicKey = RsaKeyHelper.parsePublicKeyFromPem(pemString);
/// final plaintext = utf8.encode('Hello, World!');
/// final encrypted = rsaEncrypt(publicKey, Uint8List.fromList(plaintext));
/// ```
Uint8List rsaEncrypt(RSAPublicKey myPublic, Uint8List dataToEncrypt) {
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
///
/// ## Example
///
/// ```dart
/// final privateKey = RsaKeyHelper.parsePrivateKeyFromPem(pemString);
/// final decrypted = rsaDecrypt(privateKey, encryptedBytes);
/// final plaintext = utf8.decode(decrypted);
/// ```
Uint8List rsaDecrypt(RSAPrivateKey myPrivate, Uint8List cipherText) {
  final decryptor = OAEPEncoding(RSAEngine())
    ..init(
      false,
      PrivateKeyParameter<RSAPrivateKey>(myPrivate),
    ); // false=decrypt

  return _processInBlocks(decryptor, cipherText);
}

// =============================================================================
// Block Processing
// =============================================================================

/// Processes data through an asymmetric block cipher in chunks.
///
/// [engine] is the initialized cipher engine.
/// [input] is the data to process.
///
/// Returns the processed output, trimmed to actual size.
///
/// This handles RSA's block size limitations by processing large
/// inputs in appropriately sized chunks.
Uint8List _processInBlocks(AsymmetricBlockCipher engine, Uint8List input) {
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

// =============================================================================
// RSA Digital Signatures
// =============================================================================

/// OID for SHA-256 hash algorithm used in RSA signatures.
///
/// This is the ASN.1 Object Identifier for SHA-256 in hex format.
String tomRsaHashIdentifier = '0609608648016503040201';

/// Creates an RSA digital signature using SHA-256.
///
/// [privateKey] is the RSA private key to sign with.
/// [dataToSign] is the data to sign as bytes.
///
/// Returns the signature as a [Uint8List].
///
/// The data is hashed with SHA-256 before signing.
///
/// ## Example
///
/// ```dart
/// final privateKey = RsaKeyHelper.parsePrivateKeyFromPem(pemString);
/// final data = utf8.encode('Important message');
/// final signature = rsaSign(privateKey, Uint8List.fromList(data));
/// ```
Uint8List rsaSign(RSAPrivateKey privateKey, Uint8List dataToSign) {
  //final signer = Signer('SHA-256/RSA'); // Get using registry
  final signer = RSASigner(SHA256Digest(), tomRsaHashIdentifier);

  // initialize with true, which means sign
  signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));

  final sig = signer.generateSignature(dataToSign);

  return sig.bytes;
}

/// Verifies an RSA digital signature.
///
/// [publicKey] is the RSA public key to verify with.
/// [signedData] is the original data that was signed.
/// [signature] is the signature to verify.
///
/// Returns true if the signature is valid, false otherwise.
///
/// ## Example
///
/// ```dart
/// final publicKey = RsaKeyHelper.parsePublicKeyFromPem(pemString);
/// final data = utf8.encode('Important message');
/// final isValid = rsaVerify(publicKey, Uint8List.fromList(data), signature);
/// if (isValid) {
///   print('Signature verified!');
/// }
/// ```
bool rsaVerify(
  RSAPublicKey publicKey,
  Uint8List signedData,
  Uint8List signature,
) {
  //final signer = Signer('SHA-256/RSA'); // Get using registry
  final sig = RSASignature(signature);

  final verifier = RSASigner(SHA256Digest(), tomRsaHashIdentifier);

  // initialize with false, which means verify
  verifier.init(false, PublicKeyParameter<RSAPublicKey>(publicKey));

  try {
    return verifier.verifySignature(signedData, sig);
  } on ArgumentError {
    return false; // for Pointy Castle 1.0.2 when signature has been modified
  }
}
