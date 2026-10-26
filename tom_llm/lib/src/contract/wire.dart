/// What a request says to a model, and what a call reports back.
library;

/// The prompt a provider sends, in two channels.
///
/// [system] is the material the model reads first — a role's instructions,
/// an assembled context — and [user] the request itself. A backend with a
/// native system channel routes them separately; one without sends
/// [combined]. **Providers do not edit the body**: translating it into the
/// backend's wire shape is fine, adding to it or reordering it is not.
final class WirePrompt {
  /// What the model reads first; may be empty.
  final String system;

  /// The request itself; may be empty when [system] carries everything.
  final String user;

  /// The hash of an integrity anchor the producer wrapped the body in, or
  /// empty when the producer uses none. A provider stamps it on the report
  /// unchanged.
  final String anchorHash;

  /// What raised the request — a role, a feature, an integration point.
  /// Carried into the trail as the run's purpose.
  final String roleId;

  /// The content hash of the template the prompt was rendered from, when one
  /// was.
  final String? templateSha;

  const WirePrompt({
    required this.system,
    this.user = '',
    this.anchorHash = '',
    required this.roleId,
    this.templateSha,
  });

  /// The body as one text, for a backend with no system channel.
  String get combined {
    if (user.isEmpty) return system;
    if (system.isEmpty) return user;
    return '$system\n\n$user';
  }
}

/// The prompt a backend actually received, captured for an audit trail.
final class CapturedWirePrompt {
  /// The body as sent.
  final String body;

  final String anchorHash;
  final String roleId;
  final String? templateSha;

  const CapturedWirePrompt({
    required this.body,
    required this.anchorHash,
    required this.roleId,
    this.templateSha,
  });

  Map<String, Object?> toMap() => {
    'body': body,
    'anchorHash': anchorHash,
    'roleId': roleId,
    if (templateSha != null) 'templateSha': templateSha,
  };

  factory CapturedWirePrompt.fromMap(Map<String, Object?> map) =>
      CapturedWirePrompt(
        body: map['body'] as String? ?? '',
        anchorHash: map['anchorHash'] as String? ?? '',
        roleId: map['roleId'] as String? ?? '',
        templateSha: map['templateSha'] as String?,
      );
}

/// What one call cost and where it went.
///
/// A provider stamps [providerId] with its own id, [modelId] with the model
/// that answered, [promptHash] with the content hash of the prompt's
/// combined body and [anchorHash] with the prompt's anchor hash.
final class LlmCallReport {
  final String providerId;
  final String modelId;
  final String anchorHash;
  final String promptHash;
  final int tokensIn;
  final int tokensOut;
  final int retries;
  final int wallClockMs;
  final double? cost;
  final String? templateSha;
  final List<String> notes;

  const LlmCallReport({
    required this.providerId,
    required this.modelId,
    required this.anchorHash,
    required this.promptHash,
    required this.tokensIn,
    required this.tokensOut,
    required this.retries,
    required this.wallClockMs,
    this.cost,
    this.templateSha,
    this.notes = const <String>[],
  });

  Map<String, Object?> toMap() => {
    'providerId': providerId,
    'modelId': modelId,
    'anchorHash': anchorHash,
    'promptHash': promptHash,
    'tokensIn': tokensIn,
    'tokensOut': tokensOut,
    'retries': retries,
    'wallClockMs': wallClockMs,
    if (cost != null) 'cost': cost,
    if (templateSha != null) 'templateSha': templateSha,
    if (notes.isNotEmpty) 'notes': notes,
  };

  factory LlmCallReport.fromMap(Map<String, Object?> map) => LlmCallReport(
    providerId: map['providerId'] as String? ?? '',
    modelId: map['modelId'] as String? ?? '',
    anchorHash: map['anchorHash'] as String? ?? '',
    promptHash: map['promptHash'] as String? ?? '',
    tokensIn: (map['tokensIn'] as num?)?.toInt() ?? 0,
    tokensOut: (map['tokensOut'] as num?)?.toInt() ?? 0,
    retries: (map['retries'] as num?)?.toInt() ?? 0,
    wallClockMs: (map['wallClockMs'] as num?)?.toInt() ?? 0,
    cost: (map['cost'] as num?)?.toDouble(),
    templateSha: map['templateSha'] as String?,
    notes: [for (final n in (map['notes'] as List? ?? const [])) n as String],
  );
}

/// Why a call failed, classified by the provider.
final class LlmFailure {
  /// A short machine-readable class: `timeout`, `rate_limited`, `auth`, ….
  final String classCode;

  /// A sentence, safe to show and to log.
  final String message;

  /// The underlying error; not carried across an isolate.
  final Object? cause;

  const LlmFailure({
    required this.classCode,
    required this.message,
    this.cause,
  });

  Map<String, Object?> toMap() => {'classCode': classCode, 'message': message};

  factory LlmFailure.fromMap(Map<String, Object?> map) => LlmFailure(
    classCode: map['classCode'] as String? ?? '',
    message: map['message'] as String? ?? '',
  );
}
