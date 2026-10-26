/// The run event model: a closed sealed type that crosses an isolate as
/// primitives, the answer text a run reduces to, and no event carrying the
/// context text.
library;

import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:tom_llm/tom_llm.dart';

/// One of every event, each field set.
final List<LlmEvent> _everyKind = [
  const LlmSessionOpened(
    sessionId: 'default',
    sessionKind: LlmSessionKind.internal,
  ),
  const LlmSessionClosed(LlmSessionCloseReason.failed, message: 'stopped'),
  const LlmRunStarted(purpose: 'agent', providerId: 'hosted'),
  const LlmUserPrompt(
    instruction: 'Summarize.',
    contextSectionIds: ['a', 'b'],
    contextLength: 120,
    elidedCount: 1,
    excludedCount: 2,
  ),
  const LlmSystemInit(model: 'claude', tools: ['webwork_get_section']),
  const LlmThinkingDelta('Let me see.'),
  const LlmTextDelta('Hello.'),
  const LlmToolCall(
    callId: 't1',
    name: 'webwork_update_section',
    arguments: {
      'sectionId': 'a',
      'headline': '409',
      'nested': {'n': 1},
    },
  ),
  const LlmToolResult(
    callId: 't1',
    isError: true,
    text: 'E_NOT_FOUND',
    fullLength: 11,
  ),
  const LlmRetry(
    attempt: 2,
    delay: Duration(seconds: 4),
    cause: 'HTTP 529: server_error',
  ),
  const LlmUsage(
    inputTokens: 10,
    outputTokens: 20,
    cacheReadTokens: 30,
    cacheWriteTokens: 40,
    costUsd: 0.25,
    apiDuration: Duration(milliseconds: 1500),
    models: [
      LlmModelUsage(
        model: 'claude',
        inputTokens: 10,
        outputTokens: 20,
        cacheReadTokens: 30,
        cacheWriteTokens: 40,
        costUsd: 0.25,
      ),
    ],
  ),
  const LlmStall(Duration(seconds: 120)),
  const LlmNotice('Waiting for background tasks.'),
  const LlmRunError(LlmErrorKind.timeout, 'Silent.'),
  const LlmRunCompleted(
    report: _report,
    rounds: 3,
    toolCalls: 1,
    duration: Duration(milliseconds: 4200),
  ),
];

/// Through JSON and back, as an isolate message would be after encoding.
LlmEvent _roundTrip(LlmEvent event) => LlmEvent.fromMap(
  (jsonDecode(jsonEncode(event.toMap())) as Map).cast<String, Object?>(),
);

void main() {
  test('fifteen kinds, each named once', () {
    final kinds = [for (final e in _everyKind) e.kind];
    expect(kinds.toSet(), hasLength(15));
    expect(kinds, [
      'sessionOpened',
      'sessionClosed',
      'runStarted',
      'userPrompt',
      'systemInit',
      'thinkingDelta',
      'textDelta',
      'toolCall',
      'toolResult',
      'retry',
      'usage',
      'stall',
      'notice',
      'error',
      'runEnded',
    ]);
  });

  test('every event round-trips through primitives', () {
    for (final event in _everyKind) {
      final back = _roundTrip(event);
      expect(back.runtimeType, event.runtimeType, reason: event.kind);
      expect(back.toMap(), event.toMap(), reason: event.kind);
    }
  });

  test('an event with only its required fields round-trips ', () {
    for (final event in [
      const LlmSessionClosed(LlmSessionCloseReason.closed),
      const LlmSystemInit(),
      const LlmRetry(),
      const LlmUsage(),
      const LlmRunFailed(failure: _failure, outcome: LlmRunOutcome.cancelled),
    ]) {
      expect(_roundTrip(event).toMap(), event.toMap(), reason: event.kind);
    }
  });

  test('a map that is not an event is refused', () {
    expect(
      () => LlmEvent.fromMap(const {'kind': 'nope'}),
      throwsFormatException,
    );
    expect(
      () => LlmEvent.fromMap(const {'kind': 'textDelta'}),
      throwsFormatException,
    );
  });

  test('a record carries its envelope and keeps time in UTC ', () {
    final record = LlmTrailRecord(
      sessionId: 'chat',
      runId: 'r7',
      seq: 42,
      at: DateTime.utc(2026, 10, 12, 15, 30, 1, 2, 3).toLocal(),
      event: const LlmTextDelta('Hi.'),
    );
    final back = LlmTrailRecord.fromMap(
      (jsonDecode(jsonEncode(record.toMap())) as Map).cast<String, Object?>(),
    );
    expect(back.sessionId, 'chat');
    expect(back.runId, 'r7');
    expect(back.seq, 42);
    expect(back.at, DateTime.utc(2026, 10, 12, 15, 30, 1, 2, 3));
    expect(back.at.isUtc, isTrue);
    expect((back.event as LlmTextDelta).text, 'Hi.');
  });

  test('the prelude names the purpose and provider, and summarizes the '
      'context without its text', () {
    const context = '# Chapter\n\nThe secret plan is in the garden.';
    const request = LlmRequest(
      prompt: WirePrompt(
        system: context,
        user: 'Summarize the chapter.',
        anchorHash: '',
        roleId: 'summarize',
      ),
      context: LlmContextSummary(
        includedIds: ['c1'],
        elidedCount: 2,
        excludedCount: 1,
        length: 44,
      ),
    );
    final prelude = llmRunPrelude(request, providerId: 'standalone');
    final started = prelude.first as LlmRunStarted;
    expect(started.purpose, 'summarize');
    expect(started.providerId, 'standalone');
    final prompt = prelude.last as LlmUserPrompt;
    expect(prompt.instruction, 'Summarize the chapter.');
    expect(prompt.contextSectionIds, ['c1']);
    expect(prompt.contextLength, context.length);
    expect(prompt.elidedCount, 2);
    expect(prompt.excludedCount, 1);
    expect(
      jsonEncode([for (final e in prelude) e.toMap()]),
      isNot(contains('secret plan')),
      reason: 'the context text is in no record',
    );
  });

  test('the answer is the text deltas; a run error fails it '
      'naming the transport', () async {
    final ok = llmAnswerText(
      Stream.fromIterable(const [
        LlmRunStarted(purpose: 'generate', providerId: 'hosted'),
        LlmThinkingDelta('hmm'),
        LlmTextDelta('Hel'),
        LlmTextDelta('lo.'),
        LlmRunCompleted(report: _report),
      ]),
    );
    expect(await ok.join(), 'Hello.');

    final failed = llmAnswerText(
      Stream.fromIterable(const [
        LlmRunStarted(purpose: 'generate', providerId: 'hosted'),
        LlmTextDelta('Hel'),
        LlmRunError(LlmErrorKind.remote, 'Overloaded.'),
        LlmRunFailed(failure: _failure, outcome: LlmRunOutcome.failed),
      ]),
    );
    await expectLater(
      failed.join(),
      throwsA(
        isA<LlmTransportException>()
            .having((e) => e.kind, 'kind', LlmErrorKind.remote)
            .having((e) => e.message, 'message', 'Overloaded.')
            .having((e) => e.transportId, 'transportId', 'hosted'),
      ),
    );
  });

  test('cancelling the answer cancels the run', () async {
    var cancelled = false;
    final run = StreamController<LlmEvent>(onCancel: () => cancelled = true);
    final subscription = llmAnswerText(run.stream).listen((_) {});
    run.add(const LlmTextDelta('Hel'));
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    expect(cancelled, isTrue);
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
