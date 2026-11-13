/// `TomProtectedValue`: the secret leaves the object only through `reveal()`.
library;

import 'dart:convert';
import 'dart:typed_data';

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

    test('PROTECTED-5: fromBytes protects any bytes and zeroes the buffer it '
        'was given', () {
      final input = Uint8List.fromList([0, 1, 2, 250, 255]);
      final value = TomProtectedValue.fromBytes(input);
      expect(input, everyElement(0), reason: 'the buffer is consumed');
      expect(value.length, 5);
      expect(value.withRevealed(Uint8List.fromList), [0, 1, 2, 250, 255]);
      expect(
        TomProtectedValue.of('abc'),
        TomProtectedValue.fromBytes(Uint8List.fromList(utf8.encode('abc'))),
      );
    });

    test('PROTECTED-6: withRevealed zeroes the bytes after the callback, '
        'also when it throws', () {
      final value = TomProtectedValue.of('hunter2');
      late Uint8List seen;
      final text = value.withRevealed((bytes) {
        seen = bytes;
        return utf8.decode(bytes);
      });
      expect(text, 'hunter2');
      expect(seen, everyElement(0));
      expect(
        () => value.withRevealed<void>((bytes) {
          seen = bytes;
          throw const FormatException('demo');
        }),
        throwsFormatException,
      );
      expect(seen, hasLength(7));
      expect(seen, everyElement(0));
    });

    test('PROTECTED-7: revealInto writes at an offset and checks the room', () {
      final value = TomProtectedValue.of('ab');
      final target = Uint8List(4);
      value.revealInto(target, 1);
      expect(target, [0, 0x61, 0x62, 0]);
      expect(() => value.revealInto(Uint8List(2), 1), throwsRangeError);
    });

    test('PROTECTED-8: dispose zeroes the masked bytes and the salt; reading '
        'afterwards fails, the digest stays', () {
      final value = TomProtectedValue.of('hunter2');
      final digest = value.digest;
      value.dispose();
      expect(value.isDisposed, isTrue);
      expect(value.reveal, throwsStateError);
      expect(() => value.withRevealed((b) => b.length), throwsStateError);
      expect(() => value.revealInto(Uint8List(7)), throwsStateError);
      expect(value.digest, digest);
      expect(value.length, 7);
      expect(value, TomProtectedValue.of('hunter2'));
      value.dispose();
    });
  });
}
