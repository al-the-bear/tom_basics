/// What a program printed, as a bounded list of tagged lines.
///
/// `stdout` and `stderr` are kept **interleaved in arrival order**, which is
/// why a transcript is one list of tagged lines rather than two buffers:
/// interleaving reconstructed from two sequences is a guess about which write
/// came first, and the one thing a person reading a transcript needs is the
/// order the program produced it in.
library;

/// Which stream a line came from.
enum TomOutputStream {
  /// `print` and writes to standard output.
  stdout,

  /// Writes to standard error.
  stderr,
}

/// One line of output.
class TomOutputLine {
  final TomOutputStream stream;

  /// The line, without its terminator.
  final String text;

  /// When it was produced, in UTC — so a transcript carried across an isolate
  /// boundary keeps the order it was made in rather than the order it was
  /// received in.
  final DateTime at;

  TomOutputLine({required this.stream, required this.text, DateTime? at})
    : at = (at ?? DateTime.now()).toUtc();

  /// A map of primitives, for a port or a file.
  Map<String, Object?> toMap() => {
    'stream': stream.name,
    'text': text,
    'at': at.toIso8601String(),
  };

  static TomOutputLine fromMap(Map<Object?, Object?> map) => TomOutputLine(
    stream: TomOutputStream.values.byName(map['stream']! as String),
    text: map['text']! as String,
    at: DateTime.parse(map['at']! as String),
  );

  @override
  String toString() => '[${stream.name}] $text';
}

/// A program's output, bounded.
///
/// **Bounded is the point.** A runaway loop that prints is exactly the case a
/// transcript must not turn into an out-of-memory, and it is also the commonest
/// reason somebody reads one. So the cap is a *fact the reader is told* rather
/// than a silent truncation: [droppedLines] says how many lines went
/// unretained, and whatever shows the transcript has to say so.
class TomOutputTranscript {
  /// The retained lines, oldest first.
  final List<TomOutputLine> lines;

  /// How many lines were produced beyond the bound and never retained.
  ///
  /// The **oldest** are kept rather than the newest, because a transcript is
  /// read forwards: the first thing a runaway prints is what explains it, and
  /// the ten-thousandth is the same line again.
  final int droppedLines;

  const TomOutputTranscript({this.lines = const [], this.droppedLines = 0});

  static const empty = TomOutputTranscript();

  /// The default line ceiling. Large enough that an ordinary debugging session
  /// never meets it, small enough that a runaway stays in the low megabytes.
  static const maxLines = 2000;

  /// The per-line ceiling. A single line can be arbitrarily long — a program
  /// that prints a whole document makes one — and a transcript that kept it
  /// would defeat [maxLines] with one write.
  static const maxLineLength = 4000;

  bool get isEmpty => lines.isEmpty && droppedLines == 0;
  bool get isNotEmpty => !isEmpty;
  bool get truncated => droppedLines > 0;

  /// [text], clipped to [maxLineLength] with the clipping stated in the line
  /// itself — so a reader who sees a suspiciously round line knows why.
  static String clip(String text) => text.length <= maxLineLength
      ? text
      : '${text.substring(0, maxLineLength)}… '
            '(${text.length - maxLineLength} more characters)';
}

/// Collects lines up to a bound and counts the rest.
///
/// The producing side of a [TomOutputTranscript]: every line offered is either
/// kept (clipped to [TomOutputTranscript.maxLineLength]) or counted as dropped,
/// so the settled transcript states its own truncation.
class TomOutputRecorder {
  TomOutputRecorder({this.maxLines = TomOutputTranscript.maxLines});

  /// How many lines this recorder keeps.
  final int maxLines;

  final List<TomOutputLine> _lines = [];
  int _dropped = 0;

  /// How many lines were offered and not kept.
  int get droppedLines => _dropped;

  /// Offers one line. Returns the kept line, or null when the bound was
  /// reached and the line was only counted.
  TomOutputLine? add(TomOutputStream stream, String text) {
    if (_lines.length >= maxLines) {
      _dropped++;
      return null;
    }
    final line = TomOutputLine(
      stream: stream,
      text: TomOutputTranscript.clip(text),
    );
    _lines.add(line);
    return line;
  }

  /// Counts [count] lines another producer dropped before they reached this
  /// recorder.
  void countDropped(int count) => _dropped += count;

  /// The transcript so far.
  TomOutputTranscript settle() => TomOutputTranscript(
    lines: List.unmodifiable(_lines),
    droppedLines: _dropped,
  );
}
