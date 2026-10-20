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
/// is a call to [reveal], which a reader can search for, and every place that
/// would leak it by accident — `toString()` in a log line, an interpolated
/// map, `jsonEncode`, a merge comparison — gets the [mask], the digest or an
/// error instead.
///
/// The plaintext is kept XOR-ed with a per-instance random salt, so it is not
/// in memory as one contiguous string between reads. Equality is by [digest],
/// so "same secret or not" never needs the plaintext.
final class TomProtectedValue {
  /// The text every masked rendering of a secret shows.
  static const String mask = '••••';

  final Uint8List _masked;
  final Uint8List _salt;

  /// The SHA-256 hex of the plaintext's UTF-8 bytes.
  ///
  /// What equality, merges and change detection compare.
  final String digest;

  /// The plaintext's length in UTF-8 bytes — zero for an empty secret.
  int get length => _masked.length;

  bool get isEmpty => length == 0;

  TomProtectedValue._(this._masked, this._salt, this.digest);

  /// Protects [secret]. The `String` handed in is the caller's to drop.
  factory TomProtectedValue.of(String secret) {
    final bytes = Uint8List.fromList(utf8.encode(secret));
    final salt = TomSecureBytes.generate(bytes.length);
    final masked = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      masked[i] = bytes[i] ^ salt[i];
    }
    final digest = tomSha256Hex(bytes);
    bytes.fillRange(0, bytes.length, 0);
    return TomProtectedValue._(masked, salt, digest);
  }

  /// The plaintext. **The one accessor** — every call site is a place the
  /// secret is deliberately read.
  String reveal() {
    final bytes = Uint8List(_masked.length);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _masked[i] ^ _salt[i];
    }
    return utf8.decode(bytes);
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
