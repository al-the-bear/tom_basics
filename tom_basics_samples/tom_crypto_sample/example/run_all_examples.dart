// Aggregator: runs every tom_crypto example and reports a pass/fail tally.
//
// Every example is deterministic and offline — Argon2 hashing, JWT issue/verify,
// and RSA encrypt/decrypt/sign/keygen all run in-process with no network. We
// call them in declaration order, catch any throw, and exit non-zero if any
// example fails: the single command CI needs to verify the whole sample.
//
// Run with: dart run example/run_all_examples.dart
import 'dart:async';

import '01_hashing_a_password_example.dart' as ex01;
import '02_the_hash_specification_example.dart' as ex02;
import '03_issuing_and_reading_a_jwt_example.dart' as ex03;
import '04_verifying_a_jwt_signature_example.dart' as ex04;
import '05_encrypted_jwt_payload_example.dart' as ex05;
import '06_rsa_encrypt_decrypt_example.dart' as ex06;
import '07_rsa_signatures_and_keygen_example.dart' as ex07;

Future<void> main() async {
  final examples = <String, FutureOr<void> Function()>{
    '01_hashing_a_password': ex01.main,
    '02_the_hash_specification': ex02.main,
    '03_issuing_and_reading_a_jwt': ex03.main,
    '04_verifying_a_jwt_signature': ex04.main,
    '05_encrypted_jwt_payload': ex05.main,
    '06_rsa_encrypt_decrypt': ex06.main,
    '07_rsa_signatures_and_keygen': ex07.main,
  };

  var passed = 0;
  var failed = 0;

  for (final entry in examples.entries) {
    print('\n=== ${entry.key} ===');
    try {
      await entry.value();
      passed++;
    } catch (e, st) {
      failed++;
      print('FAILED: $e');
      print(st);
    }
  }

  print('\n----------------------------------------');
  print('$passed passed, $failed failed');
  if (failed > 0) {
    throw StateError('$failed example(s) failed');
  }
}
