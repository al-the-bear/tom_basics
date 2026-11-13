/// SHA3-256 and SHAKE256 against FIPS 202's published examples.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_pqc/tom_pqc.dart';

import 'support/hex.dart';

void main() {
  test('SHA3-256 of "" and "abc"', () {
    expect(
      toHex(Sha3.sha3256(Uint8List(0))),
      'A7FFC6F8BF1ED76651C14756A061D662F580FF4DE43B49FA82D80A4B80F8434A',
    );
    expect(
      toHex(Sha3.sha3256(Uint8List.fromList(utf8.encode('abc')))),
      '3A985DA74FE225B2045C172D6BD390BD855F086E3E9D525B46BFE24511431532',
    );
  });

  test('SHAKE256 of "" and "abc", 32 bytes', () {
    expect(
      toHex(Sha3.shake256(Uint8List(0), 32)),
      '46B9DD2B0BA88D13233B3FEB743EEB243FCD52EA62B81B82B50C27646ED5762F',
    );
    expect(
      toHex(Sha3.shake256(Uint8List.fromList(utf8.encode('abc')), 32)),
      '483366601360A8771C6863080CC4114D8DB44530F8F1E1EE4F94EA37E78B5739',
    );
  });

  test('the secret variants give the same bytes in native memory', () {
    final input = SecretBytes.fromBytes(Uint8List.fromList(utf8.encode('abc')));
    final h = Sha3.sha3256Secret(input);
    final x = Sha3.shake256Secret(input, 64);
    for (final s in [input, h, x]) {
      addTearDown(s.dispose);
    }
    expect(
      h.extractBytes(),
      Sha3.sha3256(Uint8List.fromList(utf8.encode('abc'))),
    );
    expect(
      x.extractBytes(),
      Sha3.shake256(Uint8List.fromList(utf8.encode('abc')), 64),
    );
  });
}
