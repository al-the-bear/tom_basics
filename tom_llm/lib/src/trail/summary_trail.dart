/// a quest session's prompts and answers history, in the format
/// the VS Code extension writes and reads (`<q>.<session>.prompts.md`,
/// `<q>.<session>.answers.md` in the quest's `history/` folder).
///
/// Each file holds entries newest first. An entry is a header line
/// `=== PROMPT <requestId> <ISO time> <sequence> ===` (or `ANSWER`), a blank
/// line, the body and a blank line; a prompt's body is followed by the
/// extension's `TEMPLATE:` and `ANSWER-WRAPPER:` footer. The sequence counts
/// up from the newest entry's, and a file past its bound loses its oldest
/// entry — the extension's `writeSummaryPrompt` / `writeSummaryAnswer`
/// restated over a string.
library;

/// Which file of the pair.
enum LlmSummaryTrailKind {
  prompt('PROMPT', 'prompts'),
  answer('ANSWER', 'answers');

  /// The header keyword.
  final String keyword;

  /// The file-name part: `<q>.<session>.<part>.md`.
  final String part;

  const LlmSummaryTrailKind(this.keyword, this.part);
}

/// The extension's bound on a summary file's entries.
const int llmSummaryTrailMaxEntries = 1000;

/// The file name of [kind] for session [sessionId] of the quest named
/// [quest]: `<q>.<session>.prompts.md` or `.answers.md`.
String llmSummaryTrailFileName(
  String quest,
  String sessionId,
  LlmSummaryTrailKind kind,
) => '$quest.$sessionId.${kind.part}.md';

final RegExp _firstHeader = RegExp(
  r'^===\s+(?:PROMPT|ANSWER)\s+\S+\s+\S+\s+(\d+)\s+===',
);
final RegExp _anyHeader = RegExp(r'^===\s+(?:PROMPT|ANSWER)');

/// The ISO-8601 instant the extension writes: UTC, milliseconds, `Z`.
String llmSummaryTrailTimestamp(DateTime at) {
  final u = at.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final ms = u.millisecond.toString().padLeft(3, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}.${ms}Z';
}

/// [existing] with a new [kind] entry for [requestId] at [at] prepended, the
/// sequence one past the newest entry's, and the oldest entry dropped when
/// the sequence passes [maxEntries].
String llmSummaryTrailPrepend(
  String existing, {
  required LlmSummaryTrailKind kind,
  required String requestId,
  required DateTime at,
  required String body,
  int maxEntries = llmSummaryTrailMaxEntries,
}) {
  final first = existing.split('\n').first;
  final sequence =
      (int.tryParse(_firstHeader.firstMatch(first)?.group(1) ?? '') ?? 0) + 1;
  final header =
      '=== ${kind.keyword} $requestId '
      '${llmSummaryTrailTimestamp(at)} $sequence ===';
  final entry = switch (kind) {
    LlmSummaryTrailKind.prompt =>
      '$header\n\n$body\n\n'
          'TEMPLATE: (none)\nANSWER-WRAPPER: no\n\n',
    LlmSummaryTrailKind.answer => '$header\n\n$body\n\n',
  };
  final text = '$entry$existing';
  if (sequence <= maxEntries) return text;
  final lines = text.split('\n');
  for (var i = lines.length - 1; i > 0; i--) {
    if (_anyHeader.hasMatch(lines[i])) {
      return '${lines.sublist(0, i).join('\n').trimRight()}\n';
    }
  }
  return text;
}
