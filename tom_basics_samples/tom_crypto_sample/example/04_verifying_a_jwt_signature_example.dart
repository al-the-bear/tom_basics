/// Example 04 — Verifying a JWT signature.
///
/// Reading a token's claims ([TomClientJwtToken], example 3) *decodes* it but
/// does not prove it is authentic — anyone can craft a JSON payload. Trust comes
/// from the **signature**: only a holder of the signing key can produce one that
/// checks out. `tom_crypto` signs with the key in
/// [TomJwtConfiguration] (HS256 over a shared secret), and verification is the
/// `JWT.verify` call from `dart_jsonwebtoken`.
///
/// This example issues a token, verifies it with the correct secret (success),
/// then with a wrong secret (rejected with `invalid signature`). It also shows
/// that plain `decode` skips the check entirely — decode to *read*, verify to
/// *trust*.
library;

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:tom_crypto/tom_crypto.dart';

void main() {
  final token =
      TomServerJwtToken({'userId': 'u-7'}, expiresIn: const Duration(hours: 1))
          .getJWT('tom-auth');

  // Correct secret: verification succeeds and returns the decoded token. The
  // signing secret lives in TomJwtConfiguration.hmacKey.
  final verified = JWT.verify(token, TomJwtConfiguration.hmacKey);
  print('verified issuer: ${verified.issuer}');

  // Wrong secret: the signature does not match, so verify throws.
  try {
    JWT.verify(token, SecretKey('attacker-guess'));
    print('UNREACHABLE');
  } on JWTException catch (e) {
    print('wrong key rejected: ${e.message}');
  }

  // decode() parses claims WITHOUT checking the signature — never trust it on
  // its own.
  final decoded = JWT.decode(token);
  print('decode ignores signature: ${decoded.issuer}');

  // expected output:
  // verified issuer: tom-auth
  // wrong key rejected: invalid signature
  // decode ignores signature: tom-auth
}
