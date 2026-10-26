/// The trail event model: what a model run did, as a closed sealed type.
///
/// Every consumer — the provider, the session manager, the trail view, the
/// trail file writer — switches over [LlmEvent] exhaustively, so a
/// new kind is a compile error in each of them rather than a silent default.
/// Every event converts to and from a map of primitives
/// ([LlmEvent.toMap], [LlmEvent.fromMap]), because a
/// session runs in its own isolate and its events cross to the main
/// isolate as messages.
///
/// An event carries what crossed the provider and nothing more. [LlmUserPrompt] names the context by section
/// id and length and never holds its text.
library;

import 'dart:async';

import 'error.dart';
import '../contract/request.dart';
import '../contract/wire.dart';

/// What kind of session a trail belongs to.
enum LlmSessionKind {
  /// An application's own session: `default`, `chat`, or one a user made.
  internal,

  /// A session bound to a quest folder — reserved.
  quest,
}

/// Why a session's isolate ended.
enum LlmSessionCloseReason {
  /// The app closed it.
  closed,

  /// It died or was stopped.
  failed,
}

/// How a run ended.
enum LlmRunOutcome { completed, cancelled, failed, timeout }

/// One thing an AI run, or the session it runs in, did.
sealed class LlmEvent {
  const LlmEvent();

  /// The event's wire name, the `kind` of [toMap].
  String get kind;

  /// The event as a map of primitives, `kind` included.
  Map<String, Object?> toMap() => {'kind': kind, ..._fields()};

  Map<String, Object?> _fields();

  /// The event [map] describes. Throws [FormatException] for a map that is
  /// not one — an unknown kind or a missing field.
  static LlmEvent fromMap(Map<String, Object?> map) {
    String text(String key) {
      final value = map[key];
      if (value is String) return value;
      throw FormatException('trail event ${map['kind']}: $key is missing');
    }

    int? count(String key) => (map[key] as num?)?.toInt();
    Duration? millis(String key) {
      final value = count(key);
      return value == null ? null : Duration(milliseconds: value);
    }

    return switch (map['kind']) {
      'sessionOpened' => LlmSessionOpened(
        sessionId: text('sessionId'),
        sessionKind: LlmSessionKind.values.byName(text('sessionKind')),
      ),
      'sessionClosed' => LlmSessionClosed(
        LlmSessionCloseReason.values.byName(text('reason')),
        message: map['message'] as String?,
      ),
      'runStarted' => LlmRunStarted(
        purpose: text('purpose'),
        providerId: text('providerId'),
        modelId: map['modelId'] as String?,
        callId: map['callId'] as String?,
      ),
      'userPrompt' => LlmUserPrompt(
        instruction: text('instruction'),
        contextSectionIds: [
          for (final id in (map['contextSectionIds'] as List? ?? const []))
            id as String,
        ],
        contextLength: count('contextLength') ?? 0,
        elidedCount: count('elidedCount') ?? 0,
        excludedCount: count('excludedCount') ?? 0,
        drawsOnEncryptedDocument: map['drawsOnEncryptedDocument'] == true,
      ),
      'systemInit' => LlmSystemInit(
        model: map['model'] as String?,
        tools: [
          for (final t in (map['tools'] as List? ?? const [])) t as String,
        ],
      ),
      'thinkingDelta' => LlmThinkingDelta(text('text')),
      'textDelta' => LlmTextDelta(text('text')),
      'toolCall' => LlmToolCall(
        callId: text('callId'),
        name: text('name'),
        arguments: (map['arguments'] as Map? ?? const {})
            .cast<String, Object?>(),
      ),
      'toolResult' => LlmToolResult(
        callId: text('callId'),
        isError: map['isError'] == true,
        text: text('text'),
        fullLength: count('fullLength') ?? text('text').length,
      ),
      'retry' => LlmRetry(
        attempt: count('attempt'),
        delay: millis('delayMs'),
        cause: map['cause'] as String?,
      ),
      'usage' => LlmUsage(
        inputTokens: count('inputTokens'),
        outputTokens: count('outputTokens'),
        cacheReadTokens: count('cacheReadTokens'),
        cacheWriteTokens: count('cacheWriteTokens'),
        costUsd: (map['costUsd'] as num?)?.toDouble(),
        apiDuration: millis('apiMs'),
        models: [
          for (final m in (map['models'] as List? ?? const []))
            LlmModelUsage.fromMap((m as Map).cast<String, Object?>()),
        ],
      ),
      'stall' => LlmStall(millis('silenceMs') ?? Duration.zero),
      'notice' => LlmNotice(text('message')),
      'error' => LlmRunError(
        LlmErrorKind.values.byName(text('errorKind')),
        text('message'),
      ),
      'runEnded' => LlmRunEnded(
        LlmRunOutcome.values.byName(text('outcome')),
        callId: map['callId'] as String?,
        rounds: count('rounds'),
        toolCalls: count('toolCalls') ?? 0,
        duration: millis('durationMs') ?? Duration.zero,
        report: map['report'] == null
            ? null
            : LlmCallReport.fromMap(
                (map['report']! as Map).cast<String, Object?>(),
              ),
        failure: map['failure'] == null
            ? null
            : LlmFailure.fromMap(
                (map['failure']! as Map).cast<String, Object?>(),
              ),
        wire: map['wire'] == null
            ? null
            : CapturedWirePrompt.fromMap(
                (map['wire']! as Map).cast<String, Object?>(),
              ),
      ),
      final kind => throw FormatException('not a trail event kind: $kind'),
    };
  }
}

/// A session's isolate started.
final class LlmSessionOpened extends LlmEvent {
  final String sessionId;
  final LlmSessionKind sessionKind;

  const LlmSessionOpened({required this.sessionId, required this.sessionKind});

  @override
  String get kind => 'sessionOpened';

  @override
  Map<String, Object?> _fields() => {
    'sessionId': sessionId,
    'sessionKind': sessionKind.name,
  };
}

/// A session's isolate ended; [message] says why when it [reason] is
/// [LlmSessionCloseReason.failed].
final class LlmSessionClosed extends LlmEvent {
  final LlmSessionCloseReason reason;
  final String? message;

  const LlmSessionClosed(this.reason, {this.message});

  @override
  String get kind => 'sessionClosed';

  @override
  Map<String, Object?> _fields() => {
    'reason': reason.name,
    if (message != null) 'message': message,
  };
}

/// A run began: what raised it, which provider serves it, and — when the
/// provider knows them at the start — the model and its own call id.
final class LlmRunStarted extends LlmEvent {
  /// What raised the request ([LlmRequest.purpose]).
  final String purpose;

  /// The provider (or transport) that serves the run.
  final String providerId;

  /// The model, when the provider resolved it before the first byte.
  final String? modelId;

  /// The provider's id for the call, when it has one.
  final String? callId;

  const LlmRunStarted({
    this.purpose = '',
    required this.providerId,
    this.modelId,
    this.callId,
  });

  @override
  String get kind => 'runStarted';

  @override
  Map<String, Object?> _fields() => {
    'purpose': purpose,
    'providerId': providerId,
    if (modelId != null) 'modelId': modelId,
    if (callId != null) 'callId': callId,
  };
}

/// The instruction a run was given, and **a summary of** its context — the
/// sections it drew on, its length, what it left out. Never the context text
///: a trail is a plaintext file a user may keep for days.
final class LlmUserPrompt extends LlmEvent {
  final String instruction;
  final List<String> contextSectionIds;
  final int contextLength;
  final int elidedCount;
  final int excludedCount;

  /// Whether the run draws on an encrypted document, so its trail is kept in
  /// memory only.
  final bool drawsOnEncryptedDocument;

  const LlmUserPrompt({
    required this.instruction,
    this.contextSectionIds = const [],
    this.contextLength = 0,
    this.elidedCount = 0,
    this.excludedCount = 0,
    this.drawsOnEncryptedDocument = false,
  });

  /// The prompt of [request]: its instruction and its context's summary.
  factory LlmUserPrompt.of(LlmRequest request) => LlmUserPrompt(
    instruction: request.prompt.user,
    contextSectionIds: request.context.includedIds,
    contextLength: request.context.length,
    elidedCount: request.context.elidedCount,
    excludedCount: request.context.excludedCount,
    drawsOnEncryptedDocument: request.keepTrailInMemory,
  );

  @override
  String get kind => 'userPrompt';

  @override
  Map<String, Object?> _fields() => {
    'instruction': instruction,
    'contextSectionIds': contextSectionIds,
    'contextLength': contextLength,
    'elidedCount': elidedCount,
    'excludedCount': excludedCount,
    if (drawsOnEncryptedDocument) 'drawsOnEncryptedDocument': true,
  };
}

/// The far end started: its model and the tools it offers. No credential and
/// no working directory — what crossed the provider and nothing more.
final class LlmSystemInit extends LlmEvent {
  final String? model;
  final List<String> tools;

  const LlmSystemInit({this.model, this.tools = const []});

  @override
  String get kind => 'systemInit';

  @override
  Map<String, Object?> _fields() => {
    if (model != null) 'model': model,
    'tools': tools,
  };
}

/// A piece of the model's thinking.
final class LlmThinkingDelta extends LlmEvent {
  final String text;

  const LlmThinkingDelta(this.text);

  @override
  String get kind => 'thinkingDelta';

  @override
  Map<String, Object?> _fields() => {'text': text};

  @override
  String toString() => 'LlmThinkingDelta(${text.length} chars)';
}

/// A piece of the answer, in order. The answer is the concatenation of a
/// run's text deltas ([llmAnswerText]).
final class LlmTextDelta extends LlmEvent {
  final String text;

  const LlmTextDelta(this.text);

  @override
  String get kind => 'textDelta';

  @override
  Map<String, Object?> _fields() => {'text': text};

  @override
  String toString() => 'LlmTextDelta(${text.length} chars)';
}

/// The model called a tool. [arguments] is the call's JSON input.
final class LlmToolCall extends LlmEvent {
  final String callId;
  final String name;
  final Map<String, Object?> arguments;

  const LlmToolCall({
    required this.callId,
    required this.name,
    this.arguments = const {},
  });

  @override
  String get kind => 'toolCall';

  @override
  Map<String, Object?> _fields() => {
    'callId': callId,
    'name': name,
    'arguments': arguments,
  };
}

/// What the tool call [callId] answered. [fullLength] is the length of the
/// whole result; a writer that clips [text] reports it.
final class LlmToolResult extends LlmEvent {
  final String callId;
  final bool isError;
  final String text;
  final int fullLength;

  const LlmToolResult({
    required this.callId,
    required this.isError,
    required this.text,
    required this.fullLength,
  });

  @override
  String get kind => 'toolResult';

  @override
  Map<String, Object?> _fields() => {
    'callId': callId,
    'isError': isError,
    'text': text,
    'fullLength': fullLength,
  };
}

/// The far end announced it will retry a failed API call.
final class LlmRetry extends LlmEvent {
  final int? attempt;
  final Duration? delay;
  final String? cause;

  const LlmRetry({this.attempt, this.delay, this.cause});

  @override
  String get kind => 'retry';

  @override
  Map<String, Object?> _fields() => {
    if (attempt != null) 'attempt': attempt,
    if (delay != null) 'delayMs': delay!.inMilliseconds,
    if (cause != null) 'cause': cause,
  };
}

/// One model's share of a run's [LlmUsage].
final class LlmModelUsage {
  final String model;
  final int? inputTokens;
  final int? outputTokens;
  final int? cacheReadTokens;
  final int? cacheWriteTokens;
  final double? costUsd;

  const LlmModelUsage({
    required this.model,
    this.inputTokens,
    this.outputTokens,
    this.cacheReadTokens,
    this.cacheWriteTokens,
    this.costUsd,
  });

  factory LlmModelUsage.fromMap(Map<String, Object?> map) => LlmModelUsage(
    model: map['model'] as String? ?? '',
    inputTokens: (map['inputTokens'] as num?)?.toInt(),
    outputTokens: (map['outputTokens'] as num?)?.toInt(),
    cacheReadTokens: (map['cacheReadTokens'] as num?)?.toInt(),
    cacheWriteTokens: (map['cacheWriteTokens'] as num?)?.toInt(),
    costUsd: (map['costUsd'] as num?)?.toDouble(),
  );

  Map<String, Object?> toMap() => {
    'model': model,
    if (inputTokens != null) 'inputTokens': inputTokens,
    if (outputTokens != null) 'outputTokens': outputTokens,
    if (cacheReadTokens != null) 'cacheReadTokens': cacheReadTokens,
    if (cacheWriteTokens != null) 'cacheWriteTokens': cacheWriteTokens,
    if (costUsd != null) 'costUsd': costUsd,
  };
}

/// What a run cost. Every field is optional: a far end reports what it has.
final class LlmUsage extends LlmEvent {
  final int? inputTokens;
  final int? outputTokens;
  final int? cacheReadTokens;
  final int? cacheWriteTokens;
  final double? costUsd;
  final Duration? apiDuration;
  final List<LlmModelUsage> models;

  const LlmUsage({
    this.inputTokens,
    this.outputTokens,
    this.cacheReadTokens,
    this.cacheWriteTokens,
    this.costUsd,
    this.apiDuration,
    this.models = const [],
  });

  @override
  String get kind => 'usage';

  @override
  Map<String, Object?> _fields() => {
    if (inputTokens != null) 'inputTokens': inputTokens,
    if (outputTokens != null) 'outputTokens': outputTokens,
    if (cacheReadTokens != null) 'cacheReadTokens': cacheReadTokens,
    if (cacheWriteTokens != null) 'cacheWriteTokens': cacheWriteTokens,
    if (costUsd != null) 'costUsd': costUsd,
    if (apiDuration != null) 'apiMs': apiDuration!.inMilliseconds,
    'models': [for (final m in models) m.toMap()],
  };
}

/// The run was abandoned because nothing arrived for [silence].
final class LlmStall extends LlmEvent {
  final Duration silence;

  const LlmStall(this.silence);

  @override
  String get kind => 'stall';

  @override
  Map<String, Object?> _fields() => {'silenceMs': silence.inMilliseconds};
}

/// Something that is neither model output nor a failure.
final class LlmNotice extends LlmEvent {
  final String message;

  const LlmNotice(this.message);

  @override
  String get kind => 'notice';

  @override
  Map<String, Object?> _fields() => {'message': message};
}

/// The run failed: its failure kind and its sentence.
final class LlmRunError extends LlmEvent {
  final LlmErrorKind errorKind;
  final String message;

  const LlmRunError(this.errorKind, this.message);

  @override
  String get kind => 'error';

  @override
  Map<String, Object?> _fields() => {
    'errorKind': errorKind.name,
    'message': message,
  };
}

/// The run is over: [LlmRunCompleted] or [LlmRunFailed]. [rounds] is the far
/// end's turn count when it reported one.
///
/// Constructed by outcome — `LlmRunEnded(outcome, …)` answers the subclass
/// the outcome calls for — so a reader that only needs to know a run ended
/// matches this type, and one that needs the report or the failure matches
/// the subclass.
sealed class LlmRunEnded extends LlmEvent {
  final LlmRunOutcome outcome;

  /// The call this run was, as [LlmRunStarted.callId] named it — so a reader
  /// holding only the terminal event can still say which call it closes.
  final String? callId;
  final int? rounds;
  final int toolCalls;
  final Duration duration;

  /// The prompt as the backend received it, when the provider captured it.
  final CapturedWirePrompt? wire;

  const LlmRunEnded._(
    this.outcome, {
    this.callId,
    this.rounds,
    this.toolCalls = 0,
    this.duration = Duration.zero,
    this.wire,
  });

  /// The subclass [outcome] calls for: a completed run needs its [report], any
  /// other outcome its [failure].
  factory LlmRunEnded(
    LlmRunOutcome outcome, {
    String? callId,
    int? rounds,
    int toolCalls = 0,
    Duration duration = Duration.zero,
    LlmCallReport? report,
    LlmFailure? failure,
    CapturedWirePrompt? wire,
  }) {
    if (outcome == LlmRunOutcome.completed) {
      if (report == null) {
        throw ArgumentError.notNull('report of a completed run');
      }
      return LlmRunCompleted(
        report: report,
        callId: callId,
        rounds: rounds,
        toolCalls: toolCalls,
        duration: duration,
        wire: wire,
      );
    }
    if (failure == null) {
      throw ArgumentError.notNull('failure of a ${outcome.name} run');
    }
    return LlmRunFailed(
      failure: failure,
      outcome: outcome,
      report: report,
      callId: callId,
      rounds: rounds,
      toolCalls: toolCalls,
      duration: duration,
      wire: wire,
    );
  }

  /// What the call cost and where it went: always present on a completed run,
  /// present on a failed one when the provider got far enough to account it.
  LlmCallReport? get report;

  /// How the call failed, classified — null for a completed run.
  LlmFailure? get failure => null;

  @override
  String get kind => 'runEnded';

  @override
  Map<String, Object?> _fields() => {
    'outcome': outcome.name,
    if (callId != null) 'callId': callId,
    if (rounds != null) 'rounds': rounds,
    'toolCalls': toolCalls,
    'durationMs': duration.inMilliseconds,
    if (report != null) 'report': report!.toMap(),
    if (failure != null) 'failure': failure!.toMap(),
    if (wire != null) 'wire': wire!.toMap(),
  };
}

/// The run completed, and [report] accounts for it.
final class LlmRunCompleted extends LlmRunEnded {
  @override
  final LlmCallReport report;

  const LlmRunCompleted({
    required this.report,
    super.callId,
    super.rounds,
    super.toolCalls,
    super.duration,
    super.wire,
  }) : super._(LlmRunOutcome.completed);
}

/// The run failed, was cancelled or went silent, for the reason [failure]
/// gives.
final class LlmRunFailed extends LlmRunEnded {
  @override
  final LlmFailure failure;

  @override
  final LlmCallReport? report;

  const LlmRunFailed({
    required this.failure,
    LlmRunOutcome outcome = LlmRunOutcome.failed,
    this.report,
    super.callId,
    super.rounds,
    super.toolCalls,
    super.duration,
    super.wire,
  }) : assert(outcome != LlmRunOutcome.completed),
       super._(outcome);
}

/// One trail entry: an [event] in the session [sessionId], the run [runId]
/// (absent for a session event), the [seq]uence number within the session and
/// the UTC time [at] it was recorded.
final class LlmTrailRecord {
  final String sessionId;
  final String? runId;
  final int seq;
  final DateTime at;
  final LlmEvent event;

  LlmTrailRecord({
    required this.sessionId,
    this.runId,
    required this.seq,
    required DateTime at,
    required this.event,
  }) : at = at.toUtc();

  Map<String, Object?> toMap() => {
    'sessionId': sessionId,
    if (runId != null) 'runId': runId,
    'seq': seq,
    'at': at.microsecondsSinceEpoch,
    'event': event.toMap(),
  };

  factory LlmTrailRecord.fromMap(Map<String, Object?> map) => LlmTrailRecord(
    sessionId: map['sessionId']! as String,
    runId: map['runId'] as String?,
    seq: (map['seq']! as num).toInt(),
    at: DateTime.fromMicrosecondsSinceEpoch(
      (map['at']! as num).toInt(),
      isUtc: true,
    ),
    event: LlmEvent.fromMap((map['event']! as Map).cast<String, Object?>()),
  );
}

/// The two events every run opens with: what it is, and what it was asked.
List<LlmEvent> llmRunPrelude(
  LlmRequest request, {
  required String providerId,
  String? modelId,
  String? callId,
}) => [
  LlmRunStarted(
    purpose: request.purpose,
    providerId: providerId,
    modelId: modelId,
    callId: callId,
  ),
  LlmUserPrompt.of(request),
];

/// The answer a run gives: the concatenation of its [LlmTextDelta]s, in
/// order (`complete` is derived from `run`).
///
/// A [LlmRunError] fails the stream with a [LlmTransportException]
/// of its kind and sentence, naming the transport the run's
/// [LlmRunStarted] named; a run that ends without one ends the text.
/// Cancelling the subscription cancels the run.
Stream<String> llmAnswerText(Stream<LlmEvent> run) {
  var transportId = 'unknown';
  return run.transform(
    StreamTransformer<LlmEvent, String>.fromHandlers(
      handleData: (event, sink) {
        switch (event) {
          case LlmRunStarted():
            transportId = event.providerId;
          case LlmTextDelta():
            if (event.text.isNotEmpty) sink.add(event.text);
          case LlmRunError():
            sink.addError(
              LlmTransportException(
                event.errorKind,
                event.message,
                transportId: transportId,
              ),
            );
          case LlmSessionOpened() ||
              LlmSessionClosed() ||
              LlmUserPrompt() ||
              LlmSystemInit() ||
              LlmThinkingDelta() ||
              LlmToolCall() ||
              LlmToolResult() ||
              LlmRetry() ||
              LlmUsage() ||
              LlmStall() ||
              LlmNotice() ||
              LlmRunEnded():
            break;
        }
      },
    ),
  );
}
