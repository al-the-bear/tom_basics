/// A git object id: the SHA-1 of an object's type, size and content.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The 20-byte SHA-1 that names a git object.
class GitObjectId implements Comparable<GitObjectId> {
  GitObjectId._(this.bytes);

  /// The id from its 20 raw bytes.
  factory GitObjectId.fromBytes(List<int> bytes) {
    if (bytes.length != byteLength) {
      throw FormatException(
        'An object id is $byteLength bytes, not '
        '${bytes.length}',
      );
    }
    return GitObjectId._(Uint8List.fromList(bytes));
  }

  /// The id from its 40 hexadecimal digits.
  factory GitObjectId.fromHex(String hex) {
    if (hex.length != byteLength * 2) {
      throw FormatException(
        'An object id is ${byteLength * 2} hex digits',
        hex,
      );
    }
    final bytes = Uint8List(byteLength);
    for (var i = 0; i < byteLength; i++) {
      final value = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (value == null) {
        throw FormatException('Not a hexadecimal object id', hex);
      }
      bytes[i] = value;
    }
    return GitObjectId._(bytes);
  }

  /// The id of an object of [typeName] holding [content]: SHA-1 over
  /// `"<type> <size>\0<content>"`.
  factory GitObjectId.hash(String typeName, List<int> content) {
    final header = ascii.encode('$typeName ${content.length}\x00');
    final output = _DigestSink<Digest>();
    sha1.startChunkedConversion(output)
      ..add(header)
      ..add(content)
      ..close();
    return GitObjectId._(Uint8List.fromList(output.events.single.bytes));
  }

  static const byteLength = 20;

  /// All zeros: what git writes for "no object" in a ref update.
  static final GitObjectId zero = GitObjectId._(Uint8List(byteLength));

  final Uint8List bytes;

  String get hex {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  bool get isZero => bytes.every((b) => b == 0);

  @override
  bool operator ==(Object other) {
    if (other is! GitObjectId) return false;
    for (var i = 0; i < byteLength; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];

  @override
  int compareTo(GitObjectId other) {
    for (var i = 0; i < byteLength; i++) {
      final d = bytes[i] - other.bytes[i];
      if (d != 0) return d;
    }
    return 0;
  }

  @override
  String toString() => hex;
}

/// Collects the digest a chunked conversion produced.
class _DigestSink<T> implements Sink<T> {
  final List<T> events = [];

  @override
  void add(T event) => events.add(event);

  @override
  void close() {}
}
