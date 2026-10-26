/// Trail records folded into what a trail view shows.
library;

import 'package:test/test.dart';
import 'package:tom_llm/tom_llm.dart';

void main() {
  var seq = 0;
  LlmTrailRecord rec(String session, String? run, LlmEvent e) => LlmTrailRecord(
    sessionId: session,
    runId: run,
    seq: ++seq,
    at: DateTime.utc(2026, 10, 12, 18, 0, seq),
    event: e,
  );

  test('a run folds into header, thinking, text, a tool card '
      'with its result, more text and a summary', () {
    final entries = llmTrailEntries([
      rec(
        'default',
        'r1',
        const LlmRunStarted(purpose: 'agent', providerId: 'hosted'),
      ),
      rec(
        'default',
        'r1',
        const LlmUserPrompt(
          instruction: 'Rename it',
          contextSectionIds: ['a'],
          contextLength: 9,
        ),
      ),
      rec('default', 'r1', const LlmSystemInit(model: 'm1', tools: ['t'])),
      rec('default', 'r1', const LlmThinkingDelta('Let me ')),
      rec('default', 'r1', const LlmThinkingDelta('think.')),
      rec('default', 'r1', const LlmTextDelta('Reading')),
      rec('default', 'r1', const LlmTextDelta(' it.')),
      rec(
        'default',
        'r1',
        const LlmToolCall(
          callId: 'c1',
          name: 'webwork_get_section',
          arguments: {'id': 'a'},
        ),
      ),
      rec(
        'default',
        'r1',
        const LlmToolResult(
          callId: 'c1',
          isError: false,
          text: 'ok',
          fullLength: 2,
        ),
      ),
      rec('default', 'r1', const LlmTextDelta('Done.')),
      rec(
        'default',
        'r1',
        const LlmUsage(inputTokens: 10, outputTokens: 5, costUsd: 0.0012),
      ),
      rec(
        'default',
        'r1',
        const LlmRunCompleted(
          report: _report,
          toolCalls: 1,
          duration: Duration(milliseconds: 1500),
        ),
      ),
    ]);

    expect(
      [for (final e in entries) e.kind],
      [
        LlmTrailEntryKind.run,
        LlmTrailEntryKind.thinking,
        LlmTrailEntryKind.text,
        LlmTrailEntryKind.tool,
        LlmTrailEntryKind.text,
        LlmTrailEntryKind.summary,
      ],
    );
    final header = entries[0] as LlmTrailRunEntry;
    expect(header.instruction, 'Rename it');
    expect(header.model, 'm1');
    expect(header.purpose, 'agent');
    expect((entries[1] as LlmTrailThinkingEntry).text, 'Let me think.');
    expect((entries[2] as LlmTrailTextEntry).text, 'Reading it.');
    final tool = entries[3] as LlmTrailToolEntry;
    expect(tool.status, LlmToolStatus.done);
    expect(tool.argumentsJson, '{\n  "id": "a"\n}');
    expect((entries[4] as LlmTrailTextEntry).text, 'Done.');
    final summary = entries[5] as LlmTrailSummaryEntry;
    expect(
      summary.line,
      'completed · 1.5 s · 1 tool call · m1 · 10 in · 5 out · \$0.0012',
    );
  });

  test('two sessions interleaved keep each run\'s text in one '
      'block', () {
    final entries = llmTrailEntries([
      rec(
        'default',
        'a',
        const LlmRunStarted(purpose: 'generate', providerId: 't'),
      ),
      rec('chat', 'b', const LlmRunStarted(purpose: 'agent', providerId: 't')),
      rec('default', 'a', const LlmTextDelta('one ')),
      rec('chat', 'b', const LlmTextDelta('uno ')),
      rec('default', 'a', const LlmTextDelta('two')),
      rec('chat', 'b', const LlmTextDelta('dos')),
    ]);
    final texts = entries.whereType<LlmTrailTextEntry>().toList();
    expect(
      [for (final t in texts) '${t.sessionId}:${t.text}'],
      ['default:one two', 'chat:uno dos'],
    );
  });

  test('a running call, a failed call, retries, stalls, '
      'errors and session events', () {
    final entries = llmTrailEntries([
      rec(
        'chat',
        null,
        const LlmSessionOpened(
          sessionId: 'chat',
          sessionKind: LlmSessionKind.internal,
        ),
      ),
      rec('chat', 'r', const LlmRunStarted(purpose: 'agent', providerId: 't')),
      rec('chat', 'r', const LlmToolCall(callId: 'x', name: 'a')),
      rec('chat', 'r', const LlmToolCall(callId: 'y', name: 'b')),
      rec(
        'chat',
        'r',
        const LlmToolResult(
          callId: 'y',
          isError: true,
          text: 'E_NOT_FOUND',
          fullLength: 11,
        ),
      ),
      rec(
        'chat',
        'r',
        const LlmRetry(
          attempt: 2,
          delay: Duration(seconds: 3),
          cause: 'overloaded',
        ),
      ),
      rec('chat', 'r', const LlmStall(Duration(seconds: 120))),
      rec('chat', 'r', const LlmRunError(LlmErrorKind.timeout, 'No answer.')),
      rec(
        'chat',
        'r',
        const LlmRunFailed(failure: _failure, outcome: LlmRunOutcome.timeout),
      ),
      rec(
        'chat',
        null,
        const LlmSessionClosed(
          LlmSessionCloseReason.failed,
          message: 'stopped',
        ),
      ),
    ]);
    final tools = entries.whereType<LlmTrailToolEntry>().toList();
    expect(
      [for (final t in tools) t.status],
      [LlmToolStatus.running, LlmToolStatus.failed],
    );
    final notices = entries.whereType<LlmTrailNoticeEntry>().toList();
    expect(
      [for (final n in notices) n.noticeKind],
      [
        LlmTrailNoticeKind.session,
        LlmTrailNoticeKind.retry,
        LlmTrailNoticeKind.stall,
        LlmTrailNoticeKind.error,
        LlmTrailNoticeKind.session,
      ],
    );
    expect(notices[1].message, 'Retrying (attempt 2) in 3 s: overloaded.');
    expect(
      [for (final n in notices) n.isError],
      [false, false, true, true, true],
    );
    expect(entries.last.plainText, 'Session chat failed: stopped.');
  });

  test('every entry has plain text for Copy', () {
    final entries = llmTrailEntries([
      rec(
        'default',
        'r',
        const LlmRunStarted(purpose: 'summarize', providerId: 'hosted'),
      ),
      rec('default', 'r', const LlmUserPrompt(instruction: 'Sum up')),
      rec('default', 'r', const LlmThinkingDelta('hmm')),
      rec(
        'default',
        'r',
        const LlmToolCall(callId: 'c', name: 'n', arguments: {'k': 1}),
      ),
      rec(
        'default',
        'r',
        const LlmToolResult(
          callId: 'c',
          isError: false,
          text: 'v',
          fullLength: 1,
        ),
      ),
    ]);
    expect(entries[0].plainText, startsWith('summarize via hosted — '));
    expect(entries[0].plainText, endsWith('User: Sum up'));
    expect(entries[1].plainText, 'Thinking:\nhmm');
    expect(entries[2].plainText, 'Tool n {\n  "k": 1\n}\nResult: v');
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
