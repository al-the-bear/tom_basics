/// One request to a provider: the prompt, the options, the tools it may call,
/// and the facts about it the run's trail records.
library;

import 'wire.dart';

/// A tool a model may be told about.
final class ToolDescriptor {
  final String name;
  final String description;

  /// The tool's arguments as a JSON Schema object.
  final Map<String, Object?> parametersSchema;

  const ToolDescriptor({
    required this.name,
    required this.description,
    required this.parametersSchema,
  });
}

/// Tools a model may **propose** calls to; the caller decides whether to run
/// them. Contrast [LlmToolBinding], whose calls the provider makes itself.
final class ToolCatalogue {
  final List<ToolDescriptor> tools;

  const ToolCatalogue(this.tools);

  static const ToolCatalogue empty = ToolCatalogue(<ToolDescriptor>[]);

  bool get isEmpty => tools.isEmpty;
  bool get isNotEmpty => tools.isNotEmpty;
}

/// What a tool call answers the model: a result or a refusal, as text.
typedef LlmToolAnswer = ({bool isError, String text});

/// Tools a provider **runs** while the request is in flight: each call the
/// model makes is dispatched here and its answer sent back.
///
/// Per request, so whatever scope and consent the binding carries ends with
/// it. A refusal is an answer with `isError: true`, never a throw.
abstract interface class LlmToolBinding {
  /// Every tool the model may call.
  List<ToolDescriptor> get declarations;

  /// Runs [name] with [arguments] and answers the model.
  Future<LlmToolAnswer> call(String name, Map<String, Object?> arguments);
}

/// How a request is run.
final class LlmOptions {
  /// The model to use; null for the provider's default.
  final String? model;

  final double? temperature;
  final int? maxOutputTokens;
  final List<String> stopSequences;

  /// Tools the model may propose calls to.
  final ToolCatalogue toolCatalogue;

  /// A JSON Schema the answer must follow, for a provider that can enforce
  /// one.
  final Map<String, Object?>? responseFormat;

  /// The session the run belongs to: a conversation a provider continues, and
  /// the trail the run is recorded in. Null runs it in the session the
  /// provider chooses for the request's purpose.
  final String? sessionId;

  const LlmOptions({
    this.model,
    this.temperature,
    this.maxOutputTokens,
    this.stopSequences = const <String>[],
    this.toolCatalogue = ToolCatalogue.empty,
    this.responseFormat,
    this.sessionId,
  });

  static const LlmOptions empty = LlmOptions();

  LlmOptions copyWith({
    Object? model = _unset,
    Object? temperature = _unset,
    Object? maxOutputTokens = _unset,
    List<String>? stopSequences,
    ToolCatalogue? toolCatalogue,
    Object? responseFormat = _unset,
    Object? sessionId = _unset,
  }) => LlmOptions(
    model: identical(model, _unset) ? this.model : model as String?,
    temperature: identical(temperature, _unset)
        ? this.temperature
        : temperature as double?,
    maxOutputTokens: identical(maxOutputTokens, _unset)
        ? this.maxOutputTokens
        : maxOutputTokens as int?,
    stopSequences: stopSequences ?? this.stopSequences,
    toolCatalogue: toolCatalogue ?? this.toolCatalogue,
    responseFormat: identical(responseFormat, _unset)
        ? this.responseFormat
        : responseFormat as Map<String, Object?>?,
    sessionId: identical(sessionId, _unset)
        ? this.sessionId
        : sessionId as String?,
  );

  static const Object _unset = Object();
}

/// What a request's context was assembled from — never the context text.
///
/// A trail is a plaintext file a user may keep for days, so it records which
/// items the context drew on, how long it was, and what it left out; the
/// words stay in the request.
final class LlmContextSummary {
  /// The items the context drew on, by id.
  final List<String> includedIds;

  /// How many items were dropped to fit the budget.
  final int elidedCount;

  /// How many items were withheld because they may not be sent.
  final int excludedCount;

  /// The context's length in characters.
  final int length;

  const LlmContextSummary({
    this.includedIds = const [],
    this.elidedCount = 0,
    this.excludedCount = 0,
    this.length = 0,
  });

  static const none = LlmContextSummary();
}

/// One self-contained request.
final class LlmRequest {
  /// What the model is sent.
  final WirePrompt prompt;

  /// How it is run.
  final LlmOptions options;

  /// What the context was assembled from, for the trail.
  final LlmContextSummary context;

  /// The tools the provider runs while the request is in flight, or null.
  ///
  /// Only for a provider that reports [LlmCapabilities.canUseTools]: one that
  /// does not refuses a request carrying a binding rather than run an agent
  /// that cannot act while appearing to.
  final LlmToolBinding? toolBinding;

  /// Whether the run's trail is kept in memory only, never written to a file
  /// — for a request that draws on material the user keeps encrypted.
  final bool keepTrailInMemory;

  const LlmRequest({
    required this.prompt,
    this.options = LlmOptions.empty,
    this.context = LlmContextSummary.none,
    this.toolBinding,
    this.keepTrailInMemory = false,
  });

  /// What raised the request: [WirePrompt.roleId].
  String get purpose => prompt.roleId;
}
