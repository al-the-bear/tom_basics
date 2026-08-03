import 'package:tom_crypto/tom_crypto.dart';
import 'package:test/test.dart';

/// The sample size for the range tests.
///
/// Each byte is drawn independently, so the chance that a *correct* generator
/// misses some value in a sample this size is `256 * (255/256)^100000`, which
/// is around `10^-167` — far below the rate at which the machine running the
/// test miscomputes it. A generator that cannot emit a value at all fails
/// every time. So this reads as a deterministic assertion even though the
/// input is random: there is no flake budget to spend here.
const int _sampleSize = 100000;

/// Decodes the hex string [TomPasswordHasher.generateSalt] returns.
List<int> _decodeHex(String hex) => [
      for (int i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];

void main() {
  group('tccb1: secure bytes span the whole 0..255 range', () {
    test('TomSecureBytes.generate emits every byte value', () {
      final seen = TomSecureBytes.generate(_sampleSize).toSet();

      expect(
        seen,
        hasLength(256),
        reason: 'A byte drawn as nextInt(255) lands in 0..254, so 255 can '
            'never appear. This is the generator behind both the Fortuna seed '
            'and the password salt, so a narrow bound here is inherited by '
            'every key and every hash the framework produces.',
      );
      expect(seen, contains(255), reason: 'the specific value the bound loses');
      expect(seen, contains(0), reason: 'the bound at the other end');
    });

    test('generateSalt emits every byte value', () {
      // The salt is the observable half of the defect: it is hex-encoded into
      // the stored password hash, so a missing byte value is persisted rather
      // than merely computed.
      final seen = <int>{};
      const saltLength = 32;
      for (int i = 0; i < _sampleSize ~/ saltLength; i++) {
        seen.addAll(_decodeHex(TomPasswordHasher.generateSalt(saltLength)));
      }

      expect(seen, hasLength(256));
      expect(seen, contains(255));
    });

    test('generate returns the requested length and a fresh list each call', () {
      expect(TomSecureBytes.generate(0), isEmpty);
      expect(TomSecureBytes.generate(1), hasLength(1));
      expect(TomSecureBytes.generate(32), hasLength(32));

      // Two calls must not share storage — the seed of one FortunaRandom
      // cannot be allowed to alias the salt of a password hashed later.
      final first = TomSecureBytes.generate(32);
      final second = TomSecureBytes.generate(32);
      expect(identical(first, second), isFalse);
      expect(first, isNot(equals(second)),
          reason: 'two 32-byte secure draws colliding is a 2^-256 event; if '
              'this fails the generator is not random at all');
    });

    test('a negative length is rejected rather than silently yielding empty',
        () {
      expect(() => TomSecureBytes.generate(-1), throwsArgumentError);
    });
  });
}
