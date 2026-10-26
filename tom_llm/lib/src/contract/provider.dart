/// The provider contract.
library;

import 'dart:async';

import '../trail/account.dart';
import '../trail/error.dart';
import '../trail/event.dart';
import '../trail/sessions.dart';
import 'request.dart';
import 'wire.dart';

/// What a provider can do. A surface reads this before offering a feature,
/// and hides what the provider cannot serve rather than failing when pressed.
final class LlmCapabilities {
  /// Whether [LlmProvider.run] answers.
  final bool canComplete;

  /// Whether [LlmProvider.embed] answers.
  final bool canEmbed;

  /// Whether the provider runs an [LlmRequest.toolBinding]. False when
  /// omitted: tool use is a capability a provider claims.
  final bool canUseTools;

  /// The soft budget, in approximate tokens, for a request's context; zero
  /// when the provider states none.
  final int maxContextTokens;

  const LlmCapabilities({
    required this.canComplete,
    this.canEmbed = false,
    this.canUseTools = false,
    this.maxContextTokens = 0,
  });

  /// A provider that completes text and nothing else.
  static const completion = LlmCapabilities(canComplete: true);

  /// A provider that can do nothing — an unavailable one.
  static const none = LlmCapabilities(canComplete: false);
}

/// One model backend.
///
/// **One call.** [run] streams what the run does — from [LlmRunStarted] to
/// [LlmRunEnded], with the text, thinking, tool calls and their results,
/// retries and usage in between. A run that fails once started says so in
/// the stream ([LlmRunError], then [LlmRunEnded]) and does not error.
/// [complete] reduces a run to its report, and a provider whose backend is
/// not streaming may implement it natively; [llmAnswerText] reduces a run to
/// its text. Neither is a second request path.
///
/// **Stamps.** A run's [LlmRunStarted] names this provider's [id] and the
/// model; its [LlmRunEnded] carries the [LlmCallReport] with the same ids,
/// the prompt's anchor hash and the hash of its combined body.
///
/// **No prompt mutation.** A provider translates the prompt into its
/// backend's wire shape and adds nothing to the body.
///
/// **Availability is a gate, the reason an answer.** [isAvailable] is read on
/// every rebuild of every surface that offers a model, so it costs nothing;
/// [unavailableReason] says why it is false, in one sentence with no
/// credential and no content.
abstract class LlmProvider {
  const LlmProvider();

  /// Stable identifier of this provider instance.
  String get id;

  /// What this provider can do.
  LlmCapabilities get capabilities => LlmCapabilities.completion;

  /// Whether any request can be served now.
  bool get isAvailable => true;

  /// Why [isAvailable] is false, or null when it is true.
  String? get unavailableReason => null;

  /// The trails of the sessions this provider runs, or null for one that
  /// keeps none.
  LlmTrails? get trails => null;

  /// Runs [request] and streams what the run does. Cancelling the
  /// subscription cancels the run.
  Stream<LlmEvent> run(LlmRequest request);

  /// The report of [request]'s run. Throws an [LlmTransportException] when
  /// the run failed, carrying the provider's sentence.
  Future<LlmCallReport> complete(LlmRequest request) =>
      llmReportOf(run(request), providerId: id);

  /// An embedding vector for [text]. Throws [UnsupportedError] when
  /// [LlmCapabilities.canEmbed] is false.
  Future<List<double>> embed(String text) async =>
      throw UnsupportedError('$id offers no embeddings.');
}

/// What a build that wired no model at all says for itself — "not
/// configured", never "could not be reached", which would accuse a backend
/// nobody asked for.
const llmNotConfiguredReason = 'AI is not configured in this build.';

/// A provider that is never available.
class LlmUnavailableProvider extends LlmProvider {
  const LlmUnavailableProvider({
    this.id = 'unavailable',
    this.unavailableReason = llmNotConfiguredReason,
  });

  @override
  final String id;

  @override
  final String? unavailableReason;

  @override
  bool get isAvailable => false;

  @override
  LlmCapabilities get capabilities => LlmCapabilities.none;

  @override
  Stream<LlmEvent> run(LlmRequest request) =>
      throw UnsupportedError('No AI provider is configured.');
}

/// The report a run ends with.
///
/// Throws an [LlmTransportException] for a run that reported an
/// [LlmRunError], or ended failed, cancelled or timed out; the exception's
/// message is the run's own sentence.
Future<LlmCallReport> llmReportOf(
  Stream<LlmEvent> run, {
  required String providerId,
}) async {
  LlmRunError? error;
  LlmRunEnded? ended;
  await for (final event in run) {
    if (event is LlmRunError) error ??= event;
    if (event is LlmRunEnded) ended = event;
  }
  final report = ended?.report;
  if (error == null &&
      ended?.outcome == LlmRunOutcome.completed &&
      report != null) {
    return report;
  }
  final failure = ended?.failure;
  throw LlmTransportException(
    error?.errorKind ??
        (failure == null ? null : llmErrorKindOf(failure)) ??
        switch (ended?.outcome) {
          LlmRunOutcome.cancelled => LlmErrorKind.cancelled,
          LlmRunOutcome.timeout => LlmErrorKind.timeout,
          _ => LlmErrorKind.remote,
        },
    error?.message ??
        failure?.message ??
        (ended == null
            ? 'The run ended without an answer.'
            : 'The run ended ${ended.outcome.name} without a report.'),
    transportId: providerId,
    cause: failure?.cause,
  );
}
