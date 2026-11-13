// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// An ML-KEM-768 key exchange: the receiver publishes its encapsulation key,
/// the sender encapsulates a shared secret to it, the receiver decapsulates
/// the same secret.
library;

import 'package:tom_pqc/tom_pqc.dart';

void main() {
  // The receiver: a key pair. The secret key stays in native memory.
  final receiver = MlKem768.generateKeyPair();

  // The sender: a ciphertext for the receiver and the secret it carries.
  final sent = MlKem768.encapsulate(receiver.publicKey);

  // The receiver: the same secret from the ciphertext.
  final received = MlKem768.decapsulate(sent.ciphertext, receiver.secretKey);

  final same = _equal(
    sent.sharedSecret.extractBytes(),
    received.extractBytes(),
  );
  print(
    'public key ${receiver.publicKey.length} bytes, '
    'ciphertext ${sent.ciphertext.length} bytes, '
    'shared secret ${received.length} bytes, equal: $same',
  );

  // Overwrite the secrets as soon as they are no longer needed.
  sent.sharedSecret.dispose();
  received.dispose();
  receiver.dispose();
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
