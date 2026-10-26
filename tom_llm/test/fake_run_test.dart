/// The fake run behind `testing.dart` has the shape of a real run: the
/// prelude, the text, and an end that says whether it completed or failed.
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tom_llm/testing.dart';
import 'package:tom_llm/tom_llm.dart';

void main() {
  group('LLM-FAKE the fake run', () {
    const request = LlmRequest(
      prompt: WirePrompt(
        system: '',
        user: 'say hello',
        anchorHash: '',
        roleId: 'test',
      ),
    );

    test(
      'LLM-FAKE-1: the text arrives as deltas and the run completes',
      () async {
        final events = await llmFakeRun(
          request,
          Stream.fromIterable(['hel', 'lo']),
        ).toList();
        expect(
          events.whereType<LlmTextDelta>().map((e) => e.text).join(),
          'hello',
        );
        expect(events.last, isA<LlmRunEnded>());
        expect((events.last as LlmRunEnded).outcome, LlmRunOutcome.completed);
      },
    );

    test('LLM-FAKE-2: a transport failure is reported with its own kind, and '
        'the run ends failed', () async {
      final events = await llmFakeRun(
        request,
        Stream.error(
          const LlmTransportException(
            LlmErrorKind.unreachable,
            'down',
            transportId: 'fake',
          ),
        ),
      ).toList();
      final error = events.whereType<LlmRunError>().single;
      expect(error.errorKind, LlmErrorKind.unreachable);
      expect((events.last as LlmRunEnded).outcome, LlmRunOutcome.failed);
    });

    test(
      'LLM-FAKE-3: any other error is a protocol failure naming its type',
      () async {
        final events = await llmFakeRun(
          request,
          Stream.error(StateError('x')),
        ).toList();
        final error = events.whereType<LlmRunError>().single;
        expect(error.errorKind, LlmErrorKind.protocol);
        expect(error.message, 'StateError');
      },
    );

    test('LLM-FAKE-4: cancelling the run cancels the text', () async {
      var cancelled = false;
      final text = StreamController<String>(onCancel: () => cancelled = true);
      final subscription = llmFakeRun(request, text.stream).listen((_) {});
      await Future<void>.delayed(Duration.zero);
      unawaited(subscription.cancel());
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
    });
  });
}
