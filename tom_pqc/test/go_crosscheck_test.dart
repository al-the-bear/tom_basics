/// A cross-check with Go's standard library: test/vectors/go_crosscheck.json
/// holds what crypto/mlkem, crypto/mldsa and crypto/hpke (Go version in the
/// file) compute from inputs derived from a counter, written by
/// tool/go_crosscheck. tom_pqc must compute the same: the ML-KEM-768 keys,
/// ciphertexts and shared secrets, the ML-DSA-65 keys and deterministic
/// signatures, and the MLKEM768-X25519 keys, opening what Go's HPKE sealed.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_pqc/src/pqc_backend.dart';
import 'package:tom_pqc/tom_pqc.dart';

import 'support/age_reader.dart';
import 'support/hex.dart';

void main() {
  final data =
      jsonDecode(File('test/vectors/go_crosscheck.json').readAsStringSync())
          as Map<String, dynamic>;
  List<Map<String, dynamic>> cases(String name) =>
      (data[name] as List).cast<Map<String, dynamic>>();

  test('the file was written by Go 1.27 or later', () {
    expect(data['go'], startsWith('go1.'));
    final minor = int.parse((data['go'] as String).split('.')[1]);
    expect(minor, greaterThanOrEqualTo(27));
  });

  group('ML-KEM-768 (crypto/mlkem)', () {
    for (final (i, c) in cases('mlkem768').indexed) {
      test('case $i', () {
        final seed = SecretBytes.fromBytes(hex(c['seed'] as String));
        final pair = MlKem768.keyPairFromSeed(seed);
        addTearDown(seed.dispose);
        addTearDown(pair.dispose);
        expect(toHex(pair.publicKey), (c['ek'] as String).toUpperCase());
        final sent = pqcBackend.mlKem768Encapsulate(
          pair.publicKey,
          coins: hex(c['random'] as String),
        );
        addTearDown(sent.sharedSecret.dispose);
        expect(toHex(sent.ciphertext), (c['ct'] as String).toUpperCase());
        expect(
          toHex(sent.sharedSecret.extractBytes()),
          (c['ss'] as String).toUpperCase(),
        );
        final got = MlKem768.decapsulate(
          hex(c['ct'] as String),
          pair.secretKey,
        );
        addTearDown(got.dispose);
        expect(toHex(got.extractBytes()), (c['ss'] as String).toUpperCase());
      });
    }
  });

  group('ML-DSA-65 (crypto/mldsa)', () {
    for (final (i, c) in cases('mldsa65').indexed) {
      test('case $i', () {
        final pair = MlDsa65.keyPairFromSeed(
          SecretBytes.fromBytes(hex(c['seed'] as String)),
        );
        addTearDown(pair.dispose);
        expect(toHex(pair.publicKey), (c['pk'] as String).toUpperCase());
        final message = hex(c['message'] as String);
        final context = hex(c['context'] as String);
        final signature = pqcBackend.mlDsa65SignInternal(
          message,
          pair.secretKey,
          prefix: Uint8List.fromList([0, context.length, ...context]),
          rnd: Uint8List(32),
        );
        expect(toHex(signature), (c['signature'] as String).toUpperCase());
        expect(
          MlDsa65.verify(
            message,
            hex(c['signature'] as String),
            pair.publicKey,
            context: context,
          ),
          isTrue,
        );
      });
    }
  });

  group('MLKEM768-X25519 with HPKE (crypto/hpke)', () {
    for (final (i, c) in cases('mlkem768x25519_hpke').indexed) {
      test('case $i', () async {
        final seed = hex(c['seed'] as String);
        final pair = await MlKem768X25519.keyPairFromSeed(
          SecretBytes.fromBytes(seed),
        );
        addTearDown(pair.dispose);
        expect(toHex(pair.publicKey), (c['pk'] as String).toUpperCase());
        final opened = await hpkeOpenMlKem768X25519(
          hex(c['enc'] as String),
          hex(c['sealed'] as String),
          seed,
          hex(c['info'] as String),
        );
        expect(opened, hex(c['plaintext'] as String));
      });
    }
  });
}
