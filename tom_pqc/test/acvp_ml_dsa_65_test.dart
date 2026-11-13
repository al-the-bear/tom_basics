/// The FIPS 204 known-answer tests: NIST's ACVP vectors for ML-DSA-65
/// (test/vectors/acvp_ml_dsa_65.json, from ACVP-Server at the commit it
/// names). Every test case of every ML-DSA-65 group of pure ML-DSA: key
/// generation, signing (deterministic and hedged; the external interface
/// with a context, the internal interface, external mu) and verification.
/// The HashML-DSA groups (preHash) are skipped by name: tom_pqc does not
/// offer HashML-DSA.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_pqc/src/pqc_backend.dart';
import 'package:tom_pqc/tom_pqc.dart';

import 'support/hex.dart';

final _vectors =
    jsonDecode(File('test/vectors/acvp_ml_dsa_65.json').readAsStringSync())
        as Map<String, dynamic>;

List<Map<String, dynamic>> _groups(String mode) =>
    (_vectors[mode] as List).cast<Map<String, dynamic>>();

List<Map<String, dynamic>> _tests(Map<String, dynamic> group) =>
    (group['tests'] as List).cast<Map<String, dynamic>>();

String _describe(Map<String, dynamic> g) =>
    'tgId ${g['tgId']} ${g['signatureInterface']}'
    '${g['preHash'] == 'pure' || g['preHash'] == 'none' ? '' : ' ${g['preHash']}'}'
    '${g['externalMu'] == true ? ' externalMu' : ''}'
    '${g.containsKey('deterministic') ? (g['deterministic'] == true ? ' deterministic' : ' hedged') : ''}';

/// The FIPS 204 domain prefix of the external interface:
/// 0 || len(ctx) || ctx.
Uint8List _externalPrefix(Uint8List context) =>
    Uint8List.fromList([0, context.length, ...context]);

void main() {
  test('the vector file is the ML-DSA-65 extract it says it is', () {
    expect(_vectors['parameterSet'], 'ML-DSA-65');
    expect(_vectors['commit'], matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(_groups('keyGen').expand(_tests), hasLength(25));
    expect(_groups('sigGen').expand(_tests), hasLength(120));
    expect(_groups('sigVer').expand(_tests), hasLength(60));
  });

  group('keyGen (ML-DSA.KeyGen_internal)', () {
    for (final t in _groups('keyGen').expand(_tests)) {
      test('tcId ${t['tcId']}', () {
        final pair = MlDsa65.keyPairFromSeed(
          SecretBytes.fromBytes(hex(t['seed'] as String)),
        );
        addTearDown(pair.dispose);
        expect(toHex(pair.publicKey), t['pk']);
        expect(toHex(pair.secretKey.extractBytes()), t['sk']);
      });
    }
  });

  group('sigGen', () {
    for (final g in _groups('sigGen')) {
      final pure = g['preHash'] != 'preHash';
      group(_describe(g), () {
        for (final t in _tests(g)) {
          test('tcId ${t['tcId']}', () {
            final sk = SecretBytes.fromBytes(hex(t['sk'] as String));
            addTearDown(sk.dispose);
            final rnd = t.containsKey('rnd')
                ? hex(t['rnd'] as String)
                : Uint8List(MlDsa65Sizes.rnd);
            final externalMu = g['externalMu'] == true;
            final Uint8List signature;
            if (externalMu) {
              signature = pqcBackend.mlDsa65SignInternal(
                hex(t['mu'] as String),
                sk,
                prefix: Uint8List(0),
                rnd: rnd,
                externalMu: true,
              );
            } else if (g['signatureInterface'] == 'internal') {
              signature = pqcBackend.mlDsa65SignInternal(
                hex(t['message'] as String),
                sk,
                prefix: Uint8List(0),
                rnd: rnd,
              );
            } else {
              signature = pqcBackend.mlDsa65SignInternal(
                hex(t['message'] as String),
                sk,
                prefix: _externalPrefix(hex(t['context'] as String)),
                rnd: rnd,
              );
            }
            expect(toHex(signature), t['signature']);
            if (!externalMu && g['signatureInterface'] == 'external') {
              expect(
                MlDsa65.verify(
                  hex(t['message'] as String),
                  signature,
                  hex(t['pk'] as String),
                  context: hex(t['context'] as String),
                ),
                isTrue,
              );
            }
          }, skip: pure ? false : 'HashML-DSA is not offered by tom_pqc');
        }
      });
    }
  });

  group('sigVer', () {
    for (final g in _groups('sigVer')) {
      final pure = g['preHash'] != 'preHash';
      group(_describe(g), () {
        for (final t in _tests(g)) {
          test('tcId ${t['tcId']}: ${t['reason']}', () {
            final pk = hex(t['pk'] as String);
            final sig = hex(t['signature'] as String);
            final bool valid;
            if (g['externalMu'] == true) {
              valid = pqcBackend.mlDsa65VerifyInternal(
                hex(t['mu'] as String),
                sig,
                pk,
                prefix: Uint8List(0),
                externalMu: true,
              );
            } else if (g['signatureInterface'] == 'internal') {
              valid = pqcBackend.mlDsa65VerifyInternal(
                hex(t['message'] as String),
                sig,
                pk,
                prefix: Uint8List(0),
              );
            } else {
              valid = MlDsa65.verify(
                hex(t['message'] as String),
                sig,
                pk,
                context: hex(t['context'] as String),
              );
            }
            expect(valid, t['testPassed']);
          }, skip: pure ? false : 'HashML-DSA is not offered by tom_pqc');
        }
      });
    }
  });
}
