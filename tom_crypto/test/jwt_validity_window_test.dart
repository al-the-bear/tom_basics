/// Guards that a token's validity window is exactly as wide as it was asked
/// to be.
///
/// `_generateLoad` writes `validFrom` and `validUntil` as offsets from the
/// moment of issue. It used to read `DateTime.now()` once for each, so the two
/// claims were offsets from two different instants a few microseconds apart:
/// the window came out marginally narrower than `expiresIn - notBefore`, and
/// `validFrom` under the default zero `notBefore` named an instant just after
/// the one it stands for. Sub-millisecond skew never broke an expiry check,
/// but it made the two claims impossible to reason about together.
library;

import 'package:tom_crypto/tom_crypto.dart';
import 'package:test/test.dart';

/// The `validFrom`/`validUntil` pair of a freshly issued token.
(DateTime from, DateTime until) _window({
  Duration expiresIn = const Duration(hours: 2),
  Duration notBefore = Duration.zero,
}) {
  final payload = TomClientJwtToken(
    TomServerJwtToken(
      {'userId': 'u'},
      expiresIn: expiresIn,
      notBefore: notBefore,
    ).getJWT('issuer'),
    decrypt: false,
  ).payload!;
  return (
    DateTime.parse(payload['validFrom'] as String),
    DateTime.parse(payload['validUntil'] as String),
  );
}

void main() {
  group('a token validity window', () {
    test('is exactly as wide as expiresIn when notBefore is zero', () {
      final (from, until) = _window(expiresIn: const Duration(hours: 2));
      expect(until.difference(from), const Duration(hours: 2));
    });

    test('is expiresIn - notBefore when validity is delayed', () {
      final (from, until) = _window(
        expiresIn: const Duration(hours: 24),
        notBefore: const Duration(minutes: 5),
      );
      expect(until.difference(from), const Duration(hours: 24) - const Duration(minutes: 5));
    });

    test('holds for a window narrow enough that skew would show', () {
      // A one-millisecond window is the sharpest statement of the rule: under
      // two clock reads the offsets could differ by more than the window
      // itself, inverting the pair.
      final (from, until) = _window(expiresIn: const Duration(milliseconds: 1));
      expect(until.difference(from), const Duration(milliseconds: 1));
      expect(until.isAfter(from), isTrue);
    });
  });
}
