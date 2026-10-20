/// A file's bytes as text, and the text back as the same kind of bytes.
///
/// An editor works on a `String`; a save has to write the encoding, the
/// byte-order mark and the line endings the file had. The line endings are
/// kept by never re-emitting the file: every edit is a splice into the decoded
/// text, so a CRLF line nobody touched is still CRLF. What this codec keeps is
/// the rest — the encoding and the BOM, which do not survive a `String`.
library;

import 'dart:convert';
import 'dart:typed_data';

/// How a file's text is stored.
enum TomTextEncoding {
  /// UTF-8 with no byte-order mark — the ordinary case.
  utf8,

  /// UTF-8 behind the `EF BB BF` mark, which a save writes back.
  utf8Bom,

  /// UTF-16 little-endian behind `FF FE`.
  utf16le,

  /// UTF-16 big-endian behind `FE FF`.
  utf16be,

  /// Neither UTF-8 nor marked UTF-16: shown as Latin-1 and never written,
  /// since writing it back would be a guess at what it was.
  latin1;

  /// Whether a save can reproduce the file's own encoding.
  bool get writable => this != latin1;
}

/// A file's decoded text and the encoding it came from.
class TomDecodedText {
  final String text;
  final TomTextEncoding encoding;

  const TomDecodedText(this.text, this.encoding);
}

/// Decodes [bytes] as the file's own encoding: UTF-16 behind its mark, else
/// UTF-8 (a UTF-8 mark noted and dropped from the text), else Latin-1.
TomDecodedText tomDecodeTextBytes(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return TomDecodedText(
      _utf16(bytes, 2, littleEndian: true),
      TomTextEncoding.utf16le,
    );
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return TomDecodedText(
      _utf16(bytes, 2, littleEndian: false),
      TomTextEncoding.utf16be,
    );
  }
  final bom = bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
  try {
    return TomDecodedText(
      utf8.decode(bom ? bytes.sublist(3) : bytes),
      bom ? TomTextEncoding.utf8Bom : TomTextEncoding.utf8,
    );
  } on FormatException {
    return TomDecodedText(latin1.decode(bytes), TomTextEncoding.latin1);
  }
}

/// [text] as [encoding]'s bytes, mark included.
///
/// Throws a [StateError] for [TomTextEncoding.latin1], which is shown and
/// never written.
Uint8List tomEncodeText(String text, TomTextEncoding encoding) {
  switch (encoding) {
    case TomTextEncoding.utf8:
      return Uint8List.fromList(utf8.encode(text));
    case TomTextEncoding.utf8Bom:
      return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
    case TomTextEncoding.utf16le:
    case TomTextEncoding.utf16be:
      final little = encoding == TomTextEncoding.utf16le;
      final out = BytesBuilder(copy: false)
        ..add(little ? const [0xFF, 0xFE] : const [0xFE, 0xFF]);
      for (final unit in text.codeUnits) {
        final lo = unit & 0xFF;
        final hi = unit >> 8;
        out.add(little ? [lo, hi] : [hi, lo]);
      }
      return out.toBytes();
    case TomTextEncoding.latin1:
      throw StateError('A Latin-1 view is never written back.');
  }
}

String _utf16(List<int> bytes, int start, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = start; i + 1 < bytes.length; i += 2) {
    units.add(littleEndian
        ? bytes[i] | (bytes[i + 1] << 8)
        : (bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}
