/// Wycheproof's ML-KEM-768 vectors (C2SP/wycheproof, test/vectors/wycheproof/,
/// at the commit SOURCE.json names): every test case of the four files.
///
/// A `valid` case must give exactly the expected keys, ciphertext and shared
/// secret, implicit rejection of a malformed or malleable ciphertext included.
/// An `invalid` case must be refused: a seed, key or ciphertext of the wrong
/// length with an ArgumentError before any native code runs, a key FIPS 203's
/// checks reject with a TomPqcException.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:tom_pqc/src/pqc_backend.dart';
import 'package:tom_pqc/tom_pqc.dart';

import 'support/hex.dart';

const _dir = 'test/vectors/wycheproof';

final _source =
    jsonDecode(File('$_dir/SOURCE.json').readAsStringSync())
        as Map<String, dynamic>;

/// Every test case of [file], with the group's source in its name.
List<(String, Map<String, dynamic>)> _cases(String file) {
  final json =
      jsonDecode(File('$_dir/$file').readAsStringSync())
          as Map<String, dynamic>;
  final out = <(String, Map<String, dynamic>)>[];
  for (final group in (json['testGroups'] as List).cast<Map>()) {
    if (group['parameterSet'] != 'ML-KEM-768') {
      throw StateError('$file holds a ${group['parameterSet']} group');
    }
    final source = (group['source'] as Map)['name'];
    for (final t in (group['tests'] as List).cast<Map<String, dynamic>>()) {
      final comment = (t['comment'] as String?) ?? '';
      out.add((
        'tcId ${t['tcId']} [$source] ${t['result']}'
            '${comment.isEmpty ? '' : ': $comment'}',
        t,
      ));
    }
  }
  return out;
}

bool _valid(Map<String, dynamic> t) => t['result'] == 'valid';

/// The refusal an invalid case expects: wrong lengths are ArgumentErrors,
/// everything else a TomPqcException.
Matcher _refused({required bool wrongLength}) =>
    throwsA(wrongLength ? isA<ArgumentError>() : isA<TomPqcException>());

void main() {
  test('the files are the ones SOURCE.json pins, unchanged', () {
    expect(_source['commit'], matches(RegExp(r'^[0-9a-f]{40}$')));
    final digests = (_source['sha256'] as Map).cast<String, String>();
    for (final file in const [
      'mlkem_768_keygen_seed_test.json',
      'mlkem_768_encaps_test.json',
      'mlkem_768_test.json',
      'mlkem_768_semi_expanded_decaps_test.json',
    ]) {
      expect(
        sha256.convert(File('$_dir/$file').readAsBytesSync()).toString(),
        digests[file],
        reason: file,
      );
    }
    expect(
      File('$_dir/LICENSE').readAsStringSync(),
      contains('Apache License'),
    );
  });

  group('keyGen from seed', () {
    for (final (name, t) in _cases('mlkem_768_keygen_seed_test.json')) {
      test(name, () {
        expect(_valid(t), isTrue, reason: 'the keygen file holds valid cases');
        final seed = SecretBytes.fromBytes(hex(t['seed'] as String));
        final pair = MlKem768.keyPairFromSeed(seed);
        addTearDown(seed.dispose);
        addTearDown(pair.dispose);
        expect(toHex(pair.publicKey), (t['ek'] as String).toUpperCase());
        expect(
          toHex(pair.secretKey.extractBytes()),
          (t['dk'] as String).toUpperCase(),
        );
      });
    }
  });

  group('encapsulation', () {
    for (final (name, t) in _cases('mlkem_768_encaps_test.json')) {
      test(name, () {
        final ek = hex(t['ek'] as String);
        final m = hex(t['m'] as String);
        if (_valid(t)) {
          final sent = pqcBackend.mlKem768Encapsulate(ek, coins: m);
          addTearDown(sent.sharedSecret.dispose);
          expect(toHex(sent.ciphertext), (t['c'] as String).toUpperCase());
          expect(
            toHex(sent.sharedSecret.extractBytes()),
            (t['K'] as String).toUpperCase(),
          );
        } else {
          final wrongLength = ek.length != MlKem768.publicKeyLength;
          expect(
            () => pqcBackend.mlKem768Encapsulate(ek, coins: m),
            _refused(wrongLength: wrongLength),
          );
          expect(MlKem768.isValidPublicKey(ek), isFalse);
        }
      });
    }
  });

  group('decapsulation from seed', () {
    for (final (name, t) in _cases('mlkem_768_test.json')) {
      test(name, () {
        final seedBytes = hex(t['seed'] as String);
        final c = hex(t['c'] as String);
        if (seedBytes.length != MlKem768.seedLength) {
          expect(_valid(t), isFalse);
          final seed = SecretBytes.fromBytes(seedBytes);
          addTearDown(seed.dispose);
          expect(
            () => MlKem768.keyPairFromSeed(seed),
            _refused(wrongLength: true),
          );
          return;
        }
        final seed = SecretBytes.fromBytes(seedBytes);
        final pair = MlKem768.keyPairFromSeed(seed);
        addTearDown(seed.dispose);
        addTearDown(pair.dispose);
        if (t['ek'] case final String ek) {
          expect(toHex(pair.publicKey), ek.toUpperCase());
        }
        if (_valid(t)) {
          final k = MlKem768.decapsulate(c, pair.secretKey);
          addTearDown(k.dispose);
          expect(toHex(k.extractBytes()), (t['K'] as String).toUpperCase());
        } else {
          expect(c.length, isNot(MlKem768.ciphertextLength));
          expect(
            () => MlKem768.decapsulate(c, pair.secretKey),
            _refused(wrongLength: true),
          );
        }
      });
    }
  });

  group('decapsulation with an expanded key', () {
    for (final (name, t) in _cases(
      'mlkem_768_semi_expanded_decaps_test.json',
    )) {
      test(name, () {
        final dkBytes = hex(t['dk'] as String);
        final c = hex(t['c'] as String);
        final dk = SecretBytes.fromBytes(dkBytes);
        addTearDown(dk.dispose);
        if (_valid(t)) {
          final k = MlKem768.decapsulate(c, dk);
          addTearDown(k.dispose);
          expect(toHex(k.extractBytes()), (t['K'] as String).toUpperCase());
        } else {
          final wrongLength =
              dkBytes.length != MlKem768.secretKeyLength ||
              c.length != MlKem768.ciphertextLength;
          expect(
            () => MlKem768.decapsulate(c, dk),
            _refused(wrongLength: wrongLength),
          );
          if (!wrongLength) expect(MlKem768.isValidSecretKey(dk), isFalse);
        }
      });
    }
  });

  test('the case counts are the files\' own', () {
    int count(String file) => _cases(file).length;
    expect(count('mlkem_768_keygen_seed_test.json'), 100);
    expect(count('mlkem_768_encaps_test.json'), 265);
    expect(count('mlkem_768_test.json'), 201);
    expect(count('mlkem_768_semi_expanded_decaps_test.json'), 9);
  });
}
