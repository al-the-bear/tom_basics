/// MLKEM768-X25519 (X-Wing): the known answers of
/// draft-connolly-cfrg-xwing-kem (test/vectors/xwing/, at the commit
/// SOURCE.json names), and the KEM's behaviour.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:tom_pqc/tom_pqc.dart';

import 'support/hex.dart';

void main() {
  final source =
      jsonDecode(File('test/vectors/xwing/SOURCE.json').readAsStringSync())
          as Map<String, dynamic>;
  final vectors =
      (jsonDecode(
                File('test/vectors/xwing/test-vectors.json').readAsStringSync(),
              )
              as List)
          .cast<Map<String, dynamic>>();

  test('the X-Wing vectors are the pinned file, unchanged', () {
    expect(
      sha256
          .convert(
            File('test/vectors/xwing/test-vectors.json').readAsBytesSync(),
          )
          .toString(),
      (source['sha256'] as Map)['test-vectors.json'],
    );
    expect(vectors, hasLength(3));
  });

  group('draft-connolly-cfrg-xwing-kem vectors', () {
    for (final (i, v) in vectors.indexed) {
      test('vector $i', () async {
        expect(v['sk'], v['seed'], reason: 'the secret key is the seed');
        final seed = SecretBytes.fromBytes(hex(v['seed'] as String));
        final pair = await MlKem768X25519.keyPairFromSeed(seed);
        addTearDown(pair.dispose);
        expect(toHex(pair.publicKey), (v['pk'] as String).toUpperCase());

        final sent = await MlKem768X25519.encapsulateWithSeed(
          pair.publicKey,
          hex(v['eseed'] as String),
        );
        addTearDown(sent.sharedSecret.dispose);
        expect(toHex(sent.ciphertext), (v['ct'] as String).toUpperCase());
        expect(
          toHex(sent.sharedSecret.extractBytes()),
          (v['ss'] as String).toUpperCase(),
        );

        final got = await MlKem768X25519.decapsulate(
          hex(v['ct'] as String),
          pair.secretKey,
        );
        addTearDown(got.dispose);
        expect(toHex(got.extractBytes()), (v['ss'] as String).toUpperCase());
      });
    }
  });

  test('the sizes are X-Wing\'s', () {
    expect(MlKem768X25519.publicKeyLength, 1216);
    expect(MlKem768X25519.secretKeyLength, 32);
    expect(MlKem768X25519.ciphertextLength, 1120);
    expect(MlKem768X25519.sharedSecretLength, 32);
    expect(utf8.decode(MlKem768X25519.label), r'\.//^\');
  });

  test('a generated pair round-trips; another key gets an unrelated '
      'secret', () async {
    final alice = await MlKem768X25519.generateKeyPair();
    final eve = await MlKem768X25519.generateKeyPair();
    addTearDown(alice.dispose);
    addTearDown(eve.dispose);
    final sent = await MlKem768X25519.encapsulate(alice.publicKey);
    final got = await MlKem768X25519.decapsulate(
      sent.ciphertext,
      alice.secretKey,
    );
    final wrong = await MlKem768X25519.decapsulate(
      sent.ciphertext,
      eve.secretKey,
    );
    for (final s in [sent.sharedSecret, got, wrong]) {
      addTearDown(s.dispose);
    }
    expect(got.extractBytes(), sent.sharedSecret.extractBytes());
    expect(wrong.extractBytes(), isNot(sent.sharedSecret.extractBytes()));
    expect(await MlKem768X25519.publicKey(alice.secretKey), alice.publicKey);
  });

  test('a low-order X25519 share is refused, both ways', () async {
    final pair = await MlKem768X25519.generateKeyPair();
    addTearDown(pair.dispose);
    final sent = await MlKem768X25519.encapsulate(pair.publicKey);
    addTearDown(sent.sharedSecret.dispose);
    // The identity point (all zero) and a point of order 8.
    final lowOrder = [
      Uint8List(32),
      hex('5F9C95BCA3508C24B1D0B1559C83EF5B04445CC4581C8E86D8224EDDD09F11D7'),
    ];
    for (final point in lowOrder) {
      final ct = Uint8List.fromList([
        ...sent.ciphertext.sublist(0, MlKem768.ciphertextLength),
        ...point,
      ]);
      await expectLater(
        MlKem768X25519.decapsulate(ct, pair.secretKey),
        throwsA(isA<TomPqcException>()),
      );
      final pk = Uint8List.fromList([
        ...pair.publicKey.sublist(0, MlKem768.publicKeyLength),
        ...point,
      ]);
      await expectLater(
        MlKem768X25519.encapsulate(pk),
        throwsA(isA<TomPqcException>()),
      );
    }
  });

  test('wrong lengths are argument errors', () async {
    final pair = await MlKem768X25519.generateKeyPair();
    addTearDown(pair.dispose);
    await expectLater(
      MlKem768X25519.encapsulate(Uint8List(1215)),
      throwsArgumentError,
    );
    await expectLater(
      MlKem768X25519.decapsulate(Uint8List(1119), pair.secretKey),
      throwsArgumentError,
    );
    final short = SecretBytes.allocate(31);
    addTearDown(short.dispose);
    await expectLater(
      MlKem768X25519.keyPairFromSeed(short),
      throwsArgumentError,
    );
  });
}
