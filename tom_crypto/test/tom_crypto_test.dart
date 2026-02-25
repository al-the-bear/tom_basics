import 'dart:convert';
import 'dart:typed_data';

import 'package:tom_crypto/tom_crypto.dart';
import 'package:test/test.dart';

void main() {
  group('TomPasswordHasher', () {
    test('hashPassword generates hash and spec', () {
      final (hash, spec) = TomPasswordHasher.hashPassword('testPassword123');

      expect(hash, isNotEmpty);
      expect(spec, isNotEmpty);
      expect(hash, contains('\$')); // Format: salt$hash
      expect(spec, startsWith('Argon2'));
    });

    test('verifyPassword returns true for correct password', () {
      final (hash, spec) = TomPasswordHasher.hashPassword('mySecurePassword');

      final result = TomPasswordHasher.verifyPassword(
        'mySecurePassword',
        hash,
        spec,
      );

      expect(result, isTrue);
    });

    test('verifyPassword returns false for incorrect password', () {
      final (hash, spec) = TomPasswordHasher.hashPassword('correctPassword');

      final result = TomPasswordHasher.verifyPassword(
        'wrongPassword',
        hash,
        spec,
      );

      expect(result, isFalse);
    });
  });

  group('RsaKeyHelper', () {
    test('getSecureRandom returns a SecureRandom', () {
      final random = RsaKeyHelper.getSecureRandom();

      expect(random, isNotNull);
    });

    test('parsePublicKeyFromPem parses valid PEM', () {
      const pem = '''
-----BEGIN PUBLIC KEY-----
MIIBCgKCAQEApobMwJj9SxpZbk0fcG8Awv9PCiO4/GsPimeH398D+Qt1kUrrMqvm5+AYLh1PcIgE/V+QiFTgBv9Fpuu5YtrnF+oi/dg23MUKPA0yXzHjTyshm3P2uhIRN4c6fVru5HF3HXGh5POR1A6kGW9IGbeKhLCG1yyoNDGzHdrdwNEREw3N6KEKAN4swXOMau7rhaRXTkOWTSyPwhAEI+ZrwTnHBIDsVouqPQ0yAX7vTGK1UFNPGmh7itLECj8WgbxgElyrPgtDknmXmfCzrn3DMJeGbuq9dzl0z5DZysrR3nEqIQB8xnDLkkejjnmn1YOflaZMql3mKSJeJ9KxPUZ+u+6DcwIDAQAB
-----END PUBLIC KEY-----
''';

      final publicKey = RsaKeyHelper.parsePublicKeyFromPem(pem);

      expect(publicKey, isNotNull);
      expect(publicKey.modulus, isNotNull);
    });
  });

  group('RSA Encryption', () {
    late dynamic publicKey;
    late dynamic privateKey;

    setUpAll(() {
      // Use the development keys from TomJwtConfiguration
      const privPem = '''
-----BEGIN PRIVATE KEY-----
MIIFowIBAAKCAQEApobMwJj9SxpZbk0fcG8Awv9PCiO4/GsPimeH398D+Qt1kUrrMqvm5+AYLh1PcIgE/V+QiFTgBv9Fpuu5YtrnF+oi/dg23MUKPA0yXzHjTyshm3P2uhIRN4c6fVru5HF3HXGh5POR1A6kGW9IGbeKhLCG1yyoNDGzHdrdwNEREw3N6KEKAN4swXOMau7rhaRXTkOWTSyPwhAEI+ZrwTnHBIDsVouqPQ0yAX7vTGK1UFNPGmh7itLECj8WgbxgElyrPgtDknmXmfCzrn3DMJeGbuq9dzl0z5DZysrR3nEqIQB8xnDLkkejjnmn1YOflaZMql3mKSJeJ9KxPUZ+u+6DcwKCAQAvUp9dHBze+t3vOnt0uBa/U05i00P+d24zJri2Jeo7G8aNQ30TKUa1HjnA4RNyJzVDy6SHGZeQZXqltNc6AHsrkJ3hBVCR7Gy8JAPsiYDPPrKOOqYiun+qCAPXG8BHqvbupxwatBz85iw8DiOvKzlx+7hV7ZrfOkBse4YJBWCUySF/T+ZVdM3kqoMtfegnGa2AWmGa09qDoCBt1TAHVtNDAu/1UnbvjlHTJ6NFfboibortCRBicmhAu1jcbW6dn9/J9naXlkYxRK22uItXKunv/dqmDQ+lRE9KuKArexYweenHd3yuExuXGOR9XM8vJtgZqTR8WYRDbeWgNQMwXSoBAoIBAC9Sn10cHN763e86e3S4Fr9TTmLTQ/53bjMmuLYl6jsbxo1DfRMpRrUeOcDhE3InNUPLpIcZl5BleqW01zoAeyuQneEFUJHsbLwkA+yJgM8+so46piK6f6oIA9cbwEeq9u6nHBq0HPzmLDwOI68rOXH7uFXtmt86QGx7hgkFYJTJIX9P5lV0zeSqgy196CcZrYBaYZrT2oOgIG3VMAdW00MC7/VSdu+OUdMno0V9uiJuiu0JEGJyaEC7WNxtbp2f38n2dpeWRjFErba4i1cq6e/92qYND6VET0q4oCt7FjB56cd3fK4TG5cY5H1czy8m2BmpNHxZhENt5aA1AzBdKgECgYEA5QjshbsxGUmtMLSFXPn3Y2KW9e2K0r2itb5A2PRB+28aDiFArPmWVhvRujS8KG78NUBwWq/c2c8bET/6j1y0qIsy/2ZBWmoKTSyIbrxybzalMpOWQ5Y37CKypG73EQtigHmuZ6TN0Tr9vkY/q+o+wilVF+EIzcj39WAherAKHwcCgYEAuiHin+jukcxVNKy4bz8dRkHHbmCoCv12fNSihhemfrE/daCWCY1J+VkCrB1a5iuOx6huDAYHXMWl3jjfkvoTX1/YQjhb5f2bMqrHjkyw86k1j6yMdgfO+AG3sqhIz3fszMaVd6UfE7mwwaqE4QfppAJWBvKS9SQaY7KNN2+8cTUCgYB3qPHp7KL6U0Po7me+69oUUq4MTs74y5r22S+IKhVPB/zU5QqlVMD2vBIW9vZXKaUbLU+GEduQ8GNz37lIrWa1qAQ862+5jS1UpK+jK1GeSS6F/hXDuff9pyMuRctPXGNaPDiibbgaWHe5sXoSl4+yYWXT0/6FhToHOPJE5zRigQKBgQCpx2zTFgI+xVZXNNEK0FQgmLGT0eCWHbpthPs2Ou5ok77hyXfyAImgQvu4CRK37rVPEyhGGV2v1q1EdTYh96+iCGfXh1b0A48D+VkLSJMDvq2XfvmkU90KxW5NLUk0zRwXcXA28UvWj0NWc/a+2JvaOTNFJRC9QJA9rkk3btlBnQKBgQCTT4oMD16jRtyxwK+cczzxPX3P4FtZHuppBetUmuq+2xFTvdB/ivUARXcYhibG09+AC1heYtImy+pRXxMPnKXimFFvimJMT4edBq0w2XA33VDoG+xeYM6G0c3bHbk53DTNk+lr4GirKMSe6kYFV3Fo9kmnvW0N9ttLfFQqds+LUg==
-----END PRIVATE KEY-----
''';

      const pubPem = '''
-----BEGIN PUBLIC KEY-----
MIIBCgKCAQEApobMwJj9SxpZbk0fcG8Awv9PCiO4/GsPimeH398D+Qt1kUrrMqvm5+AYLh1PcIgE/V+QiFTgBv9Fpuu5YtrnF+oi/dg23MUKPA0yXzHjTyshm3P2uhIRN4c6fVru5HF3HXGh5POR1A6kGW9IGbeKhLCG1yyoNDGzHdrdwNEREw3N6KEKAN4swXOMau7rhaRXTkOWTSyPwhAEI+ZrwTnHBIDsVouqPQ0yAX7vTGK1UFNPGmh7itLECj8WgbxgElyrPgtDknmXmfCzrn3DMJeGbuq9dzl0z5DZysrR3nEqIQB8xnDLkkejjnmn1YOflaZMql3mKSJeJ9KxPUZ+u+6DcwIDAQAB
-----END PUBLIC KEY-----
''';

      privateKey = RsaKeyHelper.parsePrivateKeyFromPem(privPem);
      publicKey = RsaKeyHelper.parsePublicKeyFromPem(pubPem);
    });

    test('rsaEncrypt and rsaDecrypt round-trip', () {
      final plaintext = utf8.encode('Hello, World!');
      final encrypted = rsaEncrypt(publicKey, Uint8List.fromList(plaintext));
      final decrypted = rsaDecrypt(privateKey, encrypted);

      expect(utf8.decode(decrypted), equals('Hello, World!'));
    });

    test('rsaSign and rsaVerify work correctly', () {
      final data = utf8.encode('Data to sign');
      final signature = rsaSign(privateKey, Uint8List.fromList(data));

      expect(rsaVerify(publicKey, Uint8List.fromList(data), signature), isTrue);
    });

    test('rsaVerify returns false for tampered data', () {
      final data = utf8.encode('Original data');
      final signature = rsaSign(privateKey, Uint8List.fromList(data));
      final tamperedData = utf8.encode('Tampered data');

      expect(
        rsaVerify(publicKey, Uint8List.fromList(tamperedData), signature),
        isFalse,
      );
    });
  });

  group('TomJwtTokenException', () {
    test('creates exception with key and message', () {
      final exception = TomJwtTokenException(
        'jwt.error.expired',
        'Token has expired',
      );

      expect(exception.key, equals('jwt.error.expired'));
      expect(exception.defaultUserMessage, equals('Token has expired'));
    });
  });
}
