// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The four schemes of tom_pqc, each in a few lines: an ML-KEM-768 key
/// exchange, an ML-DSA-65 signature, an MLKEM768-X25519 (X-Wing) key
/// exchange and an RFC 10073 composite ML-DSA-65 + Ed25519 signature.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:tom_pqc/tom_pqc.dart';

Future<void> main() async {
  final message = Uint8List.fromList(utf8.encode('approve grant 42'));

  // ML-KEM-768: the receiver publishes its encapsulation key, the sender
  // encapsulates a shared secret to it, the receiver decapsulates it.
  final receiver = MlKem768.generateKeyPair();
  final sent = MlKem768.encapsulate(receiver.publicKey);
  final received = MlKem768.decapsulate(sent.ciphertext, receiver.secretKey);
  print(
    'ML-KEM-768: shared secrets equal: '
    '${_equal(sent.sharedSecret.extractBytes(), received.extractBytes())}',
  );

  // ML-DSA-65: a hedged signature with a context string.
  final context = Uint8List.fromList(utf8.encode('example/grant'));
  final signer = MlDsa65.generateKeyPair();
  final signature = MlDsa65.sign(message, signer.secretKey, context: context);
  print(
    'ML-DSA-65: ${signature.length}-byte signature verifies: '
    '${MlDsa65.verify(message, signature, signer.publicKey, context: context)}',
  );

  // MLKEM768-X25519 (X-Wing): secure while either half holds.
  final hybrid = await MlKem768X25519.generateKeyPair();
  final capsule = await MlKem768X25519.encapsulate(hybrid.publicKey);
  final opened = await MlKem768X25519.decapsulate(
    capsule.ciphertext,
    hybrid.secretKey,
  );
  print(
    'MLKEM768-X25519: shared secrets equal: '
    '${_equal(capsule.sharedSecret.extractBytes(), opened.extractBytes())}',
  );

  // Composite ML-DSA-65 + Ed25519 (RFC 10073): valid only if both verify.
  final composite = await MlDsa65Ed25519.generateKeyPair();
  final both = await MlDsa65Ed25519.sign(message, composite.secretKey);
  print(
    'ML-DSA-65+Ed25519: ${both.length}-byte signature verifies: '
    '${await MlDsa65Ed25519.verify(message, both, composite.publicKey)}',
  );

  // Overwrite the secrets as soon as they are no longer needed.
  for (final secret in [
    sent.sharedSecret,
    received,
    capsule.sharedSecret,
    opened,
  ]) {
    secret.dispose();
  }
  receiver.dispose();
  signer.dispose();
  hybrid.dispose();
  composite.dispose();
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
