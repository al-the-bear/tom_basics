/// The result of a conditional request (`If-None-Match`).
///
/// A `304 Not Modified` is not an error and not an absence of data — it means
/// the caller's own copy is still current. Modelling it as a distinct state
/// keeps callers from having to infer that from a null payload, and carries the
/// [etag] forward so the next request can be conditional too.
///
/// Conditional responses do not count against GitHub's primary rate limit,
/// which is what makes polling many resources affordable.
class GitHubConditional<T> {
  /// The payload, or `null` when [notModified] is true.
  final T? value;

  /// The entity tag to send as `If-None-Match` on the next request.
  final String? etag;

  final bool notModified;

  const GitHubConditional.modified(this.value, {this.etag})
      : notModified = false;

  const GitHubConditional.unmodified({this.etag})
      : value = null,
        notModified = true;

  /// The payload, or [fallback] when the server said "unchanged".
  T orElse(T fallback) => notModified ? fallback : value as T;
}
