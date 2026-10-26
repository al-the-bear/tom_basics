/// Which session a request runs in, the busy refusal, and the consolidated
/// trails.
library;

import 'package:test/test.dart';
import 'package:tom_llm/tom_llm.dart';

void main() {
  test('the agent run is chat, every other purpose default', () {
    expect(llmSessionFor(llmAgentPurpose), 'chat');
    for (final purpose in ['generate', 'summarize', 'categorize', '']) {
      expect(llmSessionFor(purpose), 'default', reason: purpose);
    }
  });

  test('the busy refusal names its session', () {
    expect(
      const LlmSessionBusyException('chat').message,
      'The chat AI session is busy.',
    );
  });

  test('records are numbered per session, timed in UTC, and '
      'say whether a run is in progress', () {
    var now = DateTime(2026, 10, 12, 16);
    final trails = LlmTrails(clock: () => now);
    addTearDown(trails.dispose);
    final seen = <String>[];
    trails.records.listen((r) => seen.add('${r.sessionId}#${r.seq}'));

    trails.record(
      'default',
      const LlmSessionOpened(
        sessionId: 'default',
        sessionKind: LlmSessionKind.internal,
      ),
    );
    trails.record(
      'default',
      const LlmRunStarted(purpose: 'generate', providerId: 't'),
      runId: 'r1',
    );
    expect(trails.isRunning('default'), isTrue);
    now = now.add(const Duration(seconds: 1));
    trails.record('chat', const LlmTextDelta('hi'), runId: 'r2');
    trails.record(
      'default',
      const LlmRunCompleted(report: _report),
      runId: 'r1',
    );
    expect(trails.isRunning('default'), isFalse);
    expect(seen, ['default#1', 'default#2', 'chat#1', 'default#3']);
    expect(trails.sessions, ['default', 'chat']);
    expect(
      trails.recordsOf('chat').single.at,
      DateTime(2026, 10, 12, 16, 0, 1).toUtc(),
    );
  });

  test('a session keeps its newest twenty runs, dropping an '
      'older run whole', () {
    final trails = LlmTrails(maxRuns: 3);
    addTearDown(trails.dispose);
    trails.record(
      'default',
      const LlmSessionOpened(
        sessionId: 'default',
        sessionKind: LlmSessionKind.internal,
      ),
    );
    for (var i = 1; i <= 5; i++) {
      trails.record(
        'default',
        const LlmRunStarted(purpose: 'generate', providerId: 't'),
        runId: 'r$i',
      );
      trails.record('default', LlmTextDelta('$i'), runId: 'r$i');
    }
    final runs = {for (final r in trails.recordsOf('default')) r.runId};
    expect(runs, {'r3', 'r4', 'r5'});

    final standard = LlmTrails();
    addTearDown(standard.dispose);
    for (var i = 1; i <= 21; i++) {
      standard.record('chat', LlmTextDelta('$i'), runId: 'r$i');
    }
    expect(
      {for (final r in standard.recordsOf('chat')) r.runId},
      {for (var i = 2; i <= 21; i++) 'r$i'},
    );
  });

  test('clearing a session drops its trail and says so; a '
      'closed store records without failing', () {
    final trails = LlmTrails();
    final changed = <String>[];
    trails.changes.listen(changed.add);
    trails.record('chat', const LlmTextDelta('x'), runId: 'r1');
    trails.clear('chat');
    expect(trails.sessions, isEmpty);
    expect(changed, ['chat', 'chat']);
    trails.dispose();
    trails.record('chat', const LlmTextDelta('y'), runId: 'r2');
    expect(trails.recordsOf('chat'), hasLength(1));
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
