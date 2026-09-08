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

/// The payload of a freshly issued token.
Map<String, dynamic> _payload({
  Duration expiresIn = const Duration(hours: 2),
  Duration notBefore = Duration.zero,
}) => TomClientJwtToken(
  TomServerJwtToken(
    {'userId': 'u'},
    expiresIn: expiresIn,
    notBefore: notBefore,
  ).getJWT('issuer'),
  decrypt: false,
).payload!;

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
      expect(
        until.difference(from),
        const Duration(hours: 24) - const Duration(minutes: 5),
      );
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

  group('the standard claims and the Tom claims name one instant', () {
    // A token carries both `exp`/`nbf` and `validUntil`/`validFrom`, and a
    // consumer has to choose which to read -- `TomAuthorizationCache` reads
    // `exp`. The choice is only safe because there is nothing to choose: both
    // are derived from one clock read, truncated to the whole seconds `exp` is
    // encoded in. Written from two reads they land microseconds apart, and two
    // readers of one token then disagree about when it dies.

    test('exp is validUntil, to the second', () {
      final payload = _payload();
      final validUntil = DateTime.parse(payload['validUntil'] as String);
      expect(
        payload['exp'],
        validUntil.millisecondsSinceEpoch ~/ 1000,
        reason: 'exp and validUntil must be the same instant',
      );
    });

    test('nbf is validFrom, to the second', () {
      final payload = _payload(notBefore: const Duration(minutes: 5));
      final validFrom = DateTime.parse(payload['validFrom'] as String);
      expect(payload['nbf'], validFrom.millisecondsSinceEpoch ~/ 1000);
    });

    test('the Tom claims carry no sub-second part to lose', () {
      // What makes the equality above exact rather than approximate: an
      // instant with a fractional second could not survive the epoch-second
      // encoding, so the pair would differ by up to a second and the
      // assertions above would pass or fail depending on where in the second
      // the token happened to be minted.
      final payload = _payload();
      for (final claim in ['validUntil', 'validFrom']) {
        final parsed = DateTime.parse(payload[claim] as String);
        expect(parsed.millisecond, 0, reason: '$claim carries milliseconds');
        expect(parsed.microsecond, 0, reason: '$claim carries microseconds');
      }
    });

    test('the Tom claims are absolute, not local', () {
      // An ISO string without an offset means whatever the reader's zone says.
      // `isUtc` is the property that takes the question away, and the `Z` is
      // what a non-Dart reader sees it by.
      final payload = _payload();
      for (final claim in ['validUntil', 'validFrom']) {
        expect(DateTime.parse(payload[claim] as String).isUtc, isTrue);
        expect(payload[claim] as String, endsWith('Z'));
      }
    });
  });
}
