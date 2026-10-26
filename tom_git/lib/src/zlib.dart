/// zlib, as git uses it: loose objects and packfile entries are zlib streams.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

/// [data] as one zlib stream.
Uint8List gitDeflate(List<int> data) => const ZLibEncoder().encodeBytes(data);

/// The zlib stream that starts at [offset] in [bytes], inflated, and how many
/// bytes of [bytes] it occupied.
///
/// A packfile concatenates zlib streams without stating their lengths, so the
/// end of one entry is only known by inflating it: the consumed length is the
/// two-byte header, the deflate data the inflater read, and the four-byte
/// Adler-32 trailer. [expectedSize] — the size the entry header states — is
/// checked, so a stream that inflates to anything else is refused.
({Uint8List data, int consumed}) gitInflateAt(
  Uint8List bytes,
  int offset, {
  int? expectedSize,
}) {
  if (offset + 2 > bytes.length) {
    throw const FormatException('Truncated zlib stream');
  }
  final cmf = bytes[offset];
  final flg = bytes[offset + 1];
  if ((cmf & 0x0f) != 8 || ((cmf << 8) | flg) % 31 != 0) {
    throw FormatException('Not a zlib stream at offset $offset');
  }
  if (flg & 0x20 != 0) {
    throw const FormatException('A zlib preset dictionary is not supported');
  }
  final input = InputMemoryStream(bytes, offset: offset + 2);
  final inflate = Inflate.stream(input, uncompressedSize: expectedSize);
  final data = inflate.getBytes();
  if (expectedSize != null && data.length != expectedSize) {
    throw FormatException(
      'A zlib stream at offset $offset inflated to '
      '${data.length} bytes, not $expectedSize',
    );
  }
  return (data: data, consumed: 2 + input.position + 4);
}

/// A whole zlib stream, inflated.
Uint8List gitInflate(Uint8List bytes) => gitInflateAt(bytes, 0).data;
