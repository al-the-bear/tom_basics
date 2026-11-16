// The Tom LLM provider contract, shown with an in-process provider that
// answers with what it was asked. No model is called and nothing leaves the
// process.
//
// The program writes a provider against `LlmProvider`, runs a request through
// it as a stream of events, reduces the run to its text and to its report,
// records the run in a session trail and folds it into trail entries, shows
// how a failed run surfaces as an `LlmTransportException`, and how a build
// without a model reports itself.
//
// Run from the package folder:
//
//   dart run example/tom_llm_example.dart

import 'package:tom_llm/tom_llm.dart';

/// A provider that answers with the user channel of its prompt, word by word,
/// and records every run in its session trail.
class EchoProvider extends LlmProvider {
  final LlmTrails _trails = LlmTrails();
  int _runs = 0;

  @override
  String get id => 'echo';

  @override
  LlmTrails get trails => _trails;

  @override
  Stream<LlmEvent> run(LlmRequest request) async* {
    final session = request.options.sessionId ?? request.purpose;
    final runId = 'run-${++_runs}';
    final account = LlmRunAccount.of(
      request.prompt,
      providerId: id,
      modelId: 'echo-1',
    );
    final clock = Stopwatch()..start();

    LlmEvent emit(LlmEvent event) {
      account.observe(event);
      _trails.record(session, event, runId: runId);
      return event;
    }

    // Every run opens with the prelude: LlmRunStarted, then LlmUserPrompt.
    for (final event in llmRunPrelude(
      request,
      providerId: id,
      modelId: 'echo-1',
    )) {
      yield emit(event);
    }
    final words = request.prompt.user.split(' ');
    for (var i = 0; i < words.length; i++) {
      yield emit(LlmTextDelta(i == 0 ? words[i] : ' ${words[i]}'));
    }
    yield emit(LlmUsage(inputTokens: words.length, outputTokens: words.length));
    // ... and ends with exactly one LlmRunEnded, here completed with a report.
    yield emit(account.end(LlmRunOutcome.completed, duration: clock.elapsed));
  }
}

/// A provider whose every run fails once started: it reports the failure in
/// the stream (LlmRunError, then a failed LlmRunEnded) rather than throwing.
class FailingProvider extends LlmProvider {
  @override
  String get id => 'failing';

  @override
  Stream<LlmEvent> run(LlmRequest request) async* {
    final account = LlmRunAccount.of(request.prompt, providerId: id);
    for (final event in llmRunPrelude(request, providerId: id)) {
      account.observe(event);
      yield event;
    }
    const error = LlmRunError(
      LlmErrorKind.unreachable,
      'The echo backend is not listening.',
    );
    account.observe(error);
    yield error;
    yield account.end(LlmRunOutcome.failed, duration: Duration.zero);
  }
}

LlmRequest requestFor(String user) => LlmRequest(
  prompt: WirePrompt(
    system: 'You answer briefly.',
    user: user,
    anchorHash: '',
    roleId: 'example',
  ),
  options: const LlmOptions(sessionId: 'demo'),
);

Future<void> main() async {
  final echo = EchoProvider();
  print('provider     : ${echo.id}, available: ${echo.isAvailable}');
  // provider     : echo, available: true

  // 1. A run is a stream of typed events.
  final events = await echo.run(requestFor('Say hello to Tom')).toList();
  print('events       : ${events.map((e) => e.kind).join(', ')}');
  // events       : runStarted, userPrompt, textDelta, textDelta, textDelta,
  //                textDelta, usage, runEnded

  // 2. The same run reduced to its answer text ...
  final text = await llmAnswerText(echo.run(requestFor('Hello, Tom'))).join();
  print('answer text  : $text'); // answer text  : Hello, Tom

  // 3. ... or to the report every completed run is attributed by.
  final report = await echo.complete(requestFor('One two three'));
  print(
    'report       : provider ${report.providerId}, model ${report.modelId}, '
    'tokens ${report.tokensIn} in / ${report.tokensOut} out',
  );
  // report       : provider echo, model echo-1, tokens 3 in / 3 out

  // 4. Every event converts to a map of primitives and back.
  final map = events.first.toMap();
  final restored = LlmEvent.fromMap(map) as LlmRunStarted;
  print('round trip   : ${restored.kind} for ${restored.purpose}');
  // round trip   : runStarted for example

  // 5. The provider kept the runs in its trails; fold them into entries.
  final records = echo.trails.recordsOf('demo');
  final entries = llmTrailEntries(records);
  print('trail        : ${records.length} records in session "demo"');
  // trail        : 21 records in session "demo"
  print('entries      : ${entries.map((e) => e.kind.name).join(', ')}');
  // entries      : run, text, summary, run, text, summary, run, text, summary

  // 6. A failed run is not a stream error; `complete` turns it into an
  //    LlmTransportException carrying the provider's own sentence.
  try {
    await FailingProvider().complete(requestFor('Anyone there?'));
  } on LlmTransportException catch (e) {
    print('failure      : ${e.kind.name} from ${e.transportId}: ${e.message}');
    // failure      : unreachable from failing: The echo backend is not
    //                listening.
  }

  // 7. A build without a model says so instead of failing when pressed.
  const none = LlmUnavailableProvider();
  print('unavailable  : ${none.isAvailable} — ${none.unavailableReason}');
  // unavailable  : false — AI is not configured in this build.
}
