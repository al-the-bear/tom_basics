import 'dart:math';
import 'dart:typed_data';

/// Draws cryptographically secure random bytes.
///
/// This is the single source of raw randomness in `tom_crypto`: the Fortuna
/// seed behind `RsaKeyHelper.getSecureRandom` and the salt behind
/// `TomPasswordHasher.generateSalt` both come from here. Keeping one
/// implementation is not tidiness — the two call sites previously carried
/// separate copies of the same draw loop, and both copies were wrong in the
/// same way, because a copy is where a bound goes stale unobserved.
///
/// ## Example
///
/// ```dart
/// final seed = TomSecureBytes.generate(32);
/// ```
class TomSecureBytes {
  const TomSecureBytes._();

  /// Returns [length] cryptographically secure random bytes.
  ///
  /// Every byte is drawn uniformly from the **full** `0..255` range. The upper
  /// bound matters: [Random.nextInt] is exclusive, so the natural-looking
  /// `nextInt(255)` yields `0..254` and can never produce `0xFF` — a bias of
  /// about 0.0056 bits per byte that is invisible in any output you would
  /// think to inspect, and permanent in anything derived from it.
  ///
  /// Throws [ArgumentError] if [length] is negative.
  static Uint8List generate(int length) {
    if (length < 0) {
      throw ArgumentError.value(length, 'length', 'must not be negative');
    }
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}
