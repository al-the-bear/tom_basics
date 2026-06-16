/// Example 06 — RSA encrypt / decrypt.
///
/// RSA is *asymmetric*: a public key encrypts, and only the matching private
/// key decrypts. That is what lets you publish the public key freely — anyone
/// can send you a secret, but only you can open it. `tom_crypto` wraps the
/// PointyCastle engine with **OAEP padding** ([rsaEncrypt] / [rsaDecrypt]),
/// the modern padding that defends against chosen-ciphertext attacks.
///
/// This example encrypts a message to the development public key and decrypts
/// it with the private key. Because OAEP injects randomness, encrypting the
/// same plaintext twice produces *different* ciphertext — both of which still
/// decrypt to the original. We therefore assert the round trip and the
/// block size, never the (random) ciphertext bytes.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:tom_crypto/tom_crypto.dart';

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  final pub = TomJwtConfiguration.rsaPubKey;
  final priv = TomJwtConfiguration.rsaPrivKey;

  const plaintext = 'attack at dawn';
  final bytes = Uint8List.fromList(utf8.encode(plaintext));

  // Encrypt with the public key, decrypt with the private key.
  final cipher = rsaEncrypt(pub, bytes);
  final recovered = utf8.decode(rsaDecrypt(priv, cipher));
  print('recovered: $recovered');
  print('round-trips: ${recovered == plaintext}');

  // OAEP is randomized: a second encryption differs byte-for-byte, yet decrypts.
  final cipher2 = rsaEncrypt(pub, bytes);
  print('ciphertexts differ: ${!_bytesEqual(cipher, cipher2)}');
  print('second decrypts too: '
      '${utf8.decode(rsaDecrypt(priv, cipher2)) == plaintext}');

  // A 2048-bit key produces a 256-byte ciphertext block.
  print('cipher length: ${cipher.length}');

  // expected output:
  // recovered: attack at dawn
  // round-trips: true
  // ciphertexts differ: true
  // second decrypts too: true
  // cipher length: 256
}
