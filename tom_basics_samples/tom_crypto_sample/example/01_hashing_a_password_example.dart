/// Example 01 — Hashing a password.
///
/// Never store a password. Store a one-way *hash* of it, and at login time hash
/// the attempt and compare. `tom_crypto` does this with **Argon2**, the winner
/// of the Password Hashing Competition — deliberately slow and memory-hungry so
/// that guessing is expensive.
///
/// [TomPasswordHasher.hashPassword] returns a record `(hash, spec)`: the salted
/// hash and the algorithm specification used to produce it. You store *both*.
/// [TomPasswordHasher.verifyPassword] re-derives the hash from an attempt and
/// the stored salt/spec, and compares.
///
/// Two facts this example pins down: a correct password verifies and a wrong
/// one does not; and because each hash uses a fresh random salt, hashing the
/// *same* password twice yields two different strings — both of which still
/// verify. We therefore print booleans and structure, never the random hash
/// bytes themselves.
library;

import 'package:tom_crypto/tom_crypto.dart';

void main() {
  const password = 'correct horse battery staple';

  final (hash, spec) = TomPasswordHasher.hashPassword(password);

  // The stored credential is "salt$hash" plus the spec. Show its shape, not its
  // (random) value.
  print('hash has salt\$hash shape: ${hash.contains(r'$')}');
  print('spec: $spec');

  // The right password verifies; a wrong one does not.
  print('verify correct: ${TomPasswordHasher.verifyPassword(password, hash, spec)}');
  print('verify wrong:   '
      '${TomPasswordHasher.verifyPassword('wrong password', hash, spec)}');

  // A fresh hash of the same password uses a new salt, so the strings differ —
  // yet both verify. This is why you can never compare hashes directly.
  final (hash2, _) = TomPasswordHasher.hashPassword(password);
  print('two hashes differ: ${hash != hash2}');
  print('both verify: '
      '${TomPasswordHasher.verifyPassword(password, hash2, spec)}');

  // expected output:
  // hash has salt$hash shape: true
  // spec: Argon2;2i,13,4,65536,4,128
  // verify correct: true
  // verify wrong:   false
  // two hashes differ: true
  // both verify: true
}
