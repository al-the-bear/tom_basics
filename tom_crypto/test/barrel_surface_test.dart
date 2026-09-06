/// Guards the rule that this package exports every type its own public API
/// names.
///
/// A package whose public API mentions a type the consumer cannot name has an
/// API the consumer cannot use. That is not hypothetical here: all four
/// positional parameters of `TomJwtConfiguration`'s constructor were once such
/// types, so the class could not be constructed from outside at all — not even
/// in the way its own dartdoc documents — and every downstream example that
/// wanted to show a production configuration printed the code as prose instead
/// of running it.
///
/// The guard is deliberately a *compile-time* one. It imports nothing but the
/// barrel and then names each type in a declaration, so losing an export stops
/// this file from compiling rather than failing an assertion inside it. An
/// assertion could only check a value, and what is at stake is whether a name
/// resolves.
library;

import 'package:tom_crypto/tom_crypto.dart';
import 'package:test/test.dart';

/// Every type named by the public surface of `TomJwtConfiguration`.
///
/// The parameter list mirrors the constructor exactly, so a change to that
/// signature that reaches for a fresh unexported type breaks this file.
TomJwtConfiguration _configuration(
  JWTKey key,
  JWTAlgorithm algorithm,
  RSAPrivateKey rsaPrivateKey,
  RSAPublicKey rsaPublicKey,
) => TomJwtConfiguration(key, algorithm, rsaPrivateKey, rsaPublicKey, false);

/// Every type named by the public surface of [TomClientJwtToken].
///
/// `token` and `audience` are readable properties whose types a caller has to
/// be able to write down to hold the result in anything but `var`.
(JWT, Audience?) _clientTokenTypes(TomClientJwtToken token) =>
    (token.token, token.audience);

void main() {
  group('the tom_crypto barrel', () {
    test('exports the types its own public API names', () {
      // Reaching this line means the declarations above compiled, which is the
      // assertion. The body then shows the surface is usable in practice and
      // not merely nameable: a configuration is built from exported names
      // only, and a token signed with it round-trips.
      final custom = _configuration(
        SecretKey('a-secret-of-our-own'),
        JWTAlgorithm.HS512,
        TomJwtConfiguration.rsaPrivKey,
        TomJwtConfiguration.rsaPubKey,
      );
      expect(custom.isDummy, isFalse);

      final signed = TomServerJwtToken(
        {'userId': 'user-1'},
        encryptedData: {'apiKey': 'k-9'},
        signingConfiguration: custom,
      ).getJWT('barrel-test-issuer');

      final parsed = TomClientJwtToken(signed, signingConfiguration: custom);
      final (token, audience) = _clientTokenTypes(parsed);

      expect(token.issuer, 'barrel-test-issuer');
      expect(audience, isNull, reason: 'no audience claim was set');
      expect(parsed.secretData, {'apiKey': 'k-9'});
    });
  });
}
