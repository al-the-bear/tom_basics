/// MlKem768's behaviour beyond the known answers: round trips, seeds, input
/// checks, implicit rejection, the backend and the random generator.
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_pqc/src/pqc_backend.dart';
import 'package:tom_pqc/tom_pqc.dart';

void main() {
  test('the sizes are FIPS 203 ML-KEM-768 sizes', () {
    expect(MlKem768.publicKeyLength, 1184);
    expect(MlKem768.secretKeyLength, 2400);
    expect(MlKem768.ciphertextLength, 1088);
    expect(MlKem768.sharedSecretLength, 32);
    expect(MlKem768.seedLength, 64);
  });

  test('a generated pair round-trips a shared secret', () {
    final pair = MlKem768.generateKeyPair();
    addTearDown(pair.dispose);
    expect(pair.publicKey, hasLength(MlKem768.publicKeyLength));
    expect(pair.secretKey.length, MlKem768.secretKeyLength);
    expect(MlKem768.isValidPublicKey(pair.publicKey), isTrue);
    expect(MlKem768.isValidSecretKey(pair.secretKey), isTrue);

    final sent = MlKem768.encapsulate(pair.publicKey);
    final received = MlKem768.decapsulate(sent.ciphertext, pair.secretKey);
    addTearDown(sent.sharedSecret.dispose);
    addTearDown(received.dispose);
    expect(sent.ciphertext, hasLength(MlKem768.ciphertextLength));
    expect(received.extractBytes(), sent.sharedSecret.extractBytes());
  });

  test('two generated pairs and two encapsulations differ', () {
    final a = MlKem768.generateKeyPair();
    final b = MlKem768.generateKeyPair();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    expect(a.publicKey, isNot(b.publicKey));
    final first = MlKem768.encapsulate(a.publicKey);
    final second = MlKem768.encapsulate(a.publicKey);
    addTearDown(first.sharedSecret.dispose);
    addTearDown(second.sharedSecret.dispose);
    expect(first.ciphertext, isNot(second.ciphertext));
    expect(
      first.sharedSecret.extractBytes(),
      isNot(second.sharedSecret.extractBytes()),
    );
  });

  test('a seed determines its pair; a generated seed is fresh', () {
    final seed = MlKem768.generateSeed();
    final again = SecretBytes.fromBytes(seed.extractBytes());
    final other = MlKem768.generateSeed();
    final a = MlKem768.keyPairFromSeed(seed);
    final b = MlKem768.keyPairFromSeed(again);
    final c = MlKem768.keyPairFromSeed(other);
    for (final s in [seed, again, other]) {
      addTearDown(s.dispose);
    }
    for (final pair in [a, b, c]) {
      addTearDown(pair.dispose);
    }
    expect(seed.length, MlKem768.seedLength);
    expect(a.publicKey, b.publicKey);
    expect(a.secretKey.extractBytes(), b.secretKey.extractBytes());
    expect(a.publicKey, isNot(c.publicKey));
  });

  test('a ciphertext for another key decapsulates to an unrelated secret', () {
    final alice = MlKem768.generateKeyPair();
    final eve = MlKem768.generateKeyPair();
    addTearDown(alice.dispose);
    addTearDown(eve.dispose);
    final sent = MlKem768.encapsulate(alice.publicKey);
    final wrong = MlKem768.decapsulate(sent.ciphertext, eve.secretKey);
    addTearDown(sent.sharedSecret.dispose);
    addTearDown(wrong.dispose);
    expect(wrong.extractBytes(), isNot(sent.sharedSecret.extractBytes()));
  });

  test('wrong lengths are argument errors, not native reads', () {
    final pair = MlKem768.generateKeyPair();
    addTearDown(pair.dispose);
    expect(() => MlKem768.encapsulate(Uint8List(1183)), throwsArgumentError);
    expect(
      () => MlKem768.decapsulate(Uint8List(1087), pair.secretKey),
      throwsArgumentError,
    );
    final shortKey = SecretBytes.allocate(10);
    final shortSeed = SecretBytes.allocate(32);
    addTearDown(shortKey.dispose);
    addTearDown(shortSeed.dispose);
    expect(
      () => MlKem768.decapsulate(Uint8List(1088), shortKey),
      throwsArgumentError,
    );
    expect(() => MlKem768.keyPairFromSeed(shortSeed), throwsArgumentError);
    expect(MlKem768.isValidPublicKey(Uint8List(5)), isFalse);
    expect(MlKem768.isValidSecretKey(shortKey), isFalse);
  });

  test('a disposed secret key cannot be used', () {
    final pair = MlKem768.generateKeyPair();
    final sent = MlKem768.encapsulate(pair.publicKey);
    addTearDown(sent.sharedSecret.dispose);
    pair.dispose();
    expect(
      () => MlKem768.decapsulate(sent.ciphertext, pair.secretKey),
      throwsStateError,
    );
  });

  test('the backend names the vendored code and its pinned commit', () {
    expect(
      pqcBackend.name,
      contains(
        'mlkem-native v2.0.0 (d1b2fe782888bdb761a50336012923180be7f502)',
      ),
    );
  });

  test('the random generator gives fresh bytes of the length asked', () {
    expect(pqcBackend.randomBytes(0), isEmpty);
    final a = pqcBackend.randomBytes(64);
    final b = pqcBackend.randomBytes(64);
    expect(a, hasLength(64));
    expect(a, isNot(b));
    expect(a.any((x) => x != 0), isTrue);
    expect(() => pqcBackend.randomBytes(-1), throwsArgumentError);
  });
}
