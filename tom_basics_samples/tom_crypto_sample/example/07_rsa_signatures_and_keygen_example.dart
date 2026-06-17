/// Example 07 — RSA signatures and key management.
///
/// The flip side of encryption is the **signature**: the private key signs, the
/// public key verifies. A valid signature proves the data came from the key
/// holder and was not altered. `tom_crypto` exposes [rsaSign] / [rsaVerify]
/// (SHA-256 then RSA), plus a full key-management surface in [RsaKeyHelper] —
/// generating fresh 2048-bit pairs and converting them to and from PEM text.
///
/// This example signs a release string and verifies it (valid, then rejects a
/// tampered copy), generates a brand-new key pair, round-trips its public key
/// through PEM, and proves the generated pair encrypts and decrypts. Signatures
/// and keys are large random/derived blobs, so we assert booleans and the
/// 2048-bit modulus size, not the bytes.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:tom_crypto/tom_crypto.dart';

Future<void> main() async {
  // --- Signatures with the development keys ---
  final priv = TomJwtConfiguration.rsaPrivKey;
  final pub = TomJwtConfiguration.rsaPubKey;

  final data = Uint8List.fromList(utf8.encode('release v1.0.0'));
  final signature = rsaSign(priv, data);
  print('valid signature: ${rsaVerify(pub, data, signature)}');

  final tampered = Uint8List.fromList(utf8.encode('release v1.0.1'));
  print('tampered data rejected: ${!rsaVerify(pub, tampered, signature)}');

  // --- Generate a fresh 2048-bit key pair ---
  final random = RsaKeyHelper.getSecureRandom();
  final pair = await RsaKeyHelper.computeRSAKeyPair(random);
  final genPub = pair.publicKey as RSAPublicKey;
  final genPriv = pair.privateKey as RSAPrivateKey;
  print('generated modulus bits: ${genPub.modulus!.bitLength}');

  // --- PEM round trip: encode the public key, then parse it back ---
  final pem = RsaKeyHelper.encodePublicKeyToPemPKCS1(genPub);
  final parsed = RsaKeyHelper.parsePublicKeyFromPem(pem);
  print('PEM header present: '
      '${pem.startsWith('-----BEGIN PUBLIC KEY-----')}');
  print('parsed modulus matches: ${parsed.modulus == genPub.modulus}');

  // --- The generated pair really works end to end ---
  const secret = 'generated-key secret';
  final cipher = rsaEncrypt(genPub, Uint8List.fromList(utf8.encode(secret)));
  final back = utf8.decode(rsaDecrypt(genPriv, cipher));
  print('generated pair round-trips: ${back == secret}');

  // expected output:
  // valid signature: true
  // tampered data rejected: true
  // generated modulus bits: 2048
  // PEM header present: true
  // parsed modulus matches: true
  // generated pair round-trips: true
}
