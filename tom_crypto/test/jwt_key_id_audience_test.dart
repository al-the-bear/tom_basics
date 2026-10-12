/// The key id and audience a server writes into the tokens it issues.
///
/// A verifier holding several keys — a key being retired beside its successor —
/// picks the one to check a token against by the `kid` header; a token naming
/// its audience lets a verifier refuse one minted for another service.
library;

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart' as jwt;
import 'package:test/test.dart';
import 'package:tom_crypto/tom_crypto.dart';

TomJwtConfiguration _rsaConfiguration({String? keyId}) => TomJwtConfiguration(
  jwt.RSAPrivateKey.raw(TomJwtConfiguration.rsaPrivKey),
  jwt.JWTAlgorithm.RS256,
  TomJwtConfiguration.rsaPrivKey,
  TomJwtConfiguration.rsaPubKey,
)..keyId = keyId;

void main() {
  group('the key id', () {
    test('is written as the kid header when the configuration has one', () {
      final token = TomServerJwtToken(
        {'username': 'ada'},
        signingConfiguration: _rsaConfiguration(keyId: 'key-2026-10'),
      ).getJWT('tom');
      final decoded = jwt.JWT.decode(token);
      expect(decoded.header?['kid'], 'key-2026-10');
      expect(decoded.header?['alg'], 'RS256');
    });

    test('is absent when the configuration has none', () {
      final token = TomServerJwtToken({
        'username': 'ada',
      }, signingConfiguration: _rsaConfiguration()).getJWT('tom');
      expect(jwt.JWT.decode(token).header?.containsKey('kid'), isFalse);
    });

    test('an asymmetric token verifies against the public key', () {
      final token = TomServerJwtToken({
        'username': 'ada',
      }, signingConfiguration: _rsaConfiguration(keyId: 'k')).getJWT('tom');
      final verified = jwt.JWT.verify(
        token,
        jwt.RSAPublicKey.raw(TomJwtConfiguration.rsaPubKey),
        issuer: 'tom',
      );
      expect((verified.payload as Map)['username'], 'ada');
    });
  });

  group('the audience', () {
    test('is written as the aud claim when given', () {
      final token = TomServerJwtToken({
        'username': 'ada',
      }, audience: 'orders-api').getJWT('tom');
      expect(TomClientJwtToken(token, decrypt: false).audience, ['orders-api']);
    });

    test('is absent when not given', () {
      final token = TomServerJwtToken({'username': 'ada'}).getJWT('tom');
      expect(TomClientJwtToken(token, decrypt: false).audience, isNull);
    });
  });
}
