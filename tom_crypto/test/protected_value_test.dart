/// `TomProtectedValue`: the secret leaves the object only through `reveal()`.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:tom_crypto/protected_value.dart';

void main() {
  group('PROTECTED: a secret behind one accessor', () {
    test(
      'PROTECTED-1: reveal() gives back the plaintext, multibyte included',
      () {
        final value = TomProtectedValue.of('pässwörd 🔑');
        expect(value.reveal(), 'pässwörd 🔑');
        expect(value.length, utf8.encode('pässwörd 🔑').length);
        expect(TomProtectedValue.of('').isEmpty, isTrue);
      },
    );

    test('PROTECTED-2: toString() and interpolation show the mask, never the '
        'secret', () {
      final value = TomProtectedValue.of('hunter2');
      expect(value.toString(), 'TomProtectedValue(${TomProtectedValue.mask})');
      expect('${{'password': value}}', isNot(contains('hunter2')));
    });

    test('PROTECTED-3: equality is by digest; the same secret twice is equal, '
        'another is not', () {
      final a = TomProtectedValue.of('same');
      final b = TomProtectedValue.of('same');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.digest, b.digest);
      expect(a, isNot(TomProtectedValue.of('other')));
    });

    test('PROTECTED-4: jsonEncode refuses rather than writing the secret', () {
      expect(
        () => jsonEncode({'password': TomProtectedValue.of('hunter2')}),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
    });
  });
}
