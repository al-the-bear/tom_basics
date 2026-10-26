/// A fake provider's run, built from the text it answers.
///
/// A suite that fakes [LlmProvider] decides what the model *says*; the shape
/// of a run around it — the prelude, the text deltas, how a failure and the
/// end are reported — is the provider contract's, and every fake should give
/// the same one. So it is built here once rather than in each fake.
library;

import 'dart:async';

import '../../tom_llm.dart';

/// The run of [request] whose answer is [text], from transport [transportId].
///
/// Each piece of [text] is a [LlmTextDelta]. An error [text] raises is
/// reported as the port reports a failure — a [LlmRunError] then a
/// failed [LlmRunEnded] — taking its kind and sentence from a
/// [LlmTransportException] and `protocol` and the error's type
/// otherwise. Cancelling the run cancels [text].
Stream<LlmEvent> llmFakeRun(
  LlmRequest request,
  Stream<String> text, {
  String transportId = 'fake',
}) {
  // Broadcast: a single-subscription controller whose listener is gone never
  // completes a close on a widget test's clock.
  final controller = StreamController<LlmEvent>.broadcast();
  StreamSubscription<String>? subscription;
  final clock = Stopwatch();
  final account = LlmRunAccount.of(request.prompt, providerId: transportId);

  void end(List<LlmEvent> events) {
    if (controller.isClosed) return;
    events.forEach(controller.add);
    unawaited(controller.close());
    final sub = subscription;
    subscription = null;
    if (sub != null) unawaited(sub.cancel());
  }

  controller.onListen = () {
    clock.start();
    for (final event in llmRunPrelude(request, providerId: transportId)) {
      account.observe(event);
      controller.add(event);
    }
    subscription = text.listen(
      (piece) {
        if (!controller.isClosed) controller.add(LlmTextDelta(piece));
      },
      onError: (Object error) {
        final reported = error is LlmTransportException
            ? LlmRunError(error.kind, error.message)
            : LlmRunError(LlmErrorKind.protocol, '${error.runtimeType}');
        account.observe(reported);
        end([
          reported,
          account.end(LlmRunOutcome.failed, duration: clock.elapsed),
        ]);
      },
      onDone: () =>
          end([account.end(LlmRunOutcome.completed, duration: clock.elapsed)]),
    );
  };
  controller.onCancel = () {
    final sub = subscription;
    subscription = null;
    // Not awaited: a cancel takes effect when it is called.
    if (sub != null) unawaited(sub.cancel());
  };
  return controller.stream;
}
