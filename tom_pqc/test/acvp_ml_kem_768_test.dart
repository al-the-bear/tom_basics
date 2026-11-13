/// The FIPS 203 known-answer tests: NIST's ACVP vectors for ML-KEM-768
/// (test/vectors/acvp_ml_kem_768.json, from ACVP-Server at the commit it
/// names). Every test case of the five ML-KEM-768 groups.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_pqc/src/pqc_backend.dart';
import 'package:tom_pqc/tom_pqc.dart';

import 'support/hex.dart';

void main() {
  final vectors =
      jsonDecode(File('test/vectors/acvp_ml_kem_768.json').readAsStringSync())
          as Map<String, dynamic>;
  List<Map<String, dynamic>> cases(String name) =>
      (vectors[name] as List).cast<Map<String, dynamic>>();

  test('the vector file is the ML-KEM-768 extract it says it is', () {
    expect(vectors['parameterSet'], 'ML-KEM-768');
    expect(vectors['commit'], matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(cases('keyGen'), hasLength(25));
    expect(cases('encapsulation'), hasLength(25));
    expect(cases('decapsulation'), hasLength(10));
    expect(cases('encapsulationKeyCheck'), hasLength(10));
    expect(cases('decapsulationKeyCheck'), hasLength(10));
  });

  group('keyGen (ML-KEM.KeyGen_internal)', () {
    for (final t in cases('keyGen')) {
      test('tcId ${t['tcId']}', () {
        final seed = SecretBytes.fromBytes(hex('${t['d']}${t['z']}'));
        final pair = MlKem768.keyPairFromSeed(seed);
        addTearDown(seed.dispose);
        addTearDown(pair.dispose);
        expect(toHex(pair.publicKey), t['ek']);
        expect(toHex(pair.secretKey.extractBytes()), t['dk']);
      });
    }
  });

  group('encapsulation (ML-KEM.Encaps_internal)', () {
    for (final t in cases('encapsulation')) {
      test('tcId ${t['tcId']}', () {
        final sent = pqcBackend.mlKem768Encapsulate(
          hex(t['ek'] as String),
          coins: hex(t['m'] as String),
        );
        addTearDown(sent.sharedSecret.dispose);
        expect(toHex(sent.ciphertext), t['c']);
        expect(toHex(sent.sharedSecret.extractBytes()), t['k']);

        // And the holder of dk gets the same secret back.
        final dk = SecretBytes.fromBytes(hex(t['dk'] as String));
        final received = MlKem768.decapsulate(sent.ciphertext, dk);
        addTearDown(dk.dispose);
        addTearDown(received.dispose);
        expect(toHex(received.extractBytes()), t['k']);
      });
    }
  });

  group('decapsulation (ML-KEM.Decaps, implicit rejection)', () {
    for (final t in cases('decapsulation')) {
      test('tcId ${t['tcId']}: ${t['reason']}', () {
        final dk = SecretBytes.fromBytes(hex(t['dk'] as String));
        final k = MlKem768.decapsulate(hex(t['c'] as String), dk);
        addTearDown(dk.dispose);
        addTearDown(k.dispose);
        expect(toHex(k.extractBytes()), t['k']);
      });
    }
  });

  group('encapsulationKeyCheck (FIPS 203 7.2)', () {
    for (final t in cases('encapsulationKeyCheck')) {
      test('tcId ${t['tcId']}: ${t['reason']}', () {
        final ek = hex(t['ek'] as String);
        final passed = t['testPassed'] as bool;
        expect(MlKem768.isValidPublicKey(ek), passed);
        if (passed) {
          MlKem768.encapsulate(ek).sharedSecret.dispose();
        } else {
          expect(
            () => MlKem768.encapsulate(ek),
            throwsA(isA<TomPqcException>()),
          );
        }
      });
    }
  });

  group('decapsulationKeyCheck (FIPS 203 7.3)', () {
    for (final t in cases('decapsulationKeyCheck')) {
      test('tcId ${t['tcId']}: ${t['reason']}', () {
        final dk = SecretBytes.fromBytes(hex(t['dk'] as String));
        addTearDown(dk.dispose);
        final passed = t['testPassed'] as bool;
        expect(MlKem768.isValidSecretKey(dk), passed);
        final ciphertext = Uint8List(MlKem768.ciphertextLength);
        if (passed) {
          MlKem768.decapsulate(ciphertext, dk).dispose();
        } else {
          expect(
            () => MlKem768.decapsulate(ciphertext, dk),
            throwsA(isA<TomPqcException>()),
          );
        }
      });
    }
  });
}
