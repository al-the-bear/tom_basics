/// age's hybrid post-quantum recipients against the age testkit
/// (C2SP/CCTV age/testdata, test/vectors/age/, at the commit SOURCE.json
/// names): every hybrid vector, decrypted with tom_pqc's MLKEM768-X25519
/// inside a minimal age reader (support/age_reader.dart), must end as the
/// vector expects; a success must release exactly the payload whose SHA-256
/// the vector names.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/age_reader.dart';

const _dir = 'test/vectors/age';

const _expected = {
  'success': AgeOutcome.success,
  'no match': AgeOutcome.noMatch,
  'header failure': AgeOutcome.headerFailure,
  'payload failure': AgeOutcome.payloadFailure,
  'armor failure': AgeOutcome.armorFailure,
};

void main() {
  final source =
      jsonDecode(File('$_dir/SOURCE.json').readAsStringSync())
          as Map<String, dynamic>;
  final digests = (source['sha256'] as Map).cast<String, String>();
  final files = [
    for (final f in Directory(_dir).listSync().whereType<File>())
      if (!f.path.endsWith('SOURCE.json')) f,
  ]..sort((a, b) => a.path.compareTo(b.path));

  test('the vectors are the pinned files, unchanged', () {
    expect(files.map((f) => p.basename(f.path)), unorderedEquals(digests.keys));
    expect(files, hasLength(19));
    for (final f in files) {
      expect(
        sha256.convert(f.readAsBytesSync()).toString(),
        digests[p.basename(f.path)],
        reason: f.path,
      );
    }
  });

  for (final f in files) {
    final vector = AgeVector.read(f);
    test('${p.basename(f.path)}: ${vector.expect}', () async {
      final result = await decryptAge(
        vector.file,
        vector.identities,
        armored: vector.armored,
      );
      expect(result.outcome, _expected[vector.expect]);
      if (result.outcome == AgeOutcome.success) {
        expect(sha256Hex(result.payload!), vector.payloadHash);
      }
    });
  }
}
