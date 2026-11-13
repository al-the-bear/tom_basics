/// The composite signature ML-DSA-65 + Ed25519 of RFC 10073: the RFC's
/// test vector for id-MLDSA65-Ed25519-SHA512 (test/vectors/rfc10073/), and
/// the scheme's behaviour.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:tom_pqc/tom_pqc.dart';

void main() {
  final source =
      jsonDecode(File('test/vectors/rfc10073/SOURCE.json').readAsStringSync())
          as Map<String, dynamic>;
  final file =
      jsonDecode(
            File(
              'test/vectors/rfc10073/mldsa65_ed25519.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final v = file['test'] as Map<String, dynamic>;
  final m = base64.decode(file['m'] as String);
  final ctx = base64.decode(file['ctx'] as String);
  final pk = base64.decode(v['pk'] as String);
  final s = base64.decode(v['s'] as String);
  final sWithContext = base64.decode(v['sWithContext'] as String);

  test('the RFC vector is the pinned extract, unchanged', () {
    expect(
      sha256
          .convert(
            File(
              'test/vectors/rfc10073/mldsa65_ed25519.json',
            ).readAsBytesSync(),
          )
          .toString(),
      (source['sha256'] as Map)['mldsa65_ed25519.json'],
    );
    expect(v['tcId'], 'id-MLDSA65-Ed25519-SHA512');
  });

  group('RFC 10073 vector', () {
    test('the secret key (two seeds) gives the public key', () async {
      final sk = SecretBytes.fromBytes(base64.decode(v['sk'] as String));
      addTearDown(sk.dispose);
      expect(sk.length, MlDsa65Ed25519.secretKeyLength);
      expect(await MlDsa65Ed25519.publicKey(sk), pk);
    });

    test('s verifies over m with the empty context, and only there', () async {
      expect(s, hasLength(MlDsa65Ed25519.signatureLength));
      expect(await MlDsa65Ed25519.verify(m, s, pk), isTrue);
      expect(await MlDsa65Ed25519.verify(m, s, pk, context: ctx), isFalse);
    });

    test('sWithContext verifies over m with ctx, and only there', () async {
      expect(
        await MlDsa65Ed25519.verify(m, sWithContext, pk, context: ctx),
        isTrue,
      );
      expect(await MlDsa65Ed25519.verify(m, sWithContext, pk), isFalse);
    });

    test(
      'a signature by the vector\'s key verifies under its public key',
      () async {
        final sk = SecretBytes.fromBytes(base64.decode(v['sk'] as String));
        addTearDown(sk.dispose);
        final sig = await MlDsa65Ed25519.sign(m, sk, context: ctx);
        expect(await MlDsa65Ed25519.verify(m, sig, pk, context: ctx), isTrue);
      },
    );
  });

  test('the constants are the RFC\'s', () {
    expect(MlDsa65Ed25519.publicKeyLength, 1984);
    expect(MlDsa65Ed25519.secretKeyLength, 64);
    expect(MlDsa65Ed25519.signatureLength, 3373);
    expect(
      ascii.decode(MlDsa65Ed25519.prefix),
      'CompositeAlgorithmSignatures2025',
    );
    expect(
      ascii.decode(MlDsa65Ed25519.label),
      'COMPSIG-MLDSA65-Ed25519-SHA512',
    );
    final mPrime = MlDsa65Ed25519.representative(
      Uint8List.fromList([1, 2, 3]),
      context: Uint8List.fromList([9, 9]),
    );
    expect(mPrime.length, 32 + 30 + 1 + 2 + 64);
    expect(mPrime[62], 2, reason: 'len(ctx) after Prefix and Label');
  });

  test(
    'each half is required: a signature with either half altered fails',
    () async {
      final pair = await MlDsa65Ed25519.generateKeyPair();
      addTearDown(pair.dispose);
      final message = Uint8List.fromList(utf8.encode('grant'));
      final sig = await MlDsa65Ed25519.sign(message, pair.secretKey);
      expect(await MlDsa65Ed25519.verify(message, sig, pair.publicKey), isTrue);
      for (final index in [
        0,
        MlDsa65.signatureLength - 1,
        MlDsa65.signatureLength,
        sig.length - 1,
      ]) {
        final bad = Uint8List.fromList(sig)..[index] ^= 1;
        expect(
          await MlDsa65Ed25519.verify(message, bad, pair.publicKey),
          isFalse,
          reason: 'byte $index',
        );
      }
      expect(
        await MlDsa65Ed25519.verify(
          Uint8List.fromList(utf8.encode('grant!')),
          sig,
          pair.publicKey,
        ),
        isFalse,
      );
    },
  );

  test('malformed input is an invalid signature; a long context is refused '
      'for signing', () async {
    final pair = await MlDsa65Ed25519.generateKeyPair();
    addTearDown(pair.dispose);
    final message = Uint8List(1);
    final sig = await MlDsa65Ed25519.sign(message, pair.secretKey);
    expect(
      await MlDsa65Ed25519.verify(message, sig.sublist(1), pair.publicKey),
      isFalse,
    );
    expect(
      await MlDsa65Ed25519.verify(message, sig, pair.publicKey.sublist(1)),
      isFalse,
    );
    expect(
      await MlDsa65Ed25519.verify(
        message,
        sig,
        pair.publicKey,
        context: Uint8List(256),
      ),
      isFalse,
    );
    await expectLater(
      MlDsa65Ed25519.sign(message, pair.secretKey, context: Uint8List(256)),
      throwsArgumentError,
    );
  });
}
