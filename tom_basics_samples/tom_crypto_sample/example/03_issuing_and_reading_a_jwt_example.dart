/// Example 03 — Issuing and reading a JWT.
///
/// A JSON Web Token is a signed, self-describing credential: a server packs
/// claims into it, signs it, and hands it to a client; the client (or any
/// service holding the key) reads the claims back. `tom_crypto` splits the two
/// roles cleanly — [TomServerJwtToken] *issues*, [TomClientJwtToken] *reads*.
///
/// Here the server issues a token carrying public claims (`userId`, `role`) for
/// an issuer, and the client decodes it and reads those claims plus the
/// issuer. The token string itself embeds timestamps (`iat`, `exp`, `validFrom`,
/// `validUntil`) that change every run, so we print the stable claims and the
/// token's structure (three dot-separated segments), not the token bytes.
library;

import 'package:tom_crypto/tom_crypto.dart';

void main() {
  // Server side: pack public claims and sign.
  final server = TomServerJwtToken(
    {'userId': 'u-123', 'role': 'admin'},
    expiresIn: const Duration(hours: 1),
  );
  final jwtString = server.getJWT('tom-auth');

  // A JWT is header.payload.signature — three base64url segments.
  print('token segments: ${jwtString.split('.').length}');

  // Client side: decode and read the claims back.
  final client = TomClientJwtToken(jwtString);
  print('issuer: ${client.issuer}');
  print('userId: ${client.payload?['userId']}');
  print('role:   ${client.payload?['role']}');

  // The library also stamps a validity window into the public payload.
  print('has validUntil claim: ${client.payload?.containsKey('validUntil')}');

  // No encrypted section was added, so there is no secret data to unwrap.
  print('secretData: ${client.secretData}');

  // expected output:
  // token segments: 3
  // issuer: tom-auth
  // userId: u-123
  // role:   admin
  // has validUntil claim: true
  // secretData: null
}
