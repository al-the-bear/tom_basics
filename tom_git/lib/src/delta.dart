/// Git's delta encoding: an object as copies from a base plus inserted bytes.
library;

import 'dart:typed_data';

/// Applies a git delta to [base].
///
/// A delta starts with the base size and the result size (each a
/// little-endian base-128 varint), followed by instructions: a byte with the
/// high bit set copies a range of the base (offset and size in the following
/// bytes, present per bit), any other non-zero byte inserts that many literal
/// bytes.
Uint8List gitApplyDelta(Uint8List base, Uint8List delta) {
  var i = 0;
  int varint() {
    var value = 0;
    var shift = 0;
    while (true) {
      if (i >= delta.length) throw const FormatException('Truncated delta');
      final b = delta[i++];
      value |= (b & 0x7f) << shift;
      shift += 7;
      if (b & 0x80 == 0) return value;
    }
  }

  final baseSize = varint();
  if (baseSize != base.length) {
    throw FormatException(
      'Delta expects a base of $baseSize bytes, the base '
      'has ${base.length}',
    );
  }
  final resultSize = varint();
  final out = Uint8List(resultSize);
  var o = 0;
  while (i < delta.length) {
    final op = delta[i++];
    if (op & 0x80 != 0) {
      var copyOffset = 0;
      var copySize = 0;
      for (var bit = 0; bit < 4; bit++) {
        if (op & (1 << bit) != 0) copyOffset |= delta[i++] << (bit * 8);
      }
      for (var bit = 0; bit < 3; bit++) {
        if (op & (0x10 << bit) != 0) copySize |= delta[i++] << (bit * 8);
      }
      if (copySize == 0) copySize = 0x10000;
      if (copyOffset + copySize > base.length || o + copySize > resultSize) {
        throw const FormatException('Delta copy out of range');
      }
      out.setRange(o, o + copySize, base, copyOffset);
      o += copySize;
    } else if (op != 0) {
      if (i + op > delta.length || o + op > resultSize) {
        throw const FormatException('Delta insert out of range');
      }
      out.setRange(o, o + op, delta, i);
      i += op;
      o += op;
    } else {
      throw const FormatException('Delta opcode 0 is reserved');
    }
  }
  if (o != resultSize) {
    throw FormatException('Delta produced $o bytes, expected $resultSize');
  }
  return out;
}
