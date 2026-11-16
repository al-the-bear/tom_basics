// Tom Crypto in one program: hash and verify a password, generate an RSA key
// pair, encrypt and sign with it, issue and read a JWT whose secret claims are
// RSA-encrypted, and keep a secret in memory as a protected value.
//
// Everything runs offline; the keys are generated on the spot.
//
// Run from the package folder:
//
//   dart run example/tom_crypto_example.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:tom_crypto/tom_crypto.dart';

Future<void> main() async {
  // --- Password hashing ------------------------------------------------------
  // `hashPassword` returns the hash and the spec that produced it; store both.
  final (hash, spec) = TomPasswordHasher.hashPassword('correct horse battery');
  print('password spec      : $spec'); // Argon2;2i,13,4,65536,4,128
  print(
    'correct password   : '
    '${TomPasswordHasher.verifyPassword('correct horse battery', hash, spec)}',
  ); // true
  print(
    'wrong password     : '
    '${TomPasswordHasher.verifyPassword('wrong password', hash, spec)}',
  ); // false

  // --- RSA keys, encryption and signatures -----------------------------------
  final pair = await RsaKeyHelper.computeRSAKeyPair(
    RsaKeyHelper.getSecureRandom(),
  );
  final publicKey = pair.publicKey as RSAPublicKey;
  final privateKey = pair.privateKey as RSAPrivateKey;
  print('RSA key size       : ${publicKey.modulus!.bitLength} bits'); // 2048

  final message = Uint8List.fromList(utf8.encode('Secret message'));
  final cipher = rsaEncrypt(publicKey, message);
  print('RSA round trip     : ${utf8.decode(rsaDecrypt(privateKey, cipher))}');
  // Secret message

  final signature = rsaSign(privateKey, message);
  final tampered = Uint8List.fromList(utf8.encode('Secret massage'));
  print('signature valid    : ${rsaVerify(publicKey, message, signature)}');
  // true
  print('tampered valid     : ${rsaVerify(publicKey, tampered, signature)}');
  // false

  final pem = RsaKeyHelper.encodePublicKeyToPemPKCS1(publicKey);
  final reparsed = RsaKeyHelper.parsePublicKeyFromPem(pem);
  print(
    'PEM round trip     : ${reparsed.modulus == publicKey.modulus}',
  ); // true

  // --- JWT tokens --------------------------------------------------------------
  // A configuration with the keys generated above (`false`: not the bundled
  // development keys, so no warning is printed).
  final configuration = TomJwtConfiguration(
    SecretKey('example-hmac-secret'),
    JWTAlgorithm.HS256,
    privateKey,
    publicKey,
    false,
  );
  final jwtString = TomServerJwtToken(
    {'userId': '123', 'role': 'admin'},
    encryptedData: {'sessionSecret': 'abc123'},
    expiresIn: const Duration(hours: 1),
    signingConfiguration: configuration,
  ).getJWT('example-auth-server');

  final parsed = TomClientJwtToken(
    jwtString,
    signingConfiguration: configuration,
  );
  print('JWT issuer         : ${parsed.issuer}'); // example-auth-server
  print('JWT public claim   : ${parsed.payload?['userId']}'); // 123
  print(
    'JWT secret claim   : ${parsed.secretData?['sessionSecret']}',
  ); // abc123

  // --- Secrets in memory -------------------------------------------------------
  final apiKey = TomProtectedValue.of('sk-example-not-a-real-key');
  print('protected value    : $apiKey'); // TomProtectedValue(••••)
  print('revealed length    : ${apiKey.reveal().length}'); // 25
  apiKey.dispose();

  // --- Raw randomness ----------------------------------------------------------
  print('secure bytes       : ${TomSecureBytes.generate(16).length}'); // 16
}
