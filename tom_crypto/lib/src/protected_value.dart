/// A secret held in memory behind one explicit accessor.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:tom_basics/utilities.dart';

import 'secure_bytes.dart';

/// A secret in memory: [reveal] gives the plaintext, [digest] identifies it.
///
/// The bytes can still be read by a determined caller; what this changes is
/// **where the read is visible**. Every place the plaintext leaves the object
/// is a call to [reveal], [withRevealed] or [revealInto], which a reader can
/// search for, and every place that would leak it by accident — `toString()`
/// in a log line, an interpolated map, `jsonEncode`, a merge comparison —
/// gets the [mask], the digest or an error instead.
///
/// The plaintext is kept XOR-ed with a per-instance random salt, so it is not
/// in memory as one contiguous string between reads. Equality is by [digest],
/// so "same secret or not" never needs the plaintext.
///
/// [reveal] hands out a `String`, which no one can overwrite afterwards;
/// [withRevealed] and [revealInto] hand out bytes the caller controls, and
/// [withRevealed] zeroes them once the callback returns. [dispose] zeroes the
/// masked bytes and the salt; the value can then no longer be read.
final class TomProtectedValue {
  /// The text every masked rendering of a secret shows.
  static const String mask = '••••';

  final Uint8List _masked;
  final Uint8List _salt;
  final int _length;
  bool _disposed = false;

  /// The SHA-256 hex of the plaintext's bytes (a text's UTF-8).
  ///
  /// What equality, merges and change detection compare. It stays after
  /// [dispose].
  final String digest;

  /// The plaintext's length in bytes (a text's UTF-8) — zero for an empty
  /// secret. It stays after [dispose].
  int get length => _length;

  bool get isEmpty => length == 0;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  TomProtectedValue._(this._masked, this._salt, this.digest)
    : _length = _masked.length;

  /// Protects [secret]. The `String` handed in is the caller's to drop.
  factory TomProtectedValue.of(String secret) =>
      TomProtectedValue.fromBytes(Uint8List.fromList(utf8.encode(secret)));

  /// Protects [bytes] (any bytes: text as UTF-8, or binary) and **zeroes
  /// [bytes]**: the buffer handed in is consumed, so the plaintext does not
  /// stay behind in it.
  factory TomProtectedValue.fromBytes(Uint8List bytes) {
    final salt = TomSecureBytes.generate(bytes.length);
    final masked = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      masked[i] = bytes[i] ^ salt[i];
    }
    final digest = tomSha256Hex(bytes);
    bytes.fillRange(0, bytes.length, 0);
    return TomProtectedValue._(masked, salt, digest);
  }

  void _checkReadable() {
    if (_disposed) {
      throw StateError('the protected value has been disposed');
    }
  }

  /// The plaintext as text (the bytes read as UTF-8). **The one `String`
  /// accessor** — every call site is a place the secret is deliberately
  /// read, and the `String` cannot be wiped afterwards: prefer
  /// [withRevealed] where bytes do.
  String reveal() => withRevealed(utf8.decode);

  /// Writes the plaintext into [target] at [offset]; the caller wipes
  /// [target] when it is done with it. Throws [RangeError] when it does not
  /// fit.
  void revealInto(Uint8List target, [int offset = 0]) {
    _checkReadable();
    RangeError.checkValidRange(offset, offset + _length, target.length);
    for (var i = 0; i < _length; i++) {
      target[offset + i] = _masked[i] ^ _salt[i];
    }
  }

  /// Calls [use] with the plaintext's bytes and zeroes them when it returns
  /// or throws. [use] is synchronous: the bytes exist only for its duration,
  /// and it must not keep them.
  T withRevealed<T>(T Function(Uint8List bytes) use) {
    _checkReadable();
    final bytes = Uint8List(_length);
    try {
      revealInto(bytes);
      return use(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// Zeroes the masked bytes and the salt. Reading afterwards throws a
  /// [StateError]; [digest], [length] and equality stay. Disposing twice is
  /// fine.
  void dispose() {
    _masked.fillRange(0, _masked.length, 0);
    _salt.fillRange(0, _salt.length, 0);
    _disposed = true;
  }

  /// Never the secret: the [mask].
  @override
  String toString() => 'TomProtectedValue($mask)';

  /// By [digest]: two values protecting the same secret are equal.
  @override
  bool operator ==(Object other) =>
      other is TomProtectedValue && other.digest == digest;

  @override
  int get hashCode => digest.hashCode;
}
