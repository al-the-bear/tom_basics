/// A session's trail file — `live-trail.<session>.md` — in the Tom VS Code
/// extension's live-trail entry format, so the extension's Logs panel and any
/// quest view read it with the parser they already have.
///
/// [LlmLiveTrailText] is the extension's writer (`LiveTrailWriter`)
/// restated over a string, operation for operation: a prompt block opens with
/// its header and the user's line, thinking and assistant text continue under
/// one heading while the same kind keeps arriving, a tool call is a JSON block
/// and its result a `<details>` block, and every write leaves the file ending
/// in a newline — which is why streamed deltas land on lines of their own in
/// the extension's files. The fixture under
/// `test/fixtures/live_trail/` is what the extension's own writer produced for
/// the same calls, and the test holds the two byte for byte.
///
/// [LlmLiveTrailSession] maps a session's trail records onto those
/// operations and holds the two bounds the extension does not have: the
/// file's size and a run that alone exceeds it. It hands the writer streamed
/// thinking and text **a line at a time**: the writer ends every write with a
/// newline, so a delta written as it came would cut words in two wherever the
/// model's stream did ("num" / "bers"), and Markdown renders those breaks as
/// spaces.
library;

import 'dart:convert';

import 'event.dart';

/// The file a session's trail is written to: `live-trail.<session>.md`.
///
/// The session id is in the name, so the file never collides with the
/// extension's own unsuffixed live-trail files when the trail directory is a
/// quest folder.
String llmLiveTrailFileName(String sessionId) =>
    'live-trail.${sessionId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')}.md';

/// One live-trail file's text, changed by the extension's writer operations.
class LlmLiveTrailText {
  /// The file's first line.
  static const header = '<!-- tom-ai live-trail -->';

  /// The line that opens a prompt block.
  static const _promptPrefix = '## 🚀 PROMPT ';

  /// How many prompt blocks the file keeps (the extension's
  /// `MAX_PROMPT_BLOCKS`).
  static const maxRuns = 5;

  /// The clipping of the user's instruction, a tool's arguments and a tool's
  /// result — the extension's preview lengths.
  static const _userPreview = 1000;
  static const _toolInputPreview = 2000;
  static const _toolResultPreview = 800;

  String _file;
  bool _inAssistant = false;
  bool _inThinking = false;

  /// The text, starting from the file as it was found ([existing], empty for
  /// a file that does not exist).
  LlmLiveTrailText([String existing = '']) : _file = existing;

  /// The file's text.
  String get text => _file;

  /// How many prompt blocks the text holds.
  int get _runCount => const LineSplitter()
      .convert(_file)
      .where((l) => l.startsWith(_promptPrefix))
      .length;

  /// Opens a prompt block, dropping the oldest so that [maxRuns] remain.
  void beginPrompt({
    required String transport,
    required String config,
    required String userText,
    required DateTime at,
  }) {
    final trimmed = _file.isEmpty
        ? '$header\n'
        : (_trimToKeep(maxRuns - 1) ?? _file);
    _inAssistant = false;
    _inThinking = false;
    final preview = clip(
      userText,
      _userPreview,
    ).replaceAll(RegExp(r'\r?\n'), '\n> ');
    final lines = [
      trimmed.trim(),
      '',
      '$_promptPrefix${llmLiveTrailTimestamp(at)} [$transport / $config]',
      '',
      '> User: $preview',
      '',
    ];
    if (lines.first.isEmpty) lines.removeAt(0);
    _write(lines.join('\n'));
  }

  void appendThinking(String text) {
    if (text.isEmpty) return;
    final body = _inThinking ? text : '\n### 🧠 thinking\n\n$text';
    _inThinking = true;
    _inAssistant = false;
    _append(body);
  }

  void appendAssistantText(String text) {
    if (text.isEmpty) return;
    final body = _inAssistant ? text : '\n### 💬 assistant\n\n$text';
    _inAssistant = true;
    _inThinking = false;
    _append(body);
  }

  void beginToolCall(String name, Map<String, Object?> input, String callId) {
    _reset();
    final json = clip(
      const JsonEncoder.withIndent('  ', _jsonText).convert(input),
      _toolInputPreview,
    );
    _append('\n### 🔧 $name [$callId]\n\n```json\n$json\n```\n');
  }

  static Object? _jsonText(Object? value) => value.toString();

  void appendToolResult(String preview, int fullLength) {
    _reset();
    final note = fullLength > _toolResultPreview ? ' — preview' : '';
    _append(
      '\n<details><summary>📤 result ($fullLength chars)$note</summary>\n\n'
      '```text\n${clip(preview, _toolResultPreview)}\n```\n\n</details>\n',
    );
  }

  void appendRetry(String message, [String? cause]) {
    if (message.isEmpty) return;
    final causeBlock = cause == null || cause.isEmpty
        ? '\n'
        : '\n\n```text\n${clip(cause, 1000)}\n```\n';
    _append('\n### 🔁 retry\n\n$message$causeBlock');
    _reset();
  }

  void appendNotice(String message) {
    if (message.isEmpty) return;
    _append('\n### ⏳ notice\n\n$message\n');
    _reset();
  }

  /// The usage block; nothing when [usage] reports nothing.
  void appendUsage(LlmUsage usage, DateTime at) {
    final block = llmLiveTrailUsage(usage, at);
    if (block.isEmpty) return;
    _append(block);
    _reset();
  }

  void endPrompt({
    required int rounds,
    required int toolCalls,
    required int ms,
  }) {
    _append('\n\n### ✅ DONE (rounds=$rounds, toolCalls=$toolCalls, ${ms}ms)\n');
    _reset();
  }

  void endPromptWithError(String message) {
    _append('\n\n### ⚠️ ERROR\n\n```text\n${clip(message, 2000)}\n```\n');
    _reset();
  }

  /// The extension's cancelled interruption banner.
  void endPromptCancelled(String message) {
    _append('\n\n### ⏹️ CANCELLED\n\n```text\n${clip(message, 2000)}\n```\n');
    _reset();
  }

  /// Drops the oldest prompt block, when there is more than one. Answers
  /// whether it did.
  bool dropOldestRun() {
    final runs = _runCount;
    if (runs <= 1) return false;
    _file = _trimToKeep(runs - 1)!;
    return true;
  }

  void _reset() {
    _inAssistant = false;
    _inThinking = false;
  }

  void _write(String content) {
    final body = content.startsWith(header) ? content : '$header\n\n$content';
    _file = body.endsWith('\n') ? body : '$body\n';
  }

  void _append(String content) {
    final next = (_file.isNotEmpty ? _file : '$header\n\n') + content;
    _file = next.endsWith('\n') ? next : '$next\n';
  }

  String? _trimToKeep(int keep) {
    if (_file.isEmpty) return null;
    final lines = _file.split(RegExp(r'\r?\n'));
    final starts = [
      for (var i = 0; i < lines.length; i++)
        if (lines[i].startsWith(_promptPrefix)) i,
    ];
    if (starts.length <= keep) return null;
    final from = starts[starts.length - keep];
    return '$header\n\n${lines.sublist(from).join('\n')}';
  }

  /// [s] cut to [max] characters, marked as the extension marks it.
  static String clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}\n…(trimmed)';
}

/// `YYYYMMDD_HHMMSS` in local time — the prompt header's stamp.
String llmLiveTrailTimestamp(DateTime at) {
  final d = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}${two(d.month)}${two(d.day)}_'
      '${two(d.hour)}${two(d.minute)}${two(d.second)}';
}

/// [n] with thousands separators (`12,412`), as the extension's
/// `toLocaleString('en-US')` writes it; empty for null.
String _count(int? n) {
  if (n == null) return '';
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// The extension's `### 📊 usage` block for [usage], recorded at [at]; empty
/// when there is nothing to say.
String llmLiveTrailUsage(LlmUsage usage, DateTime at) {
  final lines = <String>[];
  final counts = [
    if (usage.inputTokens != null) 'in ${_count(usage.inputTokens)}',
    if (usage.outputTokens != null) 'out ${_count(usage.outputTokens)}',
    if (usage.cacheReadTokens != null)
      'cache read ${_count(usage.cacheReadTokens)}',
    if (usage.cacheWriteTokens != null)
      'cache write ${_count(usage.cacheWriteTokens)}',
  ];
  if (counts.isNotEmpty) lines.add('- tokens: ${counts.join(' · ')}');
  final meta = [
    if (usage.costUsd case final cost? when cost.isFinite)
      '\$${cost.toStringAsFixed(4)}',
    if (usage.apiDuration case final api?)
      'api ${(api.inMilliseconds / 1000).toStringAsFixed(1)}s',
  ];
  if (meta.isNotEmpty) lines.add('- cost: ${meta.join(' · ')}');
  if (usage.models.isNotEmpty) {
    final stamp = llmLiveTrailTimestamp(at);
    lines
      ..add('')
      ..add(
        '| model | in | out | cache read | cache write | cost | ctx | when |',
      )
      ..add('| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |');
    for (final m in usage.models) {
      final c = m.costUsd;
      final cost = c != null && c.isFinite ? '\$${c.toStringAsFixed(4)}' : '';
      lines.add(
        '| ${m.model} | ${_count(m.inputTokens)} | '
        '${_count(m.outputTokens)} | ${_count(m.cacheReadTokens)} | '
        '${_count(m.cacheWriteTokens)} | $cost |  | $stamp |',
      );
    }
  }
  if (lines.isEmpty) return '';
  return '\n### 📊 usage\n\n${lines.join('\n')}\n';
}

/// The words of a retry, as the trail file writes them.
String llmLiveTrailRetryMessage(LlmRetry retry) =>
    'Retrying'
    '${retry.attempt == null ? '' : ' (attempt ${retry.attempt})'}'
    '${retry.delay == null ? '' : ' in ${(retry.delay!.inMilliseconds / 1000).toStringAsFixed(0)} s'}'
    '.';

/// The words of a stall, as the trail file writes them.
String llmLiveTrailStallMessage(LlmStall stall) =>
    'Nothing arrived for ${(stall.silence.inMilliseconds / 1000).toStringAsFixed(0)} s; '
    'the run was abandoned.';

/// The words of a cancelled run, as the trail file writes them.
const String llmLiveTrailCancelledMessage = 'The run was cancelled.';

/// One session's trail file: its text, and the records of the run in
/// progress mapped onto it.
///
/// The file keeps at most [maxBytes] bytes as well as [LlmLiveTrailText.maxRuns]
/// runs: older runs are dropped whole. A run that alone outgrows the bound
/// keeps its beginning, says in a notice that the rest is not recorded, and
/// still gets its closing block.
class LlmLiveTrailSession {
  /// The file's size bound, in UTF-8 bytes.
  final int maxBytes;

  /// Room kept under [maxBytes] for the notice and the closing block of a run
  /// that has stopped recording its output.
  static const int _closingRoom = 4096;

  final LlmLiveTrailText _text;
  LlmRunStarted? _started;
  DateTime? _startedAt;
  bool _opened = false;
  bool _clipped = false;
  String? _error;

  /// Streamed thinking or text whose line has not ended yet.
  final StringBuffer _pending = StringBuffer();

  /// Whether [_pending] is thinking rather than assistant text.
  bool _pendingThinking = false;

  LlmLiveTrailSession({String existing = '', this.maxBytes = 1 << 20})
    : _text = LlmLiveTrailText(existing);

  /// The file's text.
  String get text => _text.text;

  /// Applies [record]. Answers whether the text changed.
  bool apply(LlmTrailRecord record) {
    final before = _text.text;
    final event = record.event;
    if (event is! LlmThinkingDelta && event is! LlmTextDelta) {
      _flushPending();
    }
    switch (event) {
      case final LlmRunStarted started:
        _started = started;
        _startedAt = record.at;
        _opened = false;
        _clipped = false;
        _error = null;
      case LlmUserPrompt(:final instruction):
        _open(instruction);
      case LlmThinkingDelta(:final text):
        _stream(text, thinking: true);
      case LlmTextDelta(:final text):
        _stream(text, thinking: false);
      case LlmToolCall(:final name, :final arguments, :final callId):
        _output(() => _text.beginToolCall(name, arguments, callId));
      case LlmToolResult(:final text, :final fullLength):
        _output(() => _text.appendToolResult(text, fullLength));
      case final LlmRetry retry:
        _output(
          () => _text.appendRetry(llmLiveTrailRetryMessage(retry), retry.cause),
        );
      case LlmNotice(:final message):
        _output(() => _text.appendNotice(message));
      case final LlmStall stall:
        _output(() => _text.appendNotice(llmLiveTrailStallMessage(stall)));
      case LlmRunError(:final message):
        _error = message;
      case final LlmUsage usage:
        _open('');
        _text.appendUsage(usage, record.at);
      case final LlmRunEnded ended:
        _open('');
        switch (ended.outcome) {
          case LlmRunOutcome.completed:
            _text.endPrompt(
              rounds: ended.rounds ?? 0,
              toolCalls: ended.toolCalls,
              ms: ended.duration.inMilliseconds,
            );
          case LlmRunOutcome.cancelled:
            _text.endPromptCancelled(llmLiveTrailCancelledMessage);
          case LlmRunOutcome.failed || LlmRunOutcome.timeout:
            _text.endPromptWithError(
              _error ?? 'The run ${ended.outcome.name}.',
            );
        }
        _started = null;
      case LlmSessionOpened() || LlmSessionClosed() || LlmSystemInit():
        break;
    }
    _bound();
    return _text.text != before;
  }

  /// Adds a streamed delta, writing every line it completes.
  void _stream(String text, {required bool thinking}) {
    if (text.isEmpty) return;
    if (_pendingThinking != thinking) _flushPending();
    _pendingThinking = thinking;
    _pending.write(text);
    final held = _pending.toString();
    final end = held.lastIndexOf('\n');
    if (end < 0) return;
    _pending
      ..clear()
      ..write(held.substring(end + 1));
    _writeStreamed(held.substring(0, end + 1), thinking: thinking);
  }

  /// Writes what is held of a line, at the end of its block.
  void _flushPending() {
    if (_pending.isEmpty) return;
    final held = _pending.toString();
    _pending.clear();
    _writeStreamed(held, thinking: _pendingThinking);
  }

  void _writeStreamed(String text, {required bool thinking}) => _output(
    () =>
        thinking ? _text.appendThinking(text) : _text.appendAssistantText(text),
  );

  /// Opens the run's block, once.
  void _open(String instruction) {
    if (_opened) return;
    _opened = true;
    final started = _started;
    _text.beginPrompt(
      transport: started?.providerId ?? '',
      config: started?.purpose ?? '',
      userText: instruction,
      at: _startedAt ?? DateTime.now(),
    );
  }

  /// Records a piece of the run's output — unless the run has outgrown the
  /// file, in which case the first refusal is said once.
  void _output(void Function() write) {
    _open('');
    if (_clipped) return;
    final before = _text.text;
    write();
    if (_bytes(_text.text) <= maxBytes - _closingRoom) return;
    // Drop older runs first; only a run that alone does not fit is clipped.
    while (_bytes(_text.text) > maxBytes - _closingRoom &&
        _text.dropOldestRun()) {}
    if (_bytes(_text.text) <= maxBytes - _closingRoom) return;
    _text
      .._file = before
      .._reset();
    _clipped = true;
    _text.appendNotice(
      'This run reached the trail file\'s '
      '${maxBytes ~/ 1024} KiB bound; the rest of its output is not '
      'recorded here.',
    );
  }

  void _bound() {
    while (_bytes(_text.text) > maxBytes && _text.dropOldestRun()) {}
  }

  static int _bytes(String s) => utf8.encode(s).length;
}
