/// Example 05 — An encrypted JWT payload.
///
/// JWT claims are only *encoded*, not encrypted — anyone holding the token can
/// read them. For genuinely sensitive data, `tom_crypto` adds an **encrypted
/// section**: values passed as `encryptedData` are RSA-encrypted into a single
/// opaque `encrypted` claim, readable only by a holder of the private key.
///
/// The server packs `sessionSecret` and `scopes` into the encrypted section;
/// the public payload then carries only the opaque blob, never the plaintext.
/// A client that decrypts recovers them as `secretData`. We use a *non-dummy*
/// [TomJwtConfiguration] built from the development keys so the round trip runs
/// without the library's "dummy configuration" warning.
library;

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:tom_crypto/tom_crypto.dart';

void main() {
  // Reuse the development keys, but mark the config non-dummy (last arg false)
  // so encrypt/decrypt do not print a warning.
  final config = TomJwtConfiguration(
    TomJwtConfiguration.hmacKey,
    JWTAlgorithm.HS256,
    TomJwtConfiguration.rsaPrivKey,
    TomJwtConfiguration.rsaPubKey,
    false,
  );

  final token = TomServerJwtToken(
    {'userId': 'u-9', 'role': 'user'},
    encryptedData: {
      'sessionSecret': 's3cr3t',
      'scopes': ['read', 'write'],
    },
    expiresIn: const Duration(hours: 1),
    signingConfiguration: config,
  ).getJWT('tom-auth');

  // Without decryption, the public payload holds an opaque blob — not the
  // secret values.
  final raw =
      TomClientJwtToken(token, signingConfiguration: config, decrypt: false);
  print('public has encrypted blob: ${raw.payload?.containsKey('encrypted')}');
  print('public exposes sessionSecret: '
      '${raw.payload?.containsKey('sessionSecret')}');

  // With decryption, secretData is the recovered map.
  final client = TomClientJwtToken(token, signingConfiguration: config);
  print('sessionSecret: ${client.secretData?['sessionSecret']}');
  print('scopes: ${client.secretData?['scopes']}');

  // expected output:
  // public has encrypted blob: true
  // public exposes sessionSecret: false
  // sessionSecret: s3cr3t
  // scopes: [read, write]
}
