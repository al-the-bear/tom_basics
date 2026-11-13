/// MlDsa65's behaviour beyond the known answers.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_pqc/src/pqc_backend.dart';
import 'package:tom_pqc/tom_pqc.dart';

void main() {
  final message = Uint8List.fromList(utf8.encode('approve grant 42'));

  test('the sizes are FIPS 204 ML-DSA-65 sizes', () {
    expect(MlDsa65.publicKeyLength, 1952);
    expect(MlDsa65.secretKeyLength, 4032);
    expect(MlDsa65.signatureLength, 3309);
    expect(MlDsa65.seedLength, 32);
    expect(MlDsa65.maxContextLength, 255);
  });

  test('a generated pair signs and verifies; signing is hedged', () {
    final pair = MlDsa65.generateKeyPair();
    addTearDown(pair.dispose);
    expect(pair.seed!.length, MlDsa65.seedLength);
    final a = MlDsa65.sign(message, pair.secretKey);
    final b = MlDsa65.sign(message, pair.secretKey);
    expect(a, hasLength(MlDsa65.signatureLength));
    expect(a, isNot(b), reason: 'fresh randomness in each signature');
    expect(MlDsa65.verify(message, a, pair.publicKey), isTrue);
    expect(MlDsa65.verify(message, b, pair.publicKey), isTrue);
  });

  test('the context separates uses of one key', () {
    final pair = MlDsa65.generateKeyPair();
    addTearDown(pair.dispose);
    final ctx = Uint8List.fromList(utf8.encode('tom_secrets/grant'));
    final sig = MlDsa65.sign(message, pair.secretKey, context: ctx);
    expect(MlDsa65.verify(message, sig, pair.publicKey, context: ctx), isTrue);
    expect(MlDsa65.verify(message, sig, pair.publicKey), isFalse);
    expect(
      () => MlDsa65.sign(message, pair.secretKey, context: Uint8List(256)),
      throwsArgumentError,
    );
    expect(
      MlDsa65.verify(message, sig, pair.publicKey, context: Uint8List(256)),
      isFalse,
    );
  });

  test('a seed determines its pair; an expanded key gives its public key', () {
    final seed = MlDsa65.generateSeed();
    final again = SecretBytes.fromBytes(seed.extractBytes());
    final a = MlDsa65.keyPairFromSeed(seed);
    final b = MlDsa65.keyPairFromSeed(again);
    final c = MlDsa65.keyPairFromSecretKey(
      SecretBytes.fromBytes(a.secretKey.extractBytes()),
    );
    for (final p in [a, b, c]) {
      addTearDown(p.dispose);
    }
    expect(a.publicKey, b.publicKey);
    expect(c.publicKey, a.publicKey);
    expect(c.seed, isNull);
  });

  test('tampering, wrong keys and malformed input fail verification', () {
    final pair = MlDsa65.generateKeyPair();
    final other = MlDsa65.generateKeyPair();
    addTearDown(pair.dispose);
    addTearDown(other.dispose);
    final sig = MlDsa65.sign(message, pair.secretKey);
    expect(MlDsa65.verify(message, sig, other.publicKey), isFalse);
    expect(
      MlDsa65.verify(Uint8List.fromList([...message, 0]), sig, pair.publicKey),
      isFalse,
    );
    expect(
      MlDsa65.verify(
        message,
        Uint8List.fromList(sig)..[100] ^= 1,
        pair.publicKey,
      ),
      isFalse,
    );
    expect(MlDsa65.verify(message, sig.sublist(1), pair.publicKey), isFalse);
    expect(MlDsa65.verify(message, sig, pair.publicKey.sublist(1)), isFalse);
  });

  test('wrong lengths are argument errors, not native reads', () {
    final short = SecretBytes.allocate(31);
    final shortKey = SecretBytes.allocate(100);
    addTearDown(short.dispose);
    addTearDown(shortKey.dispose);
    expect(() => MlDsa65.keyPairFromSeed(short), throwsArgumentError);
    expect(() => MlDsa65.keyPairFromSecretKey(shortKey), throwsArgumentError);
    expect(() => MlDsa65.sign(message, shortKey), throwsArgumentError);
  });

  test('the ML-DSA backend names the vendored code and its pinned commit', () {
    expect(
      pqcBackend.mlDsaName,
      contains(
        'mldsa-native v2.0.0 (834a90d5e846ffa1e1611bd24e160bb2e9b86d35)',
      ),
    );
  });
}
