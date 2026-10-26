/// The account of one run, kept from the run's own events.
///
/// A completed run carries the [LlmCallReport] it is attributed by. A provider
/// that reads its accounting off one terminal message builds the report itself;
/// one whose accounting arrives as events — the model in [LlmSystemInit], the
/// tokens and cost in [LlmUsage], each retry as an [LlmRetry] — feeds them to an
/// [LlmRunAccount] and ends the run through it, so the report says what the
/// run itself said and no producer re-derives it.
library;

import '../contract/wire.dart';
import 'error.dart';
import 'event.dart';

/// What one run has reported about itself so far, and the terminal event it
/// ends with.
final class LlmRunAccount {
  /// The provider the report attributes the run to, unless an
  /// [LlmRunStarted] names another.
  String providerId;

  /// The model, until an [LlmRunStarted] or [LlmSystemInit] names one.
  String? modelId;

  /// The anchor hash and prompt hash of the prompt the run carried; empty for
  /// a caller that wraps no anchor.
  final String anchorHash;
  final String promptHash;

  /// The template the prompt came from, when one did.
  final String? templateSha;

  String? _callId;
  int _tokensIn = 0;
  int _tokensOut = 0;
  double? _cost;
  int _retries = 0;
  int _toolCalls = 0;
  LlmRunError? _error;

  LlmRunAccount({
    required this.providerId,
    this.modelId,
    this.anchorHash = '',
    this.promptHash = '',
    this.templateSha,
  });

  /// The account of a run of [prompt] by [providerId].
  factory LlmRunAccount.of(
    WirePrompt prompt, {
    required String providerId,
    String? modelId,
    String promptHash = '',
  }) => LlmRunAccount(
    providerId: providerId,
    modelId: modelId,
    anchorHash: prompt.anchorHash,
    promptHash: promptHash,
    templateSha: prompt.templateSha,
  );

  /// The tool calls the run has made.
  int get toolCalls => _toolCalls;

  /// Takes in what [event] says about the run.
  void observe(LlmEvent event) {
    switch (event) {
      case LlmRunStarted():
        _callId = event.callId ?? _callId;
        if (event.providerId.isNotEmpty) providerId = event.providerId;
        modelId = event.modelId ?? modelId;
      case LlmSystemInit(:final model?):
        modelId = model;
      case LlmUsage():
        _tokensIn = event.inputTokens ?? _tokensIn;
        _tokensOut = event.outputTokens ?? _tokensOut;
        _cost = event.costUsd ?? _cost;
      case LlmRetry():
        _retries++;
      case LlmToolCall():
        _toolCalls++;
      case LlmRunError():
        _error ??= event;
      default:
        break;
    }
  }

  /// The report the run is attributed by, [duration] after it started.
  LlmCallReport report(Duration duration) => LlmCallReport(
    providerId: providerId,
    modelId: modelId ?? '',
    anchorHash: anchorHash,
    promptHash: promptHash,
    tokensIn: _tokensIn,
    tokensOut: _tokensOut,
    retries: _retries,
    wallClockMs: duration.inMilliseconds,
    cost: _cost,
    templateSha: templateSha,
  );

  /// The run's terminal event: completed with its report, or ended
  /// [outcome] for [failure] — by default the first [LlmRunError] the run
  /// reported, else the outcome itself.
  LlmRunEnded end(
    LlmRunOutcome outcome, {
    required Duration duration,
    int? rounds,
    LlmFailure? failure,
  }) {
    final report = this.report(duration);
    if (outcome == LlmRunOutcome.completed) {
      return LlmRunCompleted(
        report: report,
        callId: _callId,
        rounds: rounds,
        toolCalls: _toolCalls,
        duration: duration,
      );
    }
    final error = _error;
    return LlmRunFailed(
      outcome: outcome,
      failure:
          failure ??
          LlmFailure(
            classCode: error?.errorKind.name ?? outcome.name,
            message: error?.message ?? _outcomeMessage(outcome),
          ),
      report: report,
      callId: _callId,
      rounds: rounds,
      toolCalls: _toolCalls,
      duration: duration,
    );
  }

  static String _outcomeMessage(LlmRunOutcome outcome) => switch (outcome) {
    LlmRunOutcome.cancelled => 'The run was cancelled.',
    LlmRunOutcome.timeout => 'The run went silent and was abandoned.',
    _ => 'The run failed.',
  };
}

/// The [LlmErrorKind] a failed run's [LlmFailure.classCode] names, when it
/// names one.
LlmErrorKind? llmErrorKindOf(LlmFailure failure) {
  for (final kind in LlmErrorKind.values) {
    if (kind.name == failure.classCode) return kind;
  }
  return null;
}
