/// A session's trail file in the VS Code extension's
/// live-trail format, byte for byte, and its two bounds.
///
/// The fixtures under `test/fixtures/live_trail/` were written by the
/// extension's own `LiveTrailWriter` (its compiled `out/`) driven through the
/// same scenario by `tool/live_trail_fixture/generate.js`; regenerate them
/// with that script when the extension's format changes.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_llm/tom_llm.dart';

String _fixture(String name) =>
    File('test/fixtures/live_trail/$name').readAsStringSync();

/// The records of the generator's scenario: run 1 with every block kind, a
/// stalled run that failed, a cancelled run, then [shortRuns] short runs.
List<LlmTrailRecord> _scenario({int shortRuns = 0}) {
  final records = <LlmTrailRecord>[];
  var seq = 0;
  void add(String run, int minute, LlmEvent e) => records.add(
    LlmTrailRecord(
      sessionId: 'default',
      runId: run,
      seq: ++seq,
      at: DateTime(2026, 10, 12, 14, minute).toUtc(),
      event: e,
    ),
  );

  add(
    'r1',
    30,
    const LlmRunStarted(purpose: 'agent', providerId: 'hosted-cli'),
  );
  add(
    'r1',
    30,
    const LlmUserPrompt(
      instruction: 'Rename the plan section.\nKeep its children.',
    ),
  );
  add('r1', 30, const LlmSystemInit(model: 'claude-sonnet-4-5'));
  add('r1', 30, const LlmThinkingDelta('Let me '));
  add('r1', 30, const LlmThinkingDelta('look first.'));
  add('r1', 30, const LlmTextDelta('Reading the section.'));
  add(
    'r1',
    30,
    const LlmToolCall(
      callId: 'c1',
      name: 'webwork_get_section',
      arguments: {'sectionId': '7f3c9e21', 'depth': 1},
    ),
  );
  add(
    'r1',
    30,
    const LlmToolResult(
      callId: 'c1',
      isError: false,
      text: '# Plan\nThree beds.',
      fullLength: 18,
    ),
  );
  add(
    'r1',
    30,
    LlmToolCall(
      callId: 'c2',
      name: 'webwork_update_section',
      arguments: {'sectionId': '7f3c9e21', 'headline': 'x' * 2100},
    ),
  );
  add(
    'r1',
    30,
    LlmToolResult(
      callId: 'c2',
      isError: false,
      text: 'y' * 900,
      fullLength: 5000,
    ),
  );
  add('r1', 30, const LlmRetry(attempt: 2, cause: 'HTTP 529 overloaded'));
  add('r1', 30, const LlmNotice('Waiting for background tasks.'));
  add('r1', 30, const LlmThinkingDelta('Now rename.'));
  add('r1', 30, const LlmTextDelta('Renamed **Plan**.'));
  add(
    'r1',
    31,
    const LlmUsage(
      inputTokens: 12412,
      outputTokens: 318,
      cacheReadTokens: 2000,
      cacheWriteTokens: 0,
      costUsd: 0.0119,
      apiDuration: Duration(milliseconds: 5200),
      models: [
        LlmModelUsage(
          model: 'claude-sonnet-4-5',
          inputTokens: 12412,
          outputTokens: 318,
          cacheReadTokens: 2000,
          cacheWriteTokens: 0,
          costUsd: 0.0119,
        ),
      ],
    ),
  );
  add(
    'r1',
    31,
    const LlmRunCompleted(
      report: _report,
      rounds: 3,
      toolCalls: 2,
      duration: Duration(milliseconds: 6400),
    ),
  );

  add(
    'r2',
    32,
    const LlmRunStarted(purpose: 'summarize', providerId: 'standalone-node'),
  );
  add('r2', 32, const LlmUserPrompt(instruction: 'Summarize.'));
  add('r2', 32, const LlmStall(Duration(seconds: 120)));
  add(
    'r2',
    32,
    const LlmRunError(
      LlmErrorKind.timeout,
      'No answer from the AI server for 120 seconds.',
    ),
  );
  add(
    'r2',
    32,
    const LlmRunFailed(failure: _failure, outcome: LlmRunOutcome.timeout),
  );

  add(
    'r3',
    33,
    const LlmRunStarted(purpose: 'generate', providerId: 'hosted-cli'),
  );
  add('r3', 33, const LlmUserPrompt(instruction: 'Write an intro.'));
  add('r3', 33, const LlmTextDelta('Once'));
  add(
    'r3',
    33,
    const LlmRunFailed(failure: _failure, outcome: LlmRunOutcome.cancelled),
  );

  for (var i = 4; i < 4 + shortRuns; i++) {
    add(
      'r$i',
      30 + i,
      const LlmRunStarted(purpose: 'categorize', providerId: 'hosted-cli'),
    );
    add('r$i', 30 + i, LlmUserPrompt(instruction: 'Run $i.'));
    add('r$i', 30 + i, LlmTextDelta('Answer $i.'));
    add(
      'r$i',
      30 + i,
      LlmRunCompleted(
        report: _report,
        rounds: 1,
        duration: Duration(seconds: i),
      ),
    );
  }
  return records;
}

String _render(List<LlmTrailRecord> records, {String existing = ''}) {
  final session = LlmLiveTrailSession(existing: existing);
  records.forEach(session.apply);
  return session.text;
}

void main() {
  test('every block kind is written exactly as the '
      'extension writes it', () {
    expect(_render(_scenario()), _fixture('extension_kinds.md'));
  });

  test('the file keeps the newest five runs, whole, as the '
      'extension does', () {
    expect(_render(_scenario(shortRuns: 4)), _fixture('extension_rolling.md'));
  });

  test('a file found on disk is continued, not replaced ', () {
    final all = _scenario(shortRuns: 4);
    // Runs 1–3 written by an earlier process, runs 4–7 by this one.
    final cut = all.indexWhere((r) => r.runId == 'r4');
    final earlier = _render(all.sublist(0, cut));
    expect(
      _render(all.sublist(cut), existing: earlier),
      _fixture('extension_rolling.md'),
    );
  });

  test('older runs are dropped whole to stay under the size '
      'bound; a run that alone outgrows it is clipped with a notice and still '
      'closed', () {
    var seq = 0;
    LlmTrailRecord r(String run, LlmEvent e) => LlmTrailRecord(
      sessionId: 's',
      runId: run,
      seq: ++seq,
      at: DateTime(2026, 10, 12, 15).toUtc(),
      event: e,
    );
    final session = LlmLiveTrailSession(maxBytes: 64 * 1024);
    for (final run in ['a', 'b']) {
      session
        ..apply(
          r(run, const LlmRunStarted(purpose: 'generate', providerId: 't')),
        )
        ..apply(r(run, LlmUserPrompt(instruction: 'Run $run')))
        ..apply(r(run, LlmTextDelta('${run * 20000}\n')))
        ..apply(r(run, const LlmRunCompleted(report: _report)));
    }
    // Two runs of 20 kB fit in 64 KiB; the third pushes the first out.
    session
      ..apply(r('c', const LlmRunStarted(purpose: 'generate', providerId: 't')))
      ..apply(r('c', const LlmUserPrompt(instruction: 'Run c')))
      ..apply(r('c', LlmTextDelta('${'c' * 30000}\n')));
    expect(session.text, isNot(contains('User: Run a')));
    expect(session.text, contains('User: Run b'));
    expect(utf8.encode(session.text).length, lessThanOrEqualTo(64 * 1024));

    // A run that alone does not fit: older runs go, then it is clipped.
    for (var i = 0; i < 10; i++) {
      session.apply(r('c', LlmTextDelta('${'d' * 10000}\n')));
    }
    session.apply(
      r(
        'c',
        const LlmRunCompleted(
          report: _report,
          toolCalls: 0,
          duration: Duration(seconds: 2),
        ),
      ),
    );
    final text = session.text;
    expect(text, isNot(contains('User: Run b')));
    expect(RegExp('## 🚀 PROMPT').allMatches(text), hasLength(1));
    expect(text, contains('the rest of its output is not recorded here.'));
    expect(text, contains('### ✅ DONE (rounds=0, toolCalls=0, 2000ms)'));
    expect(utf8.encode(text).length, lessThanOrEqualTo(64 * 1024));
  });

  test('the file name carries the session id', () {
    expect(llmLiveTrailFileName('default'), 'live-trail.default.md');
    expect(llmLiveTrailFileName('chat'), 'live-trail.chat.md');
    expect(llmLiveTrailFileName('a/b c'), 'live-trail.a_b_c.md');
  });

  test('streamed thinking and text are written a line at a '
      'time, so a word split across deltas stays whole; a line is written as '
      'soon as it ends', () {
    var seq = 0;
    LlmTrailRecord r(LlmEvent e) => LlmTrailRecord(
      sessionId: 's',
      runId: 'a',
      seq: ++seq,
      at: DateTime(2026, 10, 12, 15).toUtc(),
      event: e,
    );
    final session = LlmLiveTrailSession()
      ..apply(r(const LlmRunStarted(purpose: 'summarize', providerId: 't')))
      ..apply(r(const LlmUserPrompt(instruction: 'Sum up.')));
    expect(
      session.apply(r(const LlmThinkingDelta('I am checking num'))),
      isFalse,
      reason: 'half a line is held back',
    );
    expect(
      session.apply(r(const LlmThinkingDelta('bers above 380.\nThen'))),
      isTrue,
      reason: 'a finished line is written at once',
    );
    expect(session.text, endsWith('I am checking numbers above 380.\n'));
    session
      ..apply(r(const LlmThinkingDelta(' I sum.')))
      ..apply(r(const LlmTextDelta('The ans')))
      ..apply(r(const LlmTextDelta('wer.')))
      ..apply(r(const LlmRunCompleted(report: _report)));
    final text = session.text;
    expect(text, contains('above 380.\nThen I sum.\n'));
    expect(text, contains('### 💬 assistant\n\nThe answer.\n'));
    expect(text, isNot(contains('num\nbers')));
  });
}

const _report = LlmCallReport(
  providerId: 'fake',
  modelId: '',
  anchorHash: '',
  promptHash: '',
  tokensIn: 0,
  tokensOut: 0,
  retries: 0,
  wallClockMs: 0,
);

const _failure = LlmFailure(classCode: 'failed', message: 'The run failed.');
