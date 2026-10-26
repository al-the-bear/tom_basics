/// A trail as a reader sees it — the event records folded into entries.
///
/// A record is what crossed the port, one per delta. A reader wants a run's
/// thinking as one block, its text as one block, and a tool call with its
/// result under it. The fold is here rather than in the trail view because the
/// trail file groups the same way, and two folds would disagree about
/// where one block ends.
///
/// The fold is total over the trail event kinds and keeps their order: a
/// thinking or text block is continued only while the same kind keeps arriving
/// in the same run, and anything else from that run closes it.
library;

import 'dart:convert';

import 'event.dart';

/// What an entry shows — the trail view's filter.
enum LlmTrailEntryKind {
  /// The run header: task, transport, model, instruction.
  run,

  /// The model's thinking.
  thinking,

  /// The model's answer text.
  text,

  /// A tool call with its result.
  tool,

  /// Retries, stalls, notices, errors and session events.
  notice,

  /// The run's outcome, duration, tokens and cost.
  summary,
}

/// One entry of a folded trail.
sealed class LlmTrailEntry {
  /// The session the entry belongs to.
  final String sessionId;

  /// The run, or null for a session event.
  final String? runId;

  /// When the entry's first record was made (UTC).
  final DateTime at;

  LlmTrailEntry(this.sessionId, this.runId, this.at);

  /// The filter group this entry belongs to.
  LlmTrailEntryKind get kind;

  /// The entry as plain text — what *Copy* puts on the clipboard.
  String get plainText;
}

/// A run's header: when, over which transport, for which task, and
/// what the user asked.
final class LlmTrailRunEntry extends LlmTrailEntry {
  final String purpose;
  final String providerId;
  String? _instruction;
  List<String> _contextSectionIds = const [];
  int _contextLength = 0;
  int _elided = 0;
  int _excluded = 0;
  String? _model;
  List<String> _tools = const [];

  LlmTrailRunEntry._(
    super.sessionId,
    super.runId,
    super.at, {
    required this.purpose,
    required this.providerId,
  });

  /// The user's instruction, once the run reported it.
  String? get instruction => _instruction;

  /// The sections the context drew on, by id — never their text.
  List<String> get contextSectionIds => _contextSectionIds;

  /// The context's length in characters.
  int get contextLength => _contextLength;

  /// Sections cut from the context for length.
  int get elidedCount => _elided;

  /// Sections left out because AI is off for them.
  int get excludedCount => _excluded;

  /// The model the far end reported.
  String? get model => _model;

  /// The tools the far end offered.
  List<String> get tools => _tools;

  @override
  LlmTrailEntryKind get kind => LlmTrailEntryKind.run;

  @override
  String get plainText => [
    '$purpose via $providerId'
        '${_model == null ? '' : ' ($_model)'} — ${at.toIso8601String()}',
    if (_instruction != null) 'User: $_instruction',
    if (_contextSectionIds.isNotEmpty || _contextLength > 0)
      'Context: ${_contextSectionIds.length} section(s), '
          '$_contextLength characters',
  ].join('\n');
}

/// The model's thinking, deltas joined.
final class LlmTrailThinkingEntry extends LlmTrailEntry {
  final StringBuffer _text = StringBuffer();

  LlmTrailThinkingEntry._(super.sessionId, super.runId, super.at);

  String get text => _text.toString();

  @override
  LlmTrailEntryKind get kind => LlmTrailEntryKind.thinking;

  @override
  String get plainText => 'Thinking:\n$text';
}

/// The model's answer text, deltas joined.
final class LlmTrailTextEntry extends LlmTrailEntry {
  final StringBuffer _text = StringBuffer();

  LlmTrailTextEntry._(super.sessionId, super.runId, super.at);

  String get text => _text.toString();

  @override
  LlmTrailEntryKind get kind => LlmTrailEntryKind.text;

  @override
  String get plainText => text;
}

/// Where a tool call is.
enum LlmToolStatus {
  /// No result yet.
  running,

  /// The tool answered.
  done,

  /// The tool answered with an error.
  failed,
}

/// A tool call and, once it arrived, its result.
final class LlmTrailToolEntry extends LlmTrailEntry {
  final String callId;
  final String name;
  final Map<String, Object?> arguments;
  LlmToolResult? _result;

  LlmTrailToolEntry._(
    super.sessionId,
    super.runId,
    super.at, {
    required this.callId,
    required this.name,
    required this.arguments,
  });

  /// The result, or null while the call is running.
  LlmToolResult? get result => _result;

  LlmToolStatus get status => switch (_result) {
    null => LlmToolStatus.running,
    LlmToolResult(isError: true) => LlmToolStatus.failed,
    _ => LlmToolStatus.done,
  };

  /// The arguments as indented JSON; a value JSON cannot hold is its text.
  String get argumentsJson =>
      const JsonEncoder.withIndent('  ', _jsonText).convert(arguments);

  static Object? _jsonText(Object? value) => value.toString();

  @override
  LlmTrailEntryKind get kind => LlmTrailEntryKind.tool;

  @override
  String get plainText => [
    'Tool $name $argumentsJson',
    switch (_result) {
      null => '(running)',
      final r => '${r.isError ? 'Error' : 'Result'}: ${r.text}',
    },
  ].join('\n');
}

/// What a notice entry reports.
enum LlmTrailNoticeKind { session, retry, stall, notice, error }

/// A line between the blocks: a retry, a stall, a notice, an error, or a
/// session opening or closing.
final class LlmTrailNoticeEntry extends LlmTrailEntry {
  final LlmTrailNoticeKind noticeKind;
  final String message;

  /// Whether the line reports a failure, which a view shows in the error
  /// colour.
  final bool isError;

  LlmTrailNoticeEntry._(
    super.sessionId,
    super.runId,
    super.at, {
    required this.noticeKind,
    required this.message,
    this.isError = false,
  });

  @override
  LlmTrailEntryKind get kind => LlmTrailEntryKind.notice;

  @override
  String get plainText => message;
}

/// A run's last line: its outcome, how long it took, and what it cost.
final class LlmTrailSummaryEntry extends LlmTrailEntry {
  final LlmRunOutcome outcome;
  final Duration duration;
  final int toolCalls;
  final int? rounds;

  /// The model, from the far end's start.
  final String? model;

  /// The run's usage, when the far end reported one.
  final LlmUsage? usage;

  LlmTrailSummaryEntry._(
    super.sessionId,
    super.runId,
    super.at, {
    required this.outcome,
    required this.duration,
    required this.toolCalls,
    required this.rounds,
    required this.model,
    required this.usage,
  });

  @override
  LlmTrailEntryKind get kind => LlmTrailEntryKind.summary;

  /// The summary as one line: `completed · 1.2 s · 2 tool calls · …`.
  String get line {
    final u = usage;
    final seconds = (duration.inMilliseconds / 1000).toStringAsFixed(1);
    return [
      outcome.name,
      '$seconds s',
      '$toolCalls tool call${toolCalls == 1 ? '' : 's'}',
      if (rounds != null) '$rounds round${rounds == 1 ? '' : 's'}',
      ?model,
      if (u?.inputTokens != null) '${u!.inputTokens} in',
      if (u?.outputTokens != null) '${u!.outputTokens} out',
      if (u?.cacheReadTokens case final read? when read > 0) '$read cached',
      if (u?.costUsd != null) '\$${u!.costUsd!.toStringAsFixed(4)}',
    ].join(' · ');
  }

  @override
  String get plainText => line;
}

/// The words for a silence of [silence].
String _seconds(Duration silence) =>
    '${(silence.inMilliseconds / 1000).toStringAsFixed(0)} s';

/// Folds [records] into entries, in the order their first record arrived.
///
/// Records from several sessions may be interleaved (the trail view's **All**
/// tab): each run's blocks are continued across the interleaving, so a text
/// block holds one run's text however another session's records arrived
/// between its deltas.
List<LlmTrailEntry> llmTrailEntries(Iterable<LlmTrailRecord> records) {
  final entries = <LlmTrailEntry>[];
  // Per run: the header, the block still being continued, the tool calls by
  // id, the usage reported so far.
  final headers = <String, LlmTrailRunEntry>{};
  final open = <String, LlmTrailEntry>{};
  final calls = <String, LlmTrailToolEntry>{};
  final usage = <String, LlmUsage>{};

  String key(LlmTrailRecord r) => '${r.sessionId}\u0000${r.runId}';

  LlmTrailRunEntry header(
    LlmTrailRecord r, {
    String purpose = '',
    String providerId = '',
  }) => headers.putIfAbsent(key(r), () {
    final entry = LlmTrailRunEntry._(
      r.sessionId,
      r.runId,
      r.at,
      purpose: purpose,
      providerId: providerId,
    );
    entries.add(entry);
    return entry;
  });

  void add(LlmTrailRecord r, LlmTrailEntry entry) {
    open.remove(key(r));
    entries.add(entry);
  }

  void notice(
    LlmTrailRecord r,
    LlmTrailNoticeKind kind,
    String message, {
    bool isError = false,
  }) => add(
    r,
    LlmTrailNoticeEntry._(
      r.sessionId,
      r.runId,
      r.at,
      noticeKind: kind,
      message: message,
      isError: isError,
    ),
  );

  for (final r in records) {
    switch (r.event) {
      case LlmSessionOpened(:final sessionKind):
        notice(
          r,
          LlmTrailNoticeKind.session,
          'Session ${r.sessionId} opened (${sessionKind.name}).',
        );
      case LlmSessionClosed(:final reason, :final message):
        final failed = reason == LlmSessionCloseReason.failed;
        notice(
          r,
          LlmTrailNoticeKind.session,
          'Session ${r.sessionId} ${failed ? 'failed' : 'closed'}'
          '${message == null ? '' : ': $message'}.',
          isError: failed,
        );
      case LlmRunStarted(:final purpose, :final providerId):
        open.remove(key(r));
        header(r, purpose: purpose, providerId: providerId);
      case final LlmUserPrompt prompt:
        header(r)
          .._instruction = prompt.instruction
          .._contextSectionIds = prompt.contextSectionIds
          .._contextLength = prompt.contextLength
          .._elided = prompt.elidedCount
          .._excluded = prompt.excludedCount;
      case LlmSystemInit(:final model, :final tools):
        header(r)
          .._model = model
          .._tools = tools;
      case LlmThinkingDelta(:final text):
        final current = open[key(r)];
        if (current is LlmTrailThinkingEntry) {
          current._text.write(text);
        } else {
          final block = LlmTrailThinkingEntry._(r.sessionId, r.runId, r.at)
            .._text.write(text);
          entries.add(block);
          open[key(r)] = block;
        }
      case LlmTextDelta(:final text):
        final current = open[key(r)];
        if (current is LlmTrailTextEntry) {
          current._text.write(text);
        } else {
          final block = LlmTrailTextEntry._(r.sessionId, r.runId, r.at)
            .._text.write(text);
          entries.add(block);
          open[key(r)] = block;
        }
      case LlmToolCall(:final callId, :final name, :final arguments):
        final call = LlmTrailToolEntry._(
          r.sessionId,
          r.runId,
          r.at,
          callId: callId,
          name: name,
          arguments: arguments,
        );
        calls['${key(r)}\u0000$callId'] = call;
        add(r, call);
      case final LlmToolResult result:
        final call = calls['${key(r)}\u0000${result.callId}'];
        if (call == null) {
          // A result whose call this trail does not hold — its run was trimmed
          // to the newest runs mid-way. Shown, not dropped.
          final orphan = LlmTrailToolEntry._(
            r.sessionId,
            r.runId,
            r.at,
            callId: result.callId,
            name: '(unknown tool)',
            arguments: const {},
          ).._result = result;
          add(r, orphan);
        } else {
          call._result = result;
          open.remove(key(r));
        }
      case LlmRetry(:final attempt, :final delay, :final cause):
        notice(
          r,
          LlmTrailNoticeKind.retry,
          'Retrying'
          '${attempt == null ? '' : ' (attempt $attempt)'}'
          '${delay == null ? '' : ' in ${_seconds(delay)}'}'
          '${cause == null ? '' : ': $cause'}.',
        );
      case LlmStall(:final silence):
        notice(
          r,
          LlmTrailNoticeKind.stall,
          'Nothing arrived for ${_seconds(silence)}; the run was abandoned.',
          isError: true,
        );
      case LlmNotice(:final message):
        notice(r, LlmTrailNoticeKind.notice, message);
      case LlmRunError(:final message):
        notice(r, LlmTrailNoticeKind.error, message, isError: true);
      case final LlmUsage reported:
        usage[key(r)] = reported;
      case LlmRunEnded(
        :final outcome,
        :final duration,
        :final toolCalls,
        :final rounds,
      ):
        add(
          r,
          LlmTrailSummaryEntry._(
            r.sessionId,
            r.runId,
            r.at,
            outcome: outcome,
            duration: duration,
            toolCalls: toolCalls,
            rounds: rounds,
            model: headers[key(r)]?.model,
            usage: usage[key(r)],
          ),
        );
    }
  }
  return entries;
}
