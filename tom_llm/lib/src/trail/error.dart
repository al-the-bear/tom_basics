/// The one failure type a provider's run carries.
///
/// It lives beside the contract rather than beside the transports that raise
/// it, because the surface that shows a failure has to recognise it: it shows
/// the user [LlmTransportException.message] and nothing else. A type a
/// surface cannot name is one it can only render through `toString()` — a log
/// line, carrying a class name, a transport id and an enum member.
library;

/// Why a transport call failed. Callers switch on this rather than on message
/// text; the message is for the user and the diagnostics log, the kind is for
/// control flow.
enum LlmErrorKind {
  /// This transport cannot serve: nothing listening, discovery found no
  /// matching endpoint, the child process refused to start, or the runtime it
  /// needs is present but below the version floor. This is the only kind that
  /// means "degrade to unavailable" rather than "this request failed"
  ///.
  ///
  /// The last of those is a *configuration* fault the user can fix rather than
  /// a backend that is down, and it is deliberately **not** a kind of its own.
  /// The two facts differ for a reader and not for a caller: this enum exists
  /// for control flow — the comment above says so — and the control flow is
  /// identical, because an under-floor runtime is permanent until the machine
  /// changes and so must close the gate exactly as an absent server does. A
  /// second kind would need the availability gate's rule widened to name it, would
  /// oblige the one place that branches here to test two values instead of
  /// one, and would change no behaviour at all. What the user needs is in the
  /// [LlmTransportException.message], which names the version found and
  /// the version required.
  unreachable,

  /// A server answered but broke the wire contract (unparseable frame,
  /// unknown message shape, a chunk for an unknown stream).
  protocol,

  /// The far end reported a failure of the model call itself — an invalid
  /// credential, a rate limit, a refused request.
  remote,

  /// The caller cancelled, or the transport was closed under a live request.
  cancelled,

  /// The far end accepted the request and then went quiet past the deadline.
  timeout,
}

/// The single error type crossing the seam.
class LlmTransportException implements Exception {
  /// What went wrong, in machine-readable form.
  final LlmErrorKind kind;

  /// A human-readable explanation, safe to show and safe to log: it must never
  /// contain document content or a credential.
  final String message;

  /// The id of the transport that failed, for diagnostics.
  final String transportId;

  /// The underlying error, if any. Not shown to the user.
  final Object? cause;

  const LlmTransportException(
    this.kind,
    this.message, {
    required this.transportId,
    this.cause,
  });

  @override
  String toString() =>
      'LlmTransportException($transportId, ${kind.name}): $message';
}
