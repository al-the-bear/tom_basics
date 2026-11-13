/// Wycheproof's ML-DSA-65 vectors (C2SP/wycheproof, test/vectors/wycheproof/,
/// at the commit SOURCE.json names): every test case of the three files.
///
/// Signing is deterministic (rnd all zero) unless the case gives rnd; a case
/// that gives only mu signs through the external-mu interface. A `valid`
/// signing case must give exactly the expected signature, which must verify;
/// an `invalid` one must be refused: a seed, key or context of the wrong
/// length with an ArgumentError, a malformed expanded key with a
/// TomPqcException. A verification case must verify exactly when `valid`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:tom_pqc/src/pqc_backend.dart';
import 'package:tom_pqc/tom_pqc.dart';

import 'support/hex.dart';

const _dir = 'test/vectors/wycheproof';

List<(String, Map<String, dynamic>, Map<String, dynamic>)> _cases(String file) {
  final json =
      jsonDecode(File('$_dir/$file').readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final group
        in (json['testGroups'] as List).cast<Map<String, dynamic>>())
      for (final t in (group['tests'] as List).cast<Map<String, dynamic>>())
        (
          'tcId ${t['tcId']} [${(group['source'] as Map?)?['name'] ?? ''}] '
              '${t['result']}: ${t['comment'] ?? ''}',
          group,
          t,
        ),
  ];
}

Uint8List? _bytes(Object? value) => value is String ? hex(value) : null;

void main() {
  test('the ML-DSA files are the ones SOURCE.json pins, unchanged', () {
    final source =
        jsonDecode(File('$_dir/SOURCE.json').readAsStringSync())
            as Map<String, dynamic>;
    final digests = (source['sha256'] as Map).cast<String, String>();
    for (final file in const [
      'mldsa_65_sign_seed_test.json',
      'mldsa_65_sign_noseed_test.json',
      'mldsa_65_verify_test.json',
    ]) {
      expect(
        sha256.convert(File('$_dir/$file').readAsBytesSync()).toString(),
        digests[file],
        reason: file,
      );
    }
  });

  for (final file in const [
    'mldsa_65_sign_seed_test.json',
    'mldsa_65_sign_noseed_test.json',
  ]) {
    group(file, () {
      for (final (name, g, t) in _cases(file)) {
        test(name, () {
          final valid = t['result'] == 'valid';
          final context = _bytes(t['ctx']) ?? Uint8List(0);
          final MlDsa65KeyPair pair;
          if (g.containsKey('privateSeed')) {
            final seedBytes = hex(g['privateSeed'] as String);
            if (seedBytes.length != MlDsa65.seedLength) {
              expect(valid, isFalse);
              // An empty seed is already refused as a buffer; any other
              // wrong length by key generation. Both are ArgumentErrors.
              expect(() {
                final seed = SecretBytes.fromBytes(seedBytes);
                try {
                  MlDsa65.keyPairFromSeed(seed);
                } finally {
                  seed.dispose();
                }
              }, throwsArgumentError);
              return;
            }
            final seed = SecretBytes.fromBytes(seedBytes);
            pair = MlDsa65.keyPairFromSeed(seed);
          } else {
            final sk = SecretBytes.fromBytes(hex(g['privateKey'] as String));
            if (sk.length != MlDsa65.secretKeyLength) {
              expect(valid, isFalse);
              addTearDown(sk.dispose);
              expect(
                () => MlDsa65.keyPairFromSecretKey(sk),
                throwsArgumentError,
              );
              return;
            }
            if (!valid && (t['flags'] as List).contains('InvalidPrivateKey')) {
              addTearDown(sk.dispose);
              expect(
                () => MlDsa65.keyPairFromSecretKey(sk),
                throwsA(isA<TomPqcException>()),
              );
              return;
            }
            pair = MlDsa65.keyPairFromSecretKey(sk);
          }
          addTearDown(pair.dispose);
          if (g['publicKey'] case final String pk) {
            expect(toHex(pair.publicKey), pk.toUpperCase());
          }
          final msg = _bytes(t['msg']);
          if (context.length > MlDsa65.maxContextLength) {
            expect(valid, isFalse);
            expect(
              () => MlDsa65.sign(msg!, pair.secretKey, context: context),
              throwsArgumentError,
            );
            return;
          }
          expect(valid, isTrue, reason: 'no other refusal is in the files');
          final rnd = _bytes(t['rnd']) ?? Uint8List(MlDsa65Sizes.rnd);
          final signature = msg != null
              ? pqcBackend.mlDsa65SignInternal(
                  msg,
                  pair.secretKey,
                  prefix: Uint8List.fromList([0, context.length, ...context]),
                  rnd: rnd,
                )
              : pqcBackend.mlDsa65SignInternal(
                  hex(t['mu'] as String),
                  pair.secretKey,
                  prefix: Uint8List(0),
                  rnd: rnd,
                  externalMu: true,
                );
          expect(toHex(signature), (t['sig'] as String).toUpperCase());
          if (msg != null) {
            expect(
              MlDsa65.verify(msg, signature, pair.publicKey, context: context),
              isTrue,
            );
          }
        });
      }
    });
  }

  group('mldsa_65_verify_test.json', () {
    for (final (name, g, t) in _cases('mldsa_65_verify_test.json')) {
      test(name, () {
        expect(
          MlDsa65.verify(
            hex(t['msg'] as String),
            hex(t['sig'] as String),
            hex(g['publicKey'] as String),
            context: _bytes(t['ctx']),
          ),
          t['result'] == 'valid',
        );
      });
    }
  });

  test('the case counts are the files\' own', () {
    expect(_cases('mldsa_65_sign_seed_test.json'), hasLength(105));
    expect(_cases('mldsa_65_sign_noseed_test.json'), hasLength(78));
    expect(_cases('mldsa_65_verify_test.json'), hasLength(210));
  });
}
