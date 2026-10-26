/// pkt-line, git's framing on the wire: four hex digits of length, then data.
library;

import 'dart:convert';
import 'dart:typed_data';

/// What a pkt-line is.
enum GitPktKind {
  /// Ordinary data.
  data,

  /// `0000`: the end of a message or section list.
  flush,

  /// `0001`: separates sections (protocol v2).
  delimiter,

  /// `0002`: ends a stateless response (protocol v2).
  responseEnd,
}

/// One pkt-line.
class GitPktLine {
  const GitPktLine(this.kind, [this.bytes]);

  final GitPktKind kind;
  final Uint8List? bytes;

  bool get isData => kind == GitPktKind.data;

  /// The data as text, without its trailing newline.
  String get text {
    final s = utf8.decode(bytes ?? const [], allowMalformed: true);
    return s.endsWith('\n') ? s.substring(0, s.length - 1) : s;
  }

  @override
  String toString() => isData ? 'pkt($text)' : kind.name;
}

/// Writes pkt-lines into one request body.
class GitPktWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);

  /// One data line; text lines get their newline here.
  void text(String line) => bytes(utf8.encode('$line\n'));

  void bytes(List<int> data) {
    final length = data.length + 4;
    if (length > 65520) {
      throw ArgumentError('A pkt-line holds at most 65516 bytes');
    }
    _out
      ..add(ascii.encode(length.toRadixString(16).padLeft(4, '0')))
      ..add(data);
  }

  void flush() => _out.add(ascii.encode('0000'));
  void delimiter() => _out.add(ascii.encode('0001'));

  /// Bytes appended after the pkt-lines as they are — a packfile.
  void raw(List<int> data) => _out.add(data);

  Uint8List take() => _out.takeBytes();
}

/// Reads pkt-lines from a whole response body.
class GitPktReader {
  GitPktReader(this._bytes);

  final Uint8List _bytes;
  int _pos = 0;

  bool get atEnd => _pos >= _bytes.length;

  /// The bytes not yet read.
  Uint8List get rest => Uint8List.sublistView(_bytes, _pos);

  GitPktLine next() {
    if (_pos + 4 > _bytes.length) {
      throw const FormatException('Truncated pkt-line');
    }
    final length = int.tryParse(
      ascii.decode(_bytes.sublist(_pos, _pos + 4)),
      radix: 16,
    );
    if (length == null) {
      throw FormatException('Not a pkt-line length at $_pos');
    }
    _pos += 4;
    switch (length) {
      case 0:
        return const GitPktLine(GitPktKind.flush);
      case 1:
        return const GitPktLine(GitPktKind.delimiter);
      case 2:
        return const GitPktLine(GitPktKind.responseEnd);
    }
    if (length < 4 || _pos + length - 4 > _bytes.length) {
      throw FormatException('Bad pkt-line length $length');
    }
    final data = Uint8List.sublistView(_bytes, _pos, _pos + length - 4);
    _pos += length - 4;
    return GitPktLine(GitPktKind.data, data);
  }

  /// Data lines up to the next flush (or delimiter), the terminator consumed.
  List<GitPktLine> untilFlush() {
    final out = <GitPktLine>[];
    while (!atEnd) {
      final line = next();
      if (!line.isData) break;
      out.add(line);
    }
    return out;
  }
}

/// Side-band demultiplexing: data on band 1, progress on band 2, a fatal
/// error on band 3.
class GitSideBand {
  /// The band-1 bytes of [lines], in order; band 2 goes to [progress]; band 3
  /// throws, carrying the server's message.
  static Uint8List collect(
    Iterable<GitPktLine> lines, {
    void Function(String message)? progress,
  }) {
    final out = BytesBuilder(copy: false);
    for (final line in lines) {
      final bytes = line.bytes;
      if (!line.isData || bytes == null || bytes.isEmpty) continue;
      final payload = Uint8List.sublistView(bytes, 1);
      switch (bytes[0]) {
        case 1:
          out.add(payload);
        case 2:
          progress?.call(utf8.decode(payload, allowMalformed: true));
        case 3:
          throw GitRemoteError(utf8.decode(payload, allowMalformed: true));
        default:
          throw FormatException('Unknown side band ${bytes[0]}');
      }
    }
    return out.takeBytes();
  }
}

/// A fatal error the server sent.
class GitRemoteError implements Exception {
  GitRemoteError(this.message);

  final String message;

  @override
  String toString() => 'GitRemoteError: ${message.trim()}';
}
