/// Example 02 — The hash specification.
///
/// A stored credential is not just a hash. It is **`salt$hash` plus a spec**,
/// and all three are needed to verify. The spec —
/// `Argon2;variant,version,iterations,memory,lanes,keyLength` — records *how*
/// the hash was produced, so the parameters can be upgraded later without
/// invalidating old hashes: each hash carries the recipe that made it.
///
/// This example dissects that contract. The salt lives in the hash string
/// (16 bytes → 32 hex chars); the spec is a separate field; and verifying with
/// the *wrong* spec fails, because different parameters derive a different key.
/// It closes with the hex helpers the format is built on.
library;

import 'dart:typed_data';

import 'package:tom_crypto/tom_crypto.dart';

void main() {
  const password = 'sp3c-aware';
  final (hash, spec) = TomPasswordHasher.hashPassword(password);

  // The hash string is salt + "$" + derived-key, both hex. The default salt is
  // 16 bytes, so the salt half is 32 hex characters.
  final parts = hash.split(r'$');
  print('hash parts: ${parts.length}');
  print('salt hex length: ${parts[0].length}');

  // The spec is the default Argon2 recipe.
  print('spec: $spec');

  // Verifying with a tampered spec (2 iterations instead of 4) derives a
  // different key, so it fails — the spec is part of the credential.
  const tamperedSpec = 'Argon2;2i,13,2,65536,4,128';
  print('verify, correct spec: '
      '${TomPasswordHasher.verifyPassword(password, hash, spec)}');
  print('verify, tampered spec: '
      '${TomPasswordHasher.verifyPassword(password, hash, tamperedSpec)}');

  // The format rests on hex encoding. The helpers round-trip bytes <-> hex.
  final bytes = Uint8List.fromList([0, 10, 255]);
  final hex = TomPasswordHasher.toHexString(bytes);
  final back = TomPasswordHasher.toUint8List(hex);
  print('toHexString([0,10,255]): $hex');
  print('round-trips: ${back.toList()}');

  // expected output:
  // hash parts: 2
  // salt hex length: 32
  // spec: Argon2;2i,13,4,65536,4,128
  // verify, correct spec: true
  // verify, tampered spec: false
  // toHexString([0,10,255]): 000aff
  // round-trips: [0, 10, 255]
}
